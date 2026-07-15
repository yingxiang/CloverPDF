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
    var id: UUID { source.id }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var selection: AppSection = .merge
    @Published var mergeItems: [WorkspacePDF] = []
    @Published var conversionItems: [WorkspacePDF] = []
    @Published var previewItem: WorkspacePDF?
    @Published var tasks: [ProcessingTaskRecord] = []
    @Published var outputDirectory: URL
    @Published var mergeOutputName = String(localized: "Merged PDF")
    @Published var pageRangeEnabled = false
    @Published var startPage = 1
    @Published var endPage = 1
    @Published var alertMessage: String?
    @Published private(set) var remainingTrialConversions = 3

    let purchaseService: PurchaseService
    let paywallCoordinator: CloverPaywallCoordinator
    private let inspector = PDFInspector()
    private let trialStore: TrialQuotaStoring
    private let queue: TaskQueueActor
    private var refreshTask: Task<Void, Never>?

    init() {
        let repository = JSONTaskRepository()
        let trialStore = KeychainTrialQuotaStore()
        let purchaseService = PurchaseService()
        self.trialStore = trialStore
        self.purchaseService = purchaseService
        paywallCoordinator = CloverPaywallCoordinator(purchaseService: purchaseService)
        queue = TaskQueueActor(
            merger: PDFKitMerger(),
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
    }

    func importPDFs(_ urls: [URL], destination: AppSection) {
        Task {
            let inspected = await inspect(urls)
            guard !inspected.isEmpty else { return }
            switch destination {
            case .merge:
                appendUnique(inspected, to: &mergeItems)
                selection = .merge
            case .convert:
                appendUnique(inspected, to: &conversionItems)
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
                selection = .merge
            }
        }
    }

    func enqueueMerge() {
        guard !mergeItems.isEmpty else { return }
        let inputs = mergeItems.map { PDFInput(source: $0.source, password: $0.password.nilIfEmpty) }
        let request = MergeRequest(
            inputs: inputs,
            outputDirectory: outputDirectory,
            outputName: mergeOutputName
        )
        Task {
            await queue.enqueueMerge(request)
            selection = .tasks
        }
    }

    func enqueueConversions() {
        guard !conversionItems.isEmpty else { return }
        let range: ClosedRange<Int>? = pageRangeEnabled ? startPage...endPage : nil
        let requests = conversionItems.map { item in
            ConversionRequest(
                input: PDFInput(source: item.source, password: item.password.nilIfEmpty),
                outputDirectory: outputDirectory,
                pageRange: range
            )
        }
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
                if task.kind == .merge {
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
                let request = MergeRequest(
                    inputs: inspected.map { PDFInput(source: $0.source, password: nil) },
                    outputDirectory: outputDirectory,
                    outputName: task.title
                )
                await queue.enqueueMerge(request)
            } else {
                let requests = inspected.map {
                    ConversionRequest(
                        input: PDFInput(source: $0.source, password: nil),
                        outputDirectory: outputDirectory,
                        pageRange: nil
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

    func reveal(_ task: ProcessingTaskRecord) {
        guard let outputPath = task.outputPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
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

    private func refreshTasks() async {
        tasks = await queue.snapshot()
        remainingTrialConversions = trialStore.remainingConversions()
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
