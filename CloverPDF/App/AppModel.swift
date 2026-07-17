import AppKit
import Foundation

enum AppSection: String, CaseIterable, Identifiable {
    case merge
    case convert
    case tasks
    case settings

    var id: String { rawValue }
}

struct WorkspacePDF: Identifiable, Sendable {
    let source: PDFSource
    var password = ""
    var selectedPageIndices: Set<Int>
    var id: UUID { source.id }

    init(source: PDFSource, password: String = "", selectedPageIndices: Set<Int>? = nil) {
        self.source = source
        self.password = password
        self.selectedPageIndices = selectedPageIndices ?? Set(0..<source.pageCount)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: AppSection = .merge
    @Published var mergeItems: [WorkspacePDF] = []
    @Published var conversionItems: [WorkspacePDF] = []
    @Published var selectedMergeItemIDs: Set<UUID> = []
    @Published var selectedConversionItemIDs: Set<UUID> = []
    @Published var selectedTaskIDs: Set<UUID> = []
    @Published var previewItem: WorkspacePDF?
    @Published var taskPreviewItem: WorkspacePDF?
    @Published var tasks: [ProcessingTaskRecord] = []
    @Published var outputDirectory: URL
    @Published var alertMessage: String?
    @Published private(set) var remainingTrialConversions = 3

    let purchaseService: PurchaseService
    let paywallCoordinator: CloverPaywallCoordinator
    private let inspector = PDFInspector()
    private let trialStore: TrialQuotaStoring
    private let queue: TaskQueueActor
    private var refreshTask: Task<Void, Never>?
    private var taskPreviewLoadTask: Task<Void, Never>?
    private var taskPreviewTaskID: UUID?
    private var taskPreviewPath: String?
    private var mergeInputsByTask: [UUID: Set<UUID>] = [:]

    init() {
        let repository = JSONTaskRepository()
        let trialStore = KeychainTrialQuotaStore()
        let purchaseService = PurchaseService()
        self.trialStore = trialStore
        self.purchaseService = purchaseService
        paywallCoordinator = CloverPaywallCoordinator(purchaseService: purchaseService)
        queue = TaskQueueActor(
            merger: PDFKitMerger(),
            imageExporter: PDFImageExporter(),
            converter: PythonConverterService(),
            repository: repository,
            trialStore: trialStore
        )
        outputDirectory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        remainingTrialConversions = trialStore.remainingConversions()
        ExternalOpenCenter.shared.handler = { [weak self] urls in self?.openExternalPDFs(urls) }
        purchaseService.start()
        refreshTask = Task { [weak self] in
            await self?.queue.restore()
            while !Task.isCancelled {
                await self?.refreshTasks()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
    }

    deinit {
        refreshTask?.cancel()
        taskPreviewLoadTask?.cancel()
    }

    func importPDFs(_ urls: [URL], destination: AppSection) {
        Task {
            let inspected = await inspect(urls)
            guard !inspected.isEmpty else { return }
            switch destination {
            case .merge:
                appendUnique(inspected, to: &mergeItems)
                selectFirstImportedItemIfNeeded(inspected, selection: &selectedMergeItemIDs)
                selection = .merge
            case .convert:
                appendUnique(inspected, to: &conversionItems)
                selectFirstImportedItemIfNeeded(inspected, selection: &selectedConversionItemIDs)
                selection = .convert
            default:
                break
            }
        }
    }

    func openExternalPDFs(_ urls: [URL]) {
        Task {
            let inspected = await inspect(urls)
            if inspected.count == 1 {
                previewItem = inspected[0]
            } else if inspected.count > 1 {
                appendUnique(inspected, to: &mergeItems)
                selectFirstImportedItemIfNeeded(inspected, selection: &selectedMergeItemIDs)
                selection = .merge
            }
        }
    }

    func enqueueMerge() {
        guard mergeItems.count >= 2 else { return }
        guard let destination = FilePanel.saveMergedOutput() else { return }
        let submittedItems = mergeItems
        let inputs = submittedItems.map { PDFInput(source: $0.source, password: $0.password.nilIfEmpty) }
        let request = MergeRequest(
            inputs: inputs,
            outputURL: destination.url,
            outputFormat: destination.format
        )
        Task {
            let taskID = await queue.enqueueMerge(request)
            mergeInputsByTask[taskID] = Set(submittedItems.map(\.id))
            selection = .tasks
        }
    }

    func enqueueBatchImages() {
        guard !mergeItems.isEmpty else { return }
        guard let destination = FilePanel.chooseBatchImageDestination() else { return }
        let request = BatchImageRequest(
            inputs: mergeItems.map { PDFInput(source: $0.source, password: $0.password.nilIfEmpty) },
            outputDirectory: destination.directoryURL,
            imageFormat: destination.format
        )
        Task {
            await queue.enqueueBatchImages(request)
            selection = .tasks
        }
    }

    func enqueueConversions() {
        let requests = conversionItems.compactMap { item -> ConversionRequest? in
            let selectedPages = item.selectedPageIndices.sorted()
            guard !selectedPages.isEmpty else { return nil }
            return ConversionRequest(
                input: PDFInput(source: item.source, password: item.password.nilIfEmpty),
                outputDirectory: outputDirectory,
                pageIndices: selectedPages
            )
        }
        guard !requests.isEmpty else { return }
        Task {
            do {
                try await queue.enqueueConversions(requests, premiumUnlocked: purchaseService.isPremiumUnlocked)
                selection = .tasks
            } catch CloverPDFError.premiumRequired {
                paywallCoordinator.show(sourceView: NSApp.keyWindow?.contentView)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    func cancelTask(_ id: UUID) {
        Task { await queue.cancel(id) }
    }

    func clearFinishedTasks() {
        Task { await queue.clearFinished() }
    }

    func deleteTasks(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        for id in ids { mergeInputsByTask[id] = nil }
        selectedTaskIDs.subtract(ids)
        updateTaskPreview()
        Task { await queue.delete(ids) }
    }

    func updateTaskPreview() {
        guard let task = tasks.first(where: { selectedTaskIDs.contains($0.id) }),
              let path = task.previewPDFPath else {
            clearTaskPreview()
            return
        }
        guard taskPreviewTaskID != task.id || taskPreviewPath != path else { return }
        taskPreviewLoadTask?.cancel()
        taskPreviewTaskID = task.id
        taskPreviewPath = path
        taskPreviewItem = nil
        taskPreviewLoadTask = Task { [weak self] in
            guard let self else { return }
            let item = await self.inspect([URL(fileURLWithPath: path)]).first
            guard !Task.isCancelled,
                  self.selectedTaskIDs.contains(task.id),
                  self.taskPreviewPath == path else { return }
            self.taskPreviewItem = item
        }
    }

    func clearMergeItems() {
        mergeItems.removeAll()
        selectedMergeItemIDs.removeAll()
    }

    func clearConversionItems() {
        conversionItems.removeAll()
        selectedConversionItemIDs.removeAll()
    }

    func removeMergeItems(_ ids: Set<UUID>) {
        mergeItems.removeAll { ids.contains($0.id) }
        selectedMergeItemIDs.subtract(ids)
    }

    func removeConversionItems(_ ids: Set<UUID>) {
        conversionItems.removeAll { ids.contains($0.id) }
        selectedConversionItemIDs.subtract(ids)
    }

    func moveMergeItem(_ id: UUID, offset: Int) {
        Self.moveWorkspaceItem(id, offset: offset, in: &mergeItems)
    }

    func moveConversionItem(_ id: UUID, offset: Int) {
        Self.moveWorkspaceItem(id, offset: offset, in: &conversionItems)
    }

    func retryTask(_ task: ProcessingTaskRecord) {
        Task {
            if await queue.retry(task.id) { return }
            let urls = task.inputPaths.map(URL.init(fileURLWithPath:))
            let inspected = await inspect(urls)
            guard inspected.count == urls.count else {
                alertMessage = String(localized: "The source files must be added again.")
                return
            }
            if inspected.contains(where: \.source.isLocked) {
                if task.kind == .merge || task.kind == .batchImage {
                    appendUnique(inspected, to: &mergeItems)
                    selection = .merge
                } else {
                    appendUnique(inspected, to: &conversionItems)
                    selection = .convert
                }
                alertMessage = String(localized: "Enter the PDF password before retrying.")
                return
            }
            if task.kind == .merge {
                guard let destination = FilePanel.saveMergedOutput(suggestedName: task.title) else { return }
                let request = MergeRequest(
                    inputs: inspected.map { PDFInput(source: $0.source, password: nil) },
                    outputURL: destination.url,
                    outputFormat: destination.format
                )
                let taskID = await queue.enqueueMerge(request)
                mergeInputsByTask[taskID] = Set(inspected.map(\.id))
            } else if task.kind == .batchImage {
                guard let destination = FilePanel.chooseBatchImageDestination() else { return }
                let request = BatchImageRequest(
                    inputs: inspected.map { PDFInput(source: $0.source, password: nil) },
                    outputDirectory: destination.directoryURL,
                    imageFormat: destination.format
                )
                await queue.enqueueBatchImages(request)
            } else {
                let requests = inspected.map { item in
                    let savedPages = task.conversionPageIndices ?? Array(0..<item.source.pageCount)
                    let validPages = savedPages.filter { page in
                        page >= 0 && page < item.source.pageCount
                    }
                    return ConversionRequest(
                        input: PDFInput(source: item.source, password: nil),
                        outputDirectory: outputDirectory,
                        pageIndices: validPages
                    )
                }
                do {
                    try await queue.enqueueConversions(requests, premiumUnlocked: purchaseService.isPremiumUnlocked)
                } catch {
                    paywallCoordinator.show(sourceView: NSApp.keyWindow?.contentView)
                }
            }
        }
    }

    func revealTasks(_ ids: Set<UUID>) {
        let paths = tasks
            .filter { ids.contains($0.id) }
            .compactMap(\.representativePath)
        revealPaths(paths)
    }

    func revealWorkspaceItems(_ ids: Set<UUID>, in items: [WorkspacePDF]) {
        revealPaths(items.filter { ids.contains($0.id) }.map(\.source.path))
    }

    func revealSource(_ source: PDFSource) {
        revealPaths([source.path])
    }

    func revealSourceFile(atPath path: String) {
        revealPaths([path])
    }

    func usePreviewForConversion() {
        guard let previewItem else { return }
        appendUnique([previewItem], to: &conversionItems)
        self.previewItem = nil
        selection = .convert
    }

    func usePreviewForMerge() {
        guard let previewItem else { return }
        appendUnique([previewItem], to: &mergeItems)
        self.previewItem = nil
        selection = .merge
    }

    private func inspect(_ urls: [URL]) async -> [WorkspacePDF] {
        var results: [WorkspacePDF] = []
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            do {
                let source = try await Task.detached { try self.inspector.inspect(url: url) }.value
                results.append(WorkspacePDF(source: source))
            } catch {
                alertMessage = error.localizedDescription
            }
        }
        return results
    }

    private func appendUnique(_ items: [WorkspacePDF], to collection: inout [WorkspacePDF]) {
        let existing = Set(collection.map(\.source.path))
        collection.append(contentsOf: items.filter { !existing.contains($0.source.path) })
    }

    private func revealPaths(_ paths: [String]) {
        var seen: Set<String> = []
        let urls = paths.compactMap { path -> URL? in
            guard seen.insert(path).inserted else { return nil }
            return URL(fileURLWithPath: path)
        }
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    private func selectFirstImportedItemIfNeeded(
        _ items: [WorkspacePDF],
        selection: inout Set<UUID>
    ) {
        if selection.isEmpty, let firstID = items.first?.id {
            selection.insert(firstID)
        }
    }

    private static func moveWorkspaceItem(_ id: UUID, offset: Int, in items: inout [WorkspacePDF]) {
        guard let sourceIndex = items.firstIndex(where: { $0.id == id }) else { return }
        let destinationIndex = sourceIndex + offset
        guard items.indices.contains(destinationIndex) else { return }
        items.swapAt(sourceIndex, destinationIndex)
    }

    private func refreshTasks() async {
        tasks = await queue.snapshot()
        selectedTaskIDs.formIntersection(tasks.map(\.id))
        updateTaskPreview()
        remainingTrialConversions = trialStore.remainingConversions()
        let terminalStates: Set<ProcessingTaskState> = [.succeeded, .failed, .cancelled, .interrupted]
        let completedMerges = mergeInputsByTask.compactMap { taskID, inputIDs -> (UUID, Set<UUID>, ProcessingTaskState)? in
            guard let task = tasks.first(where: { $0.id == taskID }), terminalStates.contains(task.state) else { return nil }
            return (taskID, inputIDs, task.state)
        }
        for (taskID, inputIDs, state) in completedMerges {
            if state == .succeeded {
                mergeItems.removeAll { inputIDs.contains($0.id) }
                selectedMergeItemIDs.subtract(inputIDs)
            }
            mergeInputsByTask[taskID] = nil
        }
    }

    private func clearTaskPreview() {
        taskPreviewLoadTask?.cancel()
        taskPreviewLoadTask = nil
        taskPreviewTaskID = nil
        taskPreviewPath = nil
        taskPreviewItem = nil
    }

}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

private extension ProcessingTaskRecord {
    var representativePath: String? {
        outputPaths?.first ?? outputPath ?? inputPaths.first
    }

    var previewPDFPath: String? {
        let output = outputPaths?.first ?? outputPath
        if let output, URL(fileURLWithPath: output).pathExtension.lowercased() == "pdf" {
            return output
        }
        return inputPaths.first { URL(fileURLWithPath: $0).pathExtension.lowercased() == "pdf" }
    }
}
