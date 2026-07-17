import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TasksView: View {
    @EnvironmentObject private var model: AppModel
    @State private var collapsedSectionIDs: Set<Date> = []
    @State private var sectionPendingDeletion: TaskSectionModel?
    @State private var selectionAnchor: UUID?

    var body: some View {
        Group {
            if let previewItem = model.taskPreviewItem {
                HSplitView {
                    taskList
                    PDFWorkspacePreview(item: previewItem)
                }
            } else {
                taskList
            }
        }
        .onAppear { model.updateTaskPreview() }
        .onChange(of: model.selectedTaskIDs) { _ in model.updateTaskPreview() }
        .alert(
            "Delete Task Section",
            isPresented: Binding(
                get: { sectionPendingDeletion != nil },
                set: { if !$0 { sectionPendingDeletion = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { sectionPendingDeletion = nil }
            Button("Delete", role: .destructive) { deletePendingSection() }
        } message: {
            Text("Delete all tasks in this section?")
        }
    }

    private var taskList: some View {
        VStack(spacing: 0) {
            if model.tasks.isEmpty {
                EmptyPDFState(title: "No tasks", icon: "list.bullet.rectangle")
            } else {
                List {
                    ForEach(taskSections) { section in
                        TaskSectionHeader(
                            section: section,
                            isCollapsed: collapsedSectionIDs.contains(section.id),
                            toggle: { toggle(section) },
                            requestDelete: { sectionPendingDeletion = section },
                            deleteImmediately: { delete(section) },
                            revealInFinder: { model.revealTasks(section.taskIDs) }
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))

                        if !collapsedSectionIDs.contains(section.id) {
                            ForEach(section.tasks) { task in
                                TaskRow(task: task)
                                    .environmentObject(model)
                                    .selectableItem(isSelected: model.selectedTaskIDs.contains(task.id)) {
                                        updateSelection(task.id)
                                    }
                            }
                        }
                    }
                }
                .listStyle(.inset)
                .environment(\.defaultMinListRowHeight, 40)
            }
        }
    }

    private var taskSections: [TaskSectionModel] {
        TaskSectionModel.group(model.tasks)
    }

    private func toggle(_ section: TaskSectionModel) {
        if collapsedSectionIDs.contains(section.id) {
            collapsedSectionIDs.remove(section.id)
        } else {
            collapsedSectionIDs.insert(section.id)
        }
    }

    private func delete(_ section: TaskSectionModel) {
        collapsedSectionIDs.remove(section.id)
        model.deleteTasks(section.taskIDs)
    }

    private func deletePendingSection() {
        guard let section = sectionPendingDeletion else { return }
        sectionPendingDeletion = nil
        delete(section)
    }

    private func updateSelection(_ id: UUID) {
        let update = ItemSelectionController.update(
            id: id,
            orderedIDs: model.tasks.map(\.id),
            selection: model.selectedTaskIDs,
            anchor: selectionAnchor
        )
        model.selectedTaskIDs = update.selection
        selectionAnchor = update.anchor
    }
}

struct TaskSectionModel: Identifiable {
    let date: Date
    let kind: ProcessingTaskKind
    var tasks: [ProcessingTaskRecord]
    var id: Date { date }
    var taskIDs: Set<UUID> { Set(tasks.map(\.id)) }

    static func group(_ tasks: [ProcessingTaskRecord]) -> [TaskSectionModel] {
        var sections: [TaskSectionModel] = []
        for task in tasks {
            let sectionDate = Date(timeIntervalSince1970: floor(task.createdAt.timeIntervalSince1970))
            if let index = sections.firstIndex(where: { $0.date == sectionDate }) {
                sections[index].tasks.append(task)
            } else {
                sections.append(TaskSectionModel(date: sectionDate, kind: task.kind, tasks: [task]))
            }
        }
        return sections
    }
}

private struct TaskSectionHeader: View {
    let section: TaskSectionModel
    let isCollapsed: Bool
    let toggle: () -> Void
    let requestDelete: () -> Void
    let deleteImmediately: () -> Void
    let revealInFinder: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggle) {
                HStack(spacing: 5) {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2)
                        .frame(width: 10)
                    Text(section.kind.taskSectionTitle)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(Color.black.opacity(0.75))
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background {
                            Capsule().fill(section.kind.taskSectionColor)
                        }
                    Text(TaskTimestampFormatter.string(from: section.date))
                        .monospacedDigit()
                        .fixedSize()
                    Spacer(minLength: 8)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: requestDelete) {
                Image(systemName: "trash")
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
        .frame(height: 20)
        .contextMenu {
            Button("Show in Finder", action: revealInFinder)
            Divider()
            Button("Delete", role: .destructive, action: deleteImmediately)
        }
    }
}

enum TaskTimestampFormatter {
    static func string(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

private struct TaskRow: View {
    @EnvironmentObject private var model: AppModel
    @State private var outputAvailability = TaskOutputAvailability.unknown
    let task: ProcessingTaskRecord

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            taskIcon
            PDFItemDetails(
                title: displayTitle,
                titleIsUnavailable: outputAvailability == .missing,
                pageCount: task.inputPageCount,
                fileSize: task.inputFileSize,
                path: directoryPath
            ) {
                if task.state == .running {
                    ProgressView(value: task.progress)
                        .frame(maxWidth: 220)
                }
                if task.state == .failed, let errorCode = task.errorCode {
                    Text(CloverPDFError.localizedDescription(for: errorCode))
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                if !task.inputPaths.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(task.inputPaths.enumerated()), id: \.offset) { _, path in
                                TaskFileButton(path: path) {
                                    model.revealSourceFile(atPath: path)
                                }
                            }
                        }
                    }
                    .frame(height: 22)
                }
            }
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
            if outputAvailability == .available {
                Button {
                    model.revealTasks(contextSelection)
                } label: {
                    Image(systemName: "folder")
                }
                .help("Show in Finder")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .contextMenu {
            if outputAvailability == .available {
                Button("Show in Finder") {
                    model.revealTasks(contextSelection)
                }
                Divider()
            }
            Button("Delete", role: .destructive) {
                model.deleteTasks(contextSelection)
            }
        }
        .task(id: representativeOutputPath) {
            guard let path = representativeOutputPath else {
                outputAvailability = .unknown
                return
            }
            outputAvailability = .unknown
            let exists = await Task.detached(priority: .utility) {
                FileManager.default.fileExists(atPath: path)
            }.value
            guard !Task.isCancelled else { return }
            outputAvailability = exists ? .available : .missing
        }
    }

    private var displayTitle: String {
        representativeOutputPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? task.title
    }

    private var directoryPath: String {
        if let representativeOutputPath {
            return URL(fileURLWithPath: representativeOutputPath).deletingLastPathComponent().path
        }
        if let targetDirectoryPath = task.targetDirectoryPath { return targetDirectoryPath }
        let sourcePath = task.inputPaths.first ?? ""
        return URL(fileURLWithPath: sourcePath).deletingLastPathComponent().path
    }

    private var representativeOutputPath: String? {
        outputPaths.first
    }

    private var outputPaths: [String] {
        if let outputPaths = task.outputPaths, !outputPaths.isEmpty { return outputPaths }
        return task.outputPath.map { [$0] } ?? []
    }

    private var contextSelection: Set<UUID> {
        model.selectedTaskIDs.contains(task.id) ? model.selectedTaskIDs : [task.id]
    }

    @ViewBuilder
    private var taskIcon: some View {
        if let path = representativeOutputPath ?? task.inputPaths.first {
            PDFThumbnail(fileURL: URL(fileURLWithPath: path))
                .frame(width: 48, height: 60)
                .clipped()
        } else {
            Image(systemName: task.kind.icon)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
                .frame(width: 48, height: 60)
        }
    }
}

private enum TaskOutputAvailability: Equatable {
    case unknown
    case available
    case missing
}

private extension ProcessingTaskKind {
    var taskSectionTitle: String {
        switch self {
        case .merge: String(localized: "PDF Merge")
        case .batchImage: String(localized: "PDF Batch Conversion")
        case .convert: String(localized: "PDF to Word Task")
        }
    }

    var taskSectionColor: Color {
        switch self {
        case .merge: Color(red: 251.0 / 255.0, green: 192.0 / 255.0, blue: 58.0 / 255.0)
        case .batchImage: Color(red: 98.0 / 255.0, green: 180.0 / 255.0, blue: 232.0 / 255.0)
        case .convert: Color(red: 159.0 / 255.0, green: 212.0 / 255.0, blue: 70.0 / 255.0)
        }
    }

    var icon: String {
        switch self {
        case .merge: "square.stack.3d.up"
        case .batchImage: "photo.on.rectangle.angled"
        case .convert: "doc.text"
        }
    }
}

private struct TaskFileButton: View {
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
