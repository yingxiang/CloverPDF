import Foundation

private enum PendingOperation: Sendable {
    case merge(MergeRequest)
    case convert(ConversionRequest, consumesTrial: Bool)
}

actor TaskQueueActor {
    private let merger: PDFMerging
    private let converter: PDFConverting
    private let repository: TaskRepository
    private let trialStore: TrialQuotaStoring
    private var tasks: [ProcessingTaskRecord] = []
    private var operations: [UUID: PendingOperation] = [:]
    private var runner: Task<Void, Never>?
    private var runningTaskID: UUID?
    private var currentOperationTask: Task<URL, Error>?

    init(
        merger: PDFMerging,
        converter: PDFConverting,
        repository: TaskRepository,
        trialStore: TrialQuotaStoring
    ) {
        self.merger = merger
        self.converter = converter
        self.repository = repository
        self.trialStore = trialStore
    }

    func restore() async {
        tasks = (try? await repository.load()) ?? []
        try? await repository.save(tasks)
    }

    func snapshot() -> [ProcessingTaskRecord] {
        tasks.sorted { $0.createdAt > $1.createdAt }
    }

    @discardableResult
    func enqueueMerge(_ request: MergeRequest) -> UUID {
        let id = UUID()
        tasks.append(ProcessingTaskRecord(
            id: id,
            kind: .merge,
            title: request.outputURL.lastPathComponent,
            inputPaths: request.inputs.map(\.source.path),
            state: .pending,
            progress: 0,
            createdAt: Date()
        ))
        operations[id] = .merge(request)
        persistAndRun()
        return id
    }

    func enqueueConversions(_ requests: [ConversionRequest], premiumUnlocked: Bool) throws {
        if requests.count > 1 && !premiumUnlocked { throw CloverPDFError.premiumRequired }
        for request in requests {
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
                title: request.input.source.displayName,
                inputPaths: [request.input.source.path],
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

    func clearFinished() {
        tasks.removeAll { [.succeeded, .failed, .cancelled, .interrupted].contains($0.state) }
        persist()
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
        Task { try? await repository.save(snapshot) }
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
                let outputURL = try await operationTask.value
                if case .convert(_, true) = operation { try trialStore.consumeSuccessfulConversion() }
                finish(id: id, state: .succeeded, outputPath: outputURL.path, errorCode: nil)
            } catch is CancellationError {
                finish(id: id, state: .cancelled, outputPath: nil, errorCode: "cancelled")
            } catch {
                let code = (error as? CloverPDFError)?.code ?? "unknown"
                finish(id: id, state: .failed, outputPath: nil, errorCode: code)
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

    private func execute(_ operation: PendingOperation, id: UUID) async throws -> URL {
        switch operation {
        case .merge(let request):
            return try await merger.merge(request)
        case .convert(let request, _):
            return try await converter.convert(request) { [weak self] update in
                Task { await self?.updateProgress(id: id, fraction: update.fraction) }
            }
        }
    }

    private func updateProgress(id: UUID, fraction: Double) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].progress = min(max(fraction, 0), 1)
    }

    private func finish(id: UUID, state: ProcessingTaskState, outputPath: String?, errorCode: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].state = state
        tasks[index].progress = state == .succeeded ? 1 : tasks[index].progress
        tasks[index].outputPath = outputPath
        tasks[index].errorCode = errorCode
        tasks[index].finishedAt = Date()
        persist()
    }
}
