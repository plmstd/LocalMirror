import SwiftUI

struct ContentView: View {
    @StateObject private var appModel = AppModel()
    @State private var progressClock = Date()

    private let freshCurrentPathInterval: TimeInterval = 20
    private let recentTransferInterval: TimeInterval = 20
    private let staleOutputInterval: TimeInterval = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            selectionSection
            savedPairsSection
            runStateSection
            footerControls
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 680)
        .onAppear { appModel.load() }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { timestamp in
            if case .running = appModel.runState {
                progressClock = timestamp
            }
        }
        .sheet(
            isPresented: Binding(
                get: { appModel.reviewReport != nil },
                set: { isPresented in
                    if !isPresented {
                        appModel.cancelReview()
                    }
                }
            )
        ) {
            if let report = appModel.reviewReport {
                PreflightReviewSheet(
                    report: report,
                    onCancel: { appModel.cancelReview() },
                    onApprove: { confirmation in
                        appModel.approvePreflight(typedConfirmation: confirmation)
                    }
                )
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("YeOldBackup")
                        .font(.system(size: 28, weight: .bold))
                    Text("Clone backup for local folders and external drives.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let installation = appModel.installation {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(installation.displayTitle)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(installation.kind == .systemProvided ? .green : .orange)
                        Text(installation.versionDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }

            Text("Target will be made to match source. Files missing from source will be removed from target.")
                .font(.subheadline)
                .foregroundStyle(.orange)

            if let note = appModel.statusNote {
                Text(note)
                    .font(.caption)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }

            HStack(spacing: 12) {
                Button("Reveal Logs in Finder") {
                    appModel.revealLogsInFinder()
                }
                .buttonStyle(.bordered)

                Button("Copy Diagnostics") {
                    appModel.copySupportDiagnostics()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
    }

    private var selectionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            selectionRow(title: "Source", path: appModel.sourcePath) {
                appModel.selectDirectory(.source)
            }

            selectionRow(title: "Target", path: appModel.targetPath) {
                appModel.selectDirectory(.target)
            }

            if let capabilities = appModel.selectedTargetCapabilities {
                HStack(spacing: 18) {
                    capabilityPill(title: "Target FS", value: capabilities.fileSystemType)
                    capabilityPill(title: "History", value: capabilities.historyModeLabel)
                    if capabilities.isReadOnly {
                        capabilityPill(title: "Access", value: "Read-only")
                    }
                    Spacer()
                }
            }

            HStack(spacing: 12) {
                Button("Open Full Disk Access Settings") {
                    appModel.openSystemSettings()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func selectionRow(title: String, path: String, action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.headline)
                .frame(width: 60, alignment: .leading)
            Text(path.isEmpty ? "No folder selected" : path)
                .font(.body.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Button("Select…", action: action)
                .buttonStyle(.borderedProminent)
                .disabled(appModel.isBusy)
        }
    }

    private func capabilityPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var savedPairsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved Backup Pairs")
                .font(.headline)

            Table(appModel.pairs, selection: $appModel.selectedPairID) {
                TableColumn("Source") { pair in
                    Text(pair.sourceName).help(pair.sourceCanonicalPath)
                }
                TableColumn("Target") { pair in
                    Text(pair.targetName).help(pair.targetCanonicalPath)
                }
                TableColumn("Target FS") { pair in
                    Text(pair.targetCapabilities.fileSystemType)
                        .foregroundStyle(.secondary)
                }
                TableColumn("History") { pair in
                    Text(pair.targetCapabilities.historyModeLabel)
                        .foregroundStyle(pair.targetCapabilities.supportsSnapshots ? .green : .secondary)
                }
                TableColumn("Last Run") { pair in
                    if let lastRun = pair.lastRun {
                        Text(lastRun.date, style: .relative)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Never")
                            .foregroundStyle(.secondary)
                    }
                }
                TableColumn("Status") { pair in
                    statusPill(for: pair.lastRun?.status)
                }
            }
            .frame(minHeight: 180, maxHeight: 240)
            .onChange(of: appModel.selectedPairID) { _, newValue in
                appModel.loadSelectedPair(id: newValue)
            }
            .contextMenu(forSelectionType: UUID.self) { selectedIDs in
                if !selectedIDs.isEmpty {
                    Button("Remove from list", role: .destructive) {
                        appModel.deleteSelectedPairs(selectedIDs)
                    }
                }
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statusPill(for status: BackupOutcomeStatus?) -> some View {
        Group {
            switch status {
            case .success:
                Label("Success", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .partial:
                Label("Partial", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .failure:
                Label("Failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
            case .cancelled:
                Label("Cancelled", systemImage: "stop.circle.fill")
                    .foregroundStyle(.orange)
            case .none:
                Text("New")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption.weight(.medium))
    }

    @ViewBuilder
    private var runStateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Run Status")
                .font(.headline)

            switch appModel.runState {
            case .idle:
                Text("Select a source and target folder, then start a clone backup. Every run now starts with a preflight review.")
                    .foregroundStyle(.secondary)

            case .preflighting:
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text(appModel.preflightProgress?.phase ?? "Preparing preflight review…")
                    }
                    .foregroundStyle(.secondary)

                    if let progress = appModel.preflightProgress {
                        Text("\(progress.plannedChangeCount) planned change(s) found so far.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let currentPath = progress.currentPath, !currentPath.isEmpty {
                            Text(currentPath)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        if progress.warningCount > 0 {
                            Text("\(progress.warningCount) warning(s) seen during preflight.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

            case .review(let report):
                VStack(alignment: .leading, spacing: 8) {
                    Text(report.summaryLine)
                    Text("Review is open. Confirm the planned changes before the clone run starts.")
                        .foregroundStyle(.secondary)
                }

            case .running(let progress):
                runningStateView(progress)

            case .cancelling(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label("Cancel pending", systemImage: "stop.circle")
                        .foregroundStyle(.orange)
                    Text(message)
                        .foregroundStyle(.secondary)
                }

            case .completed(let result):
                terminalStateCard(
                    title: result.summary,
                    tone: result.outcome == .partial ? .orange : .green,
                    subtitle: "\(result.appliedChangeCount) change(s) applied, \(result.deletionCount) deletion(s), \(result.warnings.count) warning(s)."
                )

            case .failed(let failure):
                terminalStateCard(
                    title: failure.reason,
                    tone: .red,
                    subtitle: failure.warnings.isEmpty ? "Clone backup failed." : "\(failure.warnings.count) warning(s) were captured before the failure."
                )

            case .cancelled(let failure):
                terminalStateCard(
                    title: failure.reason,
                    tone: .orange,
                    subtitle: "Review the full log before running another clone backup."
                )
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func runningStateView(_ progress: RunProgress) -> some View {
        let presentation = runningStatusPresentation(for: progress, now: progressClock)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if presentation.showsSpinner {
                    ProgressView()
                        .controlSize(.small)
                }
                Text(presentation.title)
            }

            if let detail = presentation.detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: progress.fractionCompleted)

            Text("\(progress.appliedChangeCount) of \(max(progress.totalPlannedChanges, 1)) planned change(s) applied.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if progress.estimatedTransferBytes > 0, progress.totalTransferredBytes > 0 {
                Text(overallTransferProgressText(progress))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let currentPath = presentation.currentPath {
                Text(currentPath)
                    .font(.caption.monospaced())
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if progress.warningCount > 0 {
                Text("\(progress.warningCount) warning(s) seen so far.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func runningStatusPresentation(for progress: RunProgress, now: Date) -> RunningStatusPresentation {
        let currentPath = progress.currentPath?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCurrentPath = currentPath?.isEmpty == false
        let pathIsFresh = progress.currentPathUpdatedAt
            .map { now.timeIntervalSince($0) <= freshCurrentPathInterval } ?? false
        let transferIsRecent = progress.lastTransferProgressAt
            .map { now.timeIntervalSince($0) <= recentTransferInterval } ?? false
        let outputIsStale = progress.lastOutputAt
            .map { now.timeIntervalSince($0) >= staleOutputInterval } ?? false

        if hasCurrentPath, pathIsFresh {
            return RunningStatusPresentation(
                title: "Cloning files…",
                detail: nil,
                currentPath: currentPath,
                showsSpinner: false
            )
        }

        if transferIsRecent {
            return RunningStatusPresentation(
                title: "Copying data…",
                detail: "Overall progress is still updating.",
                currentPath: nil,
                showsSpinner: true
            )
        }

        if outputIsStale {
            return RunningStatusPresentation(
                title: "Waiting for rsync update…",
                detail: "The clone process is still running.",
                currentPath: nil,
                showsSpinner: true
            )
        }

        return RunningStatusPresentation(
            title: "Cloning files…",
            detail: nil,
            currentPath: nil,
            showsSpinner: true
        )
    }

    private func overallTransferProgressText(_ progress: RunProgress) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: progress.totalTransferredBytes)) of \(formatter.string(fromByteCount: progress.estimatedTransferBytes)) transferred."
    }

    private func terminalStateCard(title: String, tone: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .foregroundStyle(tone)
            Text(subtitle)
                .foregroundStyle(.secondary)
            HStack {
                Button("Open Full Log") {
                    appModel.openLatestLog()
                }
                .buttonStyle(.bordered)
                .disabled(!appModel.canOpenLatestLog)

                Button("Reveal Logs in Finder") {
                    appModel.revealLogsInFinder()
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
    }

    private var footerControls: some View {
        HStack {
            if appModel.canStopBackup {
                Button("Stop Clone Backup") {
                    appModel.stopCloneBackup()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            } else {
                Button("Start Clone Backup") {
                    appModel.beginCloneBackup()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!appModel.canStartBackup)
            }

            Spacer()

            if case .completed = appModel.runState {
                Button("Open Full Log") {
                    appModel.openLatestLog()
                }
                .buttonStyle(.bordered)
                .disabled(!appModel.canOpenLatestLog)
            }
        }
    }
}

private struct RunningStatusPresentation {
    var title: String
    var detail: String?
    var currentPath: String?
    var showsSpinner: Bool
}

private struct PreflightReviewSheet: View {
    let report: PreflightReport
    let onCancel: () -> Void
    let onApprove: (String) -> Void

    @State private var confirmationInput: String = ""
    private let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB, .useTB]
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Preflight Review")
                        .font(.title2.bold())
                    Text("Every clone run must be reviewed before it starts.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(report.riskLevel.rawValue.capitalized)
                    .font(.caption.weight(.bold))
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(riskColor.opacity(0.16))
                    .foregroundStyle(riskColor)
                    .clipShape(Capsule())
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    keyValue("Source", value: report.pair.sourceCanonicalPath)
                    keyValue("Target", value: report.pair.targetCanonicalPath)
                    keyValue("Source Volume", value: report.currentSourceVolume.displayName)
                    keyValue("Target Volume", value: report.currentTargetVolume.displayName)
                    keyValue("Target File System", value: report.currentTargetCapabilities.fileSystemType)
                    keyValue("Planned Changes", value: "\(report.statistics.totalChangeCount)")
                    keyValue("Planned Deletions", value: "\(report.statistics.deletionCount)")
                    keyValue("Estimated Transfer", value: byteCount(report.statistics.estimatedTransferBytes))
                    keyValue("Free Space", value: report.availableFreeBytes.map(byteCount) ?? "Unavailable")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Target Mode") {
                VStack(alignment: .leading, spacing: 8) {
                    keyValue("Current Mode", value: report.currentTargetCapabilities.historyModeLabel)
                    Text(report.snapshotReadinessSummary)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !report.validationMessages.isEmpty {
                GroupBox("Checks") {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(report.validationMessages) { message in
                            Label(message.message, systemImage: icon(for: message.severity))
                                .foregroundStyle(color(for: message.severity))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !report.warnings.isEmpty {
                GroupBox("Warnings from rsync") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(report.warnings, id: \.self) { warning in
                            Text(warning)
                                .foregroundStyle(.orange)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            GroupBox("Planned Changes Preview") {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(report.plannedChanges.prefix(25))) { change in
                            HStack(alignment: .top) {
                                Text(change.operation.rawValue.capitalized)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(changeColor(for: change.operation))
                                    .frame(width: 70, alignment: .leading)
                                Text(change.path)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                        if report.plannedChanges.count > 25 {
                            Text("…and \(report.plannedChanges.count - 25) more change(s).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 140, maxHeight: 220)
            }

            GroupBox("Fixed Exclusions") {
                Text(report.exclusions.joined(separator: ", "))
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if report.requiresTypedConfirmation {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Type `\(report.confirmationToken ?? "")` to confirm this destructive clone operation.")
                        .font(.headline)
                    TextField("Confirmation token", text: $confirmationInput)
                        .textFieldStyle(.roundedBorder)
                }
            }

            HStack {
                Button("Cancel", action: onCancel)
                Spacer()
                Button("Start Clone Now") {
                    onApprove(confirmationInput)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!report.canProceed || (report.requiresTypedConfirmation && confirmationInput != report.confirmationToken))
            }
        }
        .padding(24)
        .frame(minWidth: 720, minHeight: 720)
    }

    private var riskColor: Color {
        switch report.riskLevel {
        case .low:
            return .green
        case .medium:
            return .orange
        case .high:
            return .red
        case .critical:
            return .pink
        }
    }

    private func keyValue(_ key: String, value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .foregroundStyle(.secondary)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func byteCount(_ value: Int64) -> String {
        byteFormatter.string(fromByteCount: value)
    }

    private func icon(for severity: ValidationSeverity) -> String {
        switch severity {
        case .info:
            return "info.circle"
        case .warning:
            return "exclamationmark.triangle"
        case .blocking:
            return "xmark.octagon"
        }
    }

    private func color(for severity: ValidationSeverity) -> Color {
        switch severity {
        case .info:
            return .secondary
        case .warning:
            return .orange
        case .blocking:
            return .red
        }
    }

    private func changeColor(for operation: ChangeOperation) -> Color {
        switch operation {
        case .create:
            return .green
        case .update, .metadata, .directory:
            return .blue
        case .delete:
            return .red
        case .unknown:
            return .secondary
        }
    }
}

#Preview {
    ContentView()
}
