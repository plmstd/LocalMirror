import Darwin
import Foundation

private actor LineAccumulator {
    private var lines: [String] = []

    func append(_ line: String) {
        lines.append(line)
    }

    func snapshot() -> [String] {
        lines
    }
}

final class RsyncSyncEngine: SyncEngine, @unchecked Sendable {
    private struct ExecutionResult {
        var binaryPath: String
        var arguments: [String]
        var startedAt: Date
        var finishedAt: Date
        var terminationStatus: Int32
        var terminationReason: CommandTerminationReason
        var stdout: [String]
        var stderr: [String]
    }

    private struct StandardOutputChannel {
        var readDescriptor: Int32
        var parentWriteHandle: FileHandle
        var retainedReadHandle: FileHandle?
        var shouldCloseReadDescriptor: Bool
    }

    private let locator: RsyncBinaryLocator
    private let environment: [String: String]
    private let stateQueue = DispatchQueue(label: "LocalMirror.RsyncSyncEngine")

    private var currentProcess: Process?
    private var cancellationRequested = false

    init(locator: RsyncBinaryLocator = RsyncBinaryLocator()) {
        self.locator = locator
        self.environment = ProcessInfo.processInfo.environment.merging(["LANG": "C", "LC_ALL": "C"]) { _, new in new }
    }

    var isRunning: Bool {
        stateQueue.sync { currentProcess?.isRunning == true }
    }

    func validateInstallation() throws -> SyncInstallation {
        try locator.locate()
    }

    func preflight(
        pair: BackupPair,
        exclusions: [String],
        eventHandler: (@Sendable (SyncPreflightEvent) async -> Void)?
    ) async throws -> SyncPreflightResult {
        let installation = try validateInstallation()
        let arguments = makeArguments(dryRun: true, pair: pair, exclusions: exclusions)
        let result = try await execute(
            installation: installation,
            arguments: arguments,
            liveEventHandler: { event in
                guard let eventHandler else { return }
                switch event {
                case .started(let date):
                    await eventHandler(.started(date))
                case .changeDetected(let change):
                    await eventHandler(.plannedChange(change))
                case .appliedChange(let change):
                    if change.operation != .create && change.operation != .update {
                        await eventHandler(.plannedChange(change))
                    }
                case .warning(let message):
                    await eventHandler(.warning(message))
                case .info(let message):
                    await eventHandler(.info(message))
                case .transferProgress:
                    break
                }
            }
        )
        guard result.terminationReason == .exit, result.terminationStatus == 0 else {
            let diagnostics = CommandDiagnostics(
                phase: "preflight",
                binaryPath: result.binaryPath,
                arguments: arguments,
                startedAt: result.startedAt,
                finishedAt: result.finishedAt,
                terminationStatus: result.terminationStatus,
                terminationReason: result.terminationReason,
                stdoutLines: result.stdout,
                stderrLines: result.stderr
            )
            throw BackupError.preflightFailed(preflightFailureMessage(for: diagnostics), diagnostics)
        }
        return RsyncOutputParser.parsePreflight(stdout: result.stdout, stderr: result.stderr)
    }

    func run(
        pair: BackupPair,
        plannedChanges: [ChangeRecord],
        exclusions: [String],
        eventHandler: @escaping @Sendable (SyncRunEvent) async -> Void
    ) async throws -> SyncRunCompletion {
        let installation = try validateInstallation()
        let arguments = makeArguments(dryRun: false, pair: pair, exclusions: exclusions)
        let logID = UUID()
        let result = try await execute(
            installation: installation,
            arguments: arguments,
            liveEventHandler: eventHandler
        )
        let wasCancelled = stateQueue.sync { cancellationRequested }
        return RsyncOutputParser.parseRun(
            stdout: result.stdout,
            stderr: result.stderr,
            pairID: pair.id,
            startedAt: result.startedAt,
            finishedAt: result.finishedAt,
            exitCode: result.terminationStatus,
            wasCancelled: wasCancelled,
            textLogRelativePath: "\(logID.uuidString).log",
            plannedChanges: plannedChanges
        )
    }

