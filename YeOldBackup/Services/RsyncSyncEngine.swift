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

final class RsyncSyncEngine: SyncEngine {
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

    private let locator: RsyncBinaryLocator
    private let environment: [String: String]
    private let stateQueue = DispatchQueue(label: "YeOldBackup.RsyncSyncEngine")

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

    func preflight(pair: BackupPair, exclusions: [String]) async throws -> SyncPreflightResult {
        let installation = try validateInstallation()
        let arguments = makeArguments(dryRun: true, pair: pair, exclusions: exclusions)
        let result = try await execute(
            installation: installation,
            arguments: arguments,
            liveEventHandler: nil
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
        eventHandler: @escaping @Sendable (SyncRunEvent) -> Void
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
        liveEventHandler: (@Sendable (SyncRunEvent) -> Void)?
    ) async throws -> ExecutionResult {
        let process = Process()
        process.executableURL = installation.binaryURL
        process.arguments = arguments
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdoutLines = LineAccumulator()
        let stderrLines = LineAccumulator()

        stateQueue.sync {
            self.currentProcess = process
            self.cancellationRequested = false
        }

        let startedAt = Date()

        let stdoutTask = Task {
            for try await line in stdoutPipe.fileHandleForReading.bytes.lines {
                await stdoutLines.append(line)
                guard let liveEventHandler else { continue }
                if let change = RsyncOutputParser.parseChanges(from: [line]).first {
                    liveEventHandler(.appliedChange(change))
                } else if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    liveEventHandler(.info(line))
                }
            }
        }

        let stderrTask = Task {
            for try await line in stderrPipe.fileHandleForReading.bytes.lines {
                await stderrLines.append(line)
                guard let liveEventHandler else { continue }
                if !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    liveEventHandler(.warning(line))
                }
            }
        }

        let exitCodeTask = Task<(Int32, CommandTerminationReason), Error> {
            try process.run()
            liveEventHandler?(.started(Date()))
            return await withCheckedContinuation { continuation in
                process.terminationHandler = { finishedProcess in
                    let reason: CommandTerminationReason = finishedProcess.terminationReason == .uncaughtSignal ? .signal : .exit
                    continuation.resume(returning: (finishedProcess.terminationStatus, reason))
                }
            }
        }

        do {
            let (terminationStatus, terminationReason) = try await exitCodeTask.value
            _ = try? await stdoutTask.value
            _ = try? await stderrTask.value
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
            stateQueue.sync {
                self.currentProcess = nil
            }
            throw BackupError.rsyncLaunchFailed(error.localizedDescription)
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
