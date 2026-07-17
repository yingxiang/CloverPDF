import Foundation

private enum PendingOperation: Sendable {
    case merge(MergeRequest)
    case batchImage(BatchImageRequest)
    case convert(ConversionRequest, consumesTrial: Bool)
}

actor TaskQueueActor {
    private let merger: PDFMerging
    private let imageExporter: PDFImageExporting
    private let converter: PDFConverting
    private let repository: TaskRepository
    private let trialStore: TrialQuotaStoring
    private var tasks: [ProcessingTaskRecord] = []
    private var operations: [UUID: PendingOperation] = [:]
    private var runner: Task<Void, Never>?
    private var runningTaskID: UUID?
    private var currentOperationTask: Task<[URL], Error>?
    private var persistenceTask: Task<Void, Never>?

    init(
        merger: PDFMerging,
        imageExporter: PDFImageExporting,
        converter: PDFConverting,
        repository: TaskRepository,
        trialStore: TrialQuotaStoring
    ) {
        self.merger = merger
        self.imageExporter = imageExporter
        self.converter = converter
        self.repository = repository
        self.trialStore = trialStore
    }

    func restore() async {
        let restoredTasks = (try? await repository.load()) ?? []
        tasks = restoredTasks.flatMap(Self.expandLegacyBatchTask)
        try? await repository.save(tasks)
    }

    func snapshot() -> [ProcessingTaskRecord] {
        tasks.enumerated()
            .sorted { lhs, rhs in
                lhs.element.createdAt == rhs.element.createdAt
                    ? lhs.offset < rhs.offset
                    : lhs.element.createdAt > rhs.element.createdAt
            }
            .map(\.element)
    }

    @discardableResult
    func enqueueMerge(_ request: MergeRequest) -> UUID {
        let id = UUID()
        tasks.append(ProcessingTaskRecord(
            id: id,
            kind: .merge,
            title: request.outputURL.lastPathComponent,
            inputPaths: request.inputs.map(\.source.path),
            inputPageCount: request.inputs.reduce(0) { $0 + $1.source.pageCount },
            inputFileSize: request.inputs.reduce(0) { $0 + $1.source.fileSize },
            targetDirectoryPath: request.outputURL.deletingLastPathComponent().path,
            state: .pending,
            progress: 0,
            createdAt: Date()
        ))
        operations[id] = .merge(request)
        persistAndRun()
        return id
    }

    @discardableResult
    func enqueueBatchImages(_ request: BatchImageRequest) -> [UUID] {
        let createdAt = Date()
        let taskIDs = request.inputs.map { input -> UUID in
            let id = UUID()
            let itemRequest = BatchImageRequest(
                inputs: [input],
                outputDirectory: request.outputDirectory,
                imageFormat: request.imageFormat
            )
            tasks.append(ProcessingTaskRecord(
                id: id,
                kind: .batchImage,
                title: Self.batchOutputName(input: input, format: request.imageFormat),
                inputPaths: [input.source.path],
                inputPageCount: input.source.pageCount,
                inputFileSize: input.source.fileSize,
                targetDirectoryPath: request.outputDirectory.path,
                state: .pending,
                progress: 0,
                createdAt: createdAt
            ))
            operations[id] = .batchImage(itemRequest)
            return id
        }
        persistAndRun()
        return taskIDs
    }

    func enqueueConversions(_ requests: [ConversionRequest], premiumUnlocked: Bool) throws {
        let eligibleRequests = requests.filter { !$0.pageIndices.isEmpty }
        if eligibleRequests.count > 1 && !premiumUnlocked { throw CloverPDFError.premiumRequired }
        for request in eligibleRequests {
            let consumesTrial = !premiumUnlocked
            let activeIDs = Set(tasks.filter { $0.state == .pending || $0.state == .running }.map(\.id))
            let reservedTrials = operations.filter { id, operation in
                guard activeIDs.contains(id) else { return false }
                if case .convert(_, true) = operation { return true }
                return false
            }.count
            if consumesTrial && trialStore.remainingConversions() - reservedTrials <= 0 {
                throw CloverPDFError.premiumRequired
            }
            let id = UUID()
            tasks.append(ProcessingTaskRecord(
                id: id,
                kind: .convert,
                title: Self.wordOutputName(input: request.input),
                inputPaths: [request.input.source.path],
                inputPageCount: request.pageIndices.count,
                inputFileSize: request.input.source.fileSize,
                targetDirectoryPath: request.outputDirectory.path,
                conversionPageIndices: request.pageIndices,
                state: .pending,
                progress: 0,
                createdAt: Date()
            ))
            operations[id] = .convert(request, consumesTrial: consumesTrial)
        }
        persistAndRun()
    }

    func cancel(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        if runningTaskID == id {
            currentOperationTask?.cancel()
        } else if tasks[index].state == .pending {
            tasks[index].state = .cancelled
            tasks[index].finishedAt = Date()
            operations[id] = nil
        }
        persist()
    }

    func delete(_ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        if let runningTaskID, ids.contains(runningTaskID) {
            let operationTask = currentOperationTask
            operationTask?.cancel()
            _ = await operationTask?.result
        }
        removeTasks(withIDs: ids)
    }

    func clearFinished() {
        let finishedStates: Set<ProcessingTaskState> = [.succeeded, .failed, .cancelled, .interrupted]
        let finishedIDs = Set(tasks.filter { finishedStates.contains($0.state) }.map(\.id))
        removeTasks(withIDs: finishedIDs)
    }

    func retry(_ id: UUID) -> Bool {
        guard operations[id] != nil,
              let index = tasks.firstIndex(where: { $0.id == id }),
              tasks[index].state == .failed else {
            return false
        }
        tasks[index].state = .pending
        tasks[index].progress = 0
        tasks[index].errorCode = nil
        tasks[index].finishedAt = nil
        persistAndRun()
        return true
    }

    private func persistAndRun() {
        persist()
        guard runner == nil else { return }
        runner = Task { await processQueue() }
    }

    private func persist() {
        let snapshot = tasks
        let previousTask = persistenceTask
        persistenceTask = Task {
            _ = await previousTask?.result
            try? await repository.save(snapshot)
        }
    }

    private func removeTasks(withIDs ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        tasks.removeAll { ids.contains($0.id) }
        for id in ids { operations[id] = nil }
        persist()
    }

    private func processQueue() async {
        while let index = tasks.firstIndex(where: { $0.state == .pending }) {
            let id = tasks[index].id
            guard let operation = operations[id] else {
                tasks[index].state = .interrupted
                continue
            }
            runningTaskID = id
            tasks[index].state = .running
            tasks[index].progress = 0.02
            persist()
            do {
                let operationTask = Task { try await execute(operation, id: id) }
                currentOperationTask = operationTask
                let outputURLs = try await operationTask.value
                if case .convert(_, true) = operation { try trialStore.consumeSuccessfulConversion() }
                finish(id: id, state: .succeeded, outputURLs: outputURLs, errorCode: nil)
            } catch is CancellationError {
                finish(id: id, state: .cancelled, outputURLs: [], errorCode: "cancelled")
            } catch {
                let code = (error as? CloverPDFError)?.code ?? "unknown"
                finish(id: id, state: .failed, outputURLs: [], errorCode: code)
            }
            if tasks.first(where: { $0.id == id })?.state != .failed {
                operations[id] = nil
            }
            runningTaskID = nil
            currentOperationTask = nil
        }
        runner = nil
        persist()
    }

    private func execute(_ operation: PendingOperation, id: UUID) async throws -> [URL] {
        switch operation {
        case .merge(let request):
            return [try await merger.merge(request)]
        case .batchImage(let request):
            return try await imageExporter.export(request)
        case .convert(let request, _):
            return [try await converter.convert(request) { [weak self] update in
                Task { await self?.updateProgress(id: id, fraction: update.fraction) }
            }]
        }
    }

    private func updateProgress(id: UUID, fraction: Double) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].progress = min(max(fraction, 0), 1)
    }

    private func finish(id: UUID, state: ProcessingTaskState, outputURLs: [URL], errorCode: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = state
        tasks[index].progress = state == .succeeded ? 1 : tasks[index].progress
        tasks[index].outputPath = outputURLs.first?.path
        tasks[index].outputPaths = outputURLs.isEmpty ? nil : outputURLs.map(\.path)
        tasks[index].errorCode = errorCode
        tasks[index].finishedAt = Date()
        persist()
    }

    private static func batchOutputName(input: PDFInput, format: RasterImageFormat) -> String {
        URL(fileURLWithPath: input.source.displayName)
            .deletingPathExtension()
            .appendingPathExtension(format.fileExtension)
            .lastPathComponent
    }

    private static func wordOutputName(input: PDFInput) -> String {
        URL(fileURLWithPath: input.source.displayName)
            .deletingPathExtension()
            .appendingPathExtension("docx")
            .lastPathComponent
    }

    private static func expandLegacyBatchTask(_ task: ProcessingTaskRecord) -> [ProcessingTaskRecord] {
        guard task.kind == .batchImage else { return [task] }
        let outputPaths = task.outputPaths ?? task.outputPath.map { [$0] } ?? []
        let itemCount = max(task.inputPaths.count, outputPaths.count)
        guard itemCount > 1 else { return [task] }
        return (0..<itemCount).map { index in
            let outputPath = outputPaths[safe: index]
            let inputPath = task.inputPaths[safe: index]
            return ProcessingTaskRecord(
                id: index == 0 ? task.id : UUID(),
                kind: .batchImage,
                title: outputPath.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? inputPath.map { URL(fileURLWithPath: $0).lastPathComponent }
                    ?? task.title,
                inputPaths: inputPath.map { [$0] } ?? [],
                inputPageCount: task.inputPageCount,
                inputFileSize: task.inputFileSize,
                targetDirectoryPath: task.targetDirectoryPath,
                conversionPageIndices: task.conversionPageIndices,
                outputPath: outputPath,
                outputPaths: outputPath.map { [$0] },
                state: task.state,
                progress: task.progress,
                errorCode: task.errorCode,
                createdAt: task.createdAt,
                finishedAt: task.finishedAt
            )
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