    func requestCancellation() async {
        let process = stateQueue.sync { () -> Process? in
            cancellationRequested = true
            return currentProcess
        }

        guard let process, process.isRunning else { return }
        process.interrupt()

        Task.detached {
            try? await Task.sleep(for: .seconds(3))
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private func makeArguments(dryRun: Bool, pair: BackupPair, exclusions: [String]) -> [String] {
        var arguments = ["-a", "--delete-delay", "--itemize-changes", "--out-format=ITEM|%i|%n%L", "--stats"]
        if dryRun {
            arguments.insert("-n", at: 0)
        } else {
            arguments.append("--progress")
        }
        for exclusion in exclusions {
            arguments.append(contentsOf: ["--exclude", exclusion])
        }
        arguments.append(ensureTrailingSlash(pair.sourceCanonicalPath))
        arguments.append(pair.targetCanonicalPath)
        return arguments
    }

    private func ensureTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    private func execute(
        installation: SyncInstallation,
        arguments: [String],
        liveEventHandler: (@Sendable (SyncRunEvent) async -> Void)?
    ) async throws -> ExecutionResult {
        let process = Process()
        process.executableURL = installation.binaryURL
        process.arguments = arguments
        process.environment = environment

        let stdoutChannel = try makeStandardOutputChannel(usePseudoTerminal: arguments.contains("--progress"))
        let stderrPipe = Pipe()
        process.standardOutput = stdoutChannel.parentWriteHandle
        process.standardError = stderrPipe.fileHandleForWriting

        let stdoutLines = LineAccumulator()
        let stderrLines = LineAccumulator()

        stateQueue.sync {
            self.currentProcess = process
            self.cancellationRequested = false
        }

        let startedAt = Date()

        let stdoutTask = Task<ChangeRecord?, Error> {
            var inFlightTransferChange: ChangeRecord?

            defer {
                if stdoutChannel.shouldCloseReadDescriptor {
                    close(stdoutChannel.readDescriptor)
                }
            }

            try await readDelimitedOutput(from: stdoutChannel.readDescriptor) { line in
                if let change = RsyncOutputParser.parseChanges(from: [line]).first {
                    await stdoutLines.append(line)
                    if let pending = inFlightTransferChange {
                        if let liveEventHandler {
                            await liveEventHandler(.appliedChange(pending))
                        }
                        inFlightTransferChange = nil
                    }

                    if change.operation == .create || change.operation == .update {
                        inFlightTransferChange = change
                        if let liveEventHandler {
                            await liveEventHandler(.changeDetected(change))
                        }
                    } else {
                        if let liveEventHandler {
                            await liveEventHandler(.appliedChange(change))
                        }
                    }
                } else if let pending = inFlightTransferChange,
                          let progress = RsyncOutputParser.parseTransferProgress(from: line, currentPath: pending.path) {
                    if let liveEventHandler {
                        await liveEventHandler(.transferProgress(progress))
                    }
                    if progress.isCompleted {
                        if let liveEventHandler {
                            await liveEventHandler(.appliedChange(pending))
                        }
                        inFlightTransferChange = nil
                    }
                } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await stdoutLines.append(line)
                    if let liveEventHandler {
                        await liveEventHandler(.info(line))
                    }
                }
            }

            return inFlightTransferChange
        }

        let stderrTask = Task {
            try await readDelimitedOutput(from: stderrPipe.fileHandleForReading.fileDescriptor) { line in
                await stderrLines.append(line)
                guard let liveEventHandler else { return }
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    await liveEventHandler(.warning(line))
                }
            }
        }

        let exitCodeTask = Task<(Int32, CommandTerminationReason), Error> {
            try process.run()
            try? stdoutChannel.parentWriteHandle.close()
            try? stderrPipe.fileHandleForWriting.close()
            if let liveEventHandler {
                await liveEventHandler(.started(Date()))
            }
            return await withCheckedContinuation { continuation in
                process.terminationHandler = { finishedProcess in
                    let reason: CommandTerminationReason = finishedProcess.terminationReason == .uncaughtSignal ? .signal : .exit
                    continuation.resume(returning: (finishedProcess.terminationStatus, reason))
                }
            }
        }

        do {
            let (terminationStatus, terminationReason) = try await exitCodeTask.value
            let pendingTransferChange = try? await stdoutTask.value
            _ = try? await stderrTask.value
            if terminationReason == .exit,
               terminationStatus == 0,
               let pendingTransferChange {
                if let liveEventHandler {
                    await liveEventHandler(.appliedChange(pendingTransferChange))
                }
            }
            stateQueue.sync {
                self.currentProcess = nil
            }
            return ExecutionResult(
                binaryPath: installation.binaryURL.path,
                arguments: arguments,
                startedAt: startedAt,
                finishedAt: Date(),
                terminationStatus: terminationStatus,
                terminationReason: terminationReason,
                stdout: await stdoutLines.snapshot(),
                stderr: await stderrLines.snapshot()
            )
        } catch {
            try? stdoutChannel.parentWriteHandle.close()
            try? stderrPipe.fileHandleForWriting.close()
            stateQueue.sync {
                self.currentProcess = nil
            }
            throw BackupError.rsyncLaunchFailed(error.localizedDescription)
        }
    }

