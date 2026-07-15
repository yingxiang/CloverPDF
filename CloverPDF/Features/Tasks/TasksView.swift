import SwiftUI

struct TasksView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Tasks").font(.title2).fontWeight(.semibold)
                Spacer()
                Button {
                    model.clearFinishedTasks()
                } label: {
                    Label("Clear Finished", systemImage: "trash")
                }
                .disabled(!model.tasks.contains { $0.state.isFinished })
            }
            .padding(16)
            Divider()
            if model.tasks.isEmpty {
                EmptyPDFState(title: "No tasks", icon: "list.bullet.rectangle")
            } else {
                List(model.tasks) { task in
                    TaskRow(task: task)
                        .environmentObject(model)
                }
                .listStyle(.inset)
            }
        }
    }
}

private struct TaskRow: View {
    @EnvironmentObject private var model: AppModel
    let task: ProcessingTaskRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: task.kind == .merge ? "square.stack.3d.up" : "doc.text")
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title).lineLimit(1)
                HStack(spacing: 8) {
                    Text(task.state.localizedTitle)
                    if task.state == .running {
                        ProgressView(value: task.progress)
                            .frame(maxWidth: 220)
                    }
                }
                .font(.caption)
                .foregroundStyle(task.state == .failed ? .red : .secondary)
                if task.state == .failed, let errorCode = task.errorCode {
                    Text(CloverPDFError.localizedDescription(for: errorCode))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
            if task.state == .pending || task.state == .running {
                Button {
                    model.cancelTask(task.id)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .help("Cancel")
            }
            if task.state == .failed || task.state == .interrupted {
                Button {
                    model.retryTask(task)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Retry")
            }
            if task.outputPath != nil {
                Button {
                    model.reveal(task)
                } label: {
                    Image(systemName: "folder")
                }
                .help("Show in Finder")
            }
        }
        .padding(.vertical, 8)
    }
}

private extension ProcessingTaskState {
    var isFinished: Bool {
        [.succeeded, .failed, .cancelled, .interrupted].contains(self)
    }

    var localizedTitle: String {
        switch self {
        case .pending: String(localized: "Waiting")
        case .validating: String(localized: "Validating")
        case .running: String(localized: "Processing")
        case .succeeded: String(localized: "Completed")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        case .interrupted: String(localized: "Interrupted")
        }
    }
}
