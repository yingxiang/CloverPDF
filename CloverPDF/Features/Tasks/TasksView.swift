import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TasksView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
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
            taskIcon
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
                if task.kind == .merge, task.state == .succeeded {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(task.inputPaths.enumerated()), id: \.offset) { _, path in
                                TaskSourceFileButton(path: path) {
                                    model.revealSourceFile(atPath: path)
                                }
                            }
                        }
                    }
                    .frame(height: 22)
                }
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

    @ViewBuilder
    private var taskIcon: some View {
        if task.kind == .merge, task.state == .succeeded, let outputPath = task.outputPath {
            PDFThumbnail(fileURL: URL(fileURLWithPath: outputPath))
                .frame(width: 48, height: 60)
                .clipped()
        } else if task.kind == .merge, task.state.isActive {
            Image(nsImage: NSWorkspace.shared.icon(for: .pdf))
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 48, height: 60)
        } else {
            Image(systemName: task.kind == .merge ? "square.stack.3d.up" : "doc.text")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 60)
        }
    }
}

private struct TaskSourceFileButton: View {
    let path: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Text(URL(fileURLWithPath: path).lastPathComponent)
                .font(.caption2)
                .lineLimit(1)
                .foregroundStyle(Color(nsColor: .textBackgroundColor))
                .padding(.horizontal, 8)
                .frame(height: 20)
                .background {
                    Capsule()
                        .fill(Color(nsColor: .textColor).opacity(isHovered ? 1 : 0.5))
                }
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(path)
    }
}

private extension ProcessingTaskState {
    var isActive: Bool {
        self == .pending || self == .validating || self == .running
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