    private func makeStandardOutputChannel(usePseudoTerminal: Bool) throws -> StandardOutputChannel {
        if usePseudoTerminal {
            var masterDescriptor: Int32 = -1
            var slaveDescriptor: Int32 = -1
            guard openpty(&masterDescriptor, &slaveDescriptor, nil, nil, nil) == 0 else {
                throw BackupError.rsyncLaunchFailed("Could not create a pseudo-terminal for rsync progress output.")
            }

            return StandardOutputChannel(
                readDescriptor: masterDescriptor,
                parentWriteHandle: FileHandle(fileDescriptor: slaveDescriptor, closeOnDealloc: true),
                retainedReadHandle: nil,
                shouldCloseReadDescriptor: true
            )
        }

        let pipe = Pipe()
        return StandardOutputChannel(
            readDescriptor: pipe.fileHandleForReading.fileDescriptor,
            parentWriteHandle: pipe.fileHandleForWriting,
            retainedReadHandle: pipe.fileHandleForReading,
            shouldCloseReadDescriptor: false
        )
    }

    private func readDelimitedOutput(
        from descriptor: Int32,
        handler: @escaping (String) async -> Void
    ) async throws {
        var buffer = Data()
        var previousWasCarriageReturn = false

        while true {
            var byte: UInt8 = 0
            let bytesRead = Darwin.read(descriptor, &byte, 1)
            if bytesRead == 0 {
                break
            }
            if bytesRead < 0 {
                if errno == EINTR {
                    continue
                }
                if errno == EIO {
                    break
                }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }

            switch byte {
            case 0x0D, 0x0A:
                if previousWasCarriageReturn && byte == 0x0A {
                    previousWasCarriageReturn = false
                    continue
                }

                if !buffer.isEmpty {
                    let line = String(decoding: buffer, as: UTF8.self)
                    buffer.removeAll(keepingCapacity: true)
                    await handler(line)
                }

                previousWasCarriageReturn = (byte == 0x0D)

            default:
                previousWasCarriageReturn = false
                buffer.append(byte)
            }
        }

        if !buffer.isEmpty {
            await handler(String(decoding: buffer, as: UTF8.self))
        }
    }

    private func preflightFailureMessage(for diagnostics: CommandDiagnostics) -> String {
        if diagnostics.terminationReason == .signal {
            if diagnostics.terminationStatus == 9 {
                return "Dry run was terminated by signal 9."
            }
            return "Dry run was terminated by signal \(diagnostics.terminationStatus)."
        }

        let stderrMessage = diagnostics.stderrLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderrMessage.isEmpty {
            return stderrMessage
        }
        return "Dry run failed with exit code \(diagnostics.terminationStatus)."
    }
}
