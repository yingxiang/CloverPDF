import AppKit
import QuickLookThumbnailing
import QuickLookUI
import SwiftUI
import UniformTypeIdentifiers

struct TasksView: View {
    @EnvironmentObject private var model: AppModel
    @State private var collapsedSectionIDs: Set<String> = []
    @State private var sectionPendingDeletion: TaskSectionModel?
    @State private var selectionAnchor: UUID?

    var body: some View {
        Group {
            if let previewPath = model.taskPreviewPath {
                HSplitView {
                    taskList
                        .frame(minWidth: 420, idealWidth: 500, maxWidth: .infinity)
                        .layoutPriority(1)
                    taskPreview(path: previewPath)
                        .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
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
                                    .listRowInsets(EdgeInsets(top: 0, leading: 15, bottom: 0, trailing: 8))
                                    .selectableItem(
                                        isSelected: model.selectedTaskIDs.contains(task.id),
                                        outlineColor: Color(nsColor: .controlAccentColor)
                                    ) {
                                        updateSelection(task.id)
                                    }
                                    .tint(.primary)
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

    @ViewBuilder
    private func taskPreview(path: String) -> some View {
        if ["doc", "docx"].contains(URL(fileURLWithPath: path).pathExtension.lowercased()) {
            WordOutputThumbnail(path: path)
        } else {
            TaskOutputPreview(path: path)
        }
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

private struct WordOutputThumbnail: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 96, height: 120)
            }
        }
        .frame(maxWidth: 320, maxHeight: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: path) {
            image = await loadThumbnail()
        }
    }

    private func loadThumbnail() async -> NSImage? {
        let url = URL(fileURLWithPath: path)
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed { url.stopAccessingSecurityScopedResource() }
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: NSSize(width: 320, height: 420),
            scale: NSScreen.main?.backingScaleFactor ?? 2,
            representationTypes: .thumbnail
        )
        return await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.nsImage)
            }
        }
    }
}

private struct TaskOutputPreview: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> QLPreviewView {
        let view = ResizableQuickLookView(frame: .zero, style: .normal)!
        view.autostarts = true
        view.autoresizingMask = [.width, .height]
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        view.previewItem = URL(fileURLWithPath: path) as NSURL
    }
}

private final class ResizableQuickLookView: QLPreviewView {
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }
}

struct TaskSectionModel: Identifiable {
    let date: Date
    let type: TaskDisplayType
    var tasks: [ProcessingTaskRecord]
    var id: String { "\(date.timeIntervalSince1970):\(type.rawValue)" }
    var taskIDs: Set<UUID> { Set(tasks.map(\.id)) }

    static func group(_ tasks: [ProcessingTaskRecord]) -> [TaskSectionModel] {
        var sections: [TaskSectionModel] = []
        for task in tasks {
            let sectionDate = Date(timeIntervalSince1970: floor(task.createdAt.timeIntervalSince1970))
            let type = TaskDisplayType(task: task)
            if let index = sections.firstIndex(where: { $0.date == sectionDate && $0.type == type }) {
                sections[index].tasks.append(task)
            } else {
                sections.append(TaskSectionModel(date: sectionDate, type: type, tasks: [task]))
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
                    Text(section.type.title)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(Color.black.opacity(0.75))
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background {
                            Capsule().fill(section.type.color)
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
    @State private var outputFileSize: Int64?
    let task: ProcessingTaskRecord

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            taskIcon
            PDFItemDetails(
                title: displayTitle,
                titleIsUnavailable: outputAvailability == .missing,
                pageCount: task.inputPageCount,
                fileSize: displayedFileSize,
                metadataOverride: metadataOverride,
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
        .contentShape(RoundedRectangle(cornerRadius: 10).inset(by: 2))
        .onTapGesture(count: 2) {
            openGeneratedFile()
        }
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
                outputFileSize = nil
                return
            }
            outputAvailability = .unknown
            outputFileSize = nil
            let outputInfo = await Task.detached(priority: .utility) {
                let url = URL(fileURLWithPath: path)
                guard FileManager.default.fileExists(atPath: path) else {
                    return TaskOutputInfo(exists: false, fileSize: nil)
                }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey])
                return TaskOutputInfo(
                    exists: true,
                    fileSize: values?.fileSize.map(Int64.init)
                )
            }.value
            guard !Task.isCancelled else { return }
            outputAvailability = outputInfo.exists ? .available : .missing
            outputFileSize = outputInfo.fileSize
        }
    }

    private var displayedFileSize: Int64? {
        if task.kind == .convert, task.state == .succeeded {
            return outputFileSize
        }
        return task.inputFileSize
    }

    private var metadataOverride: String? {
        guard task.kind == .convert else { return nil }
        switch task.state {
        case .pending, .validating, .running:
            return String(localized: "Converting")
        case .succeeded, .failed, .cancelled, .interrupted:
            return nil
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

    private func openGeneratedFile() {
        guard task.state == .succeeded,
              outputAvailability == .available,
              let path = representativeOutputPath else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    @ViewBuilder
    private var taskIcon: some View {
        if (task.state == .pending || task.state == .running), outputAvailability != .available {
            TaskOutputFileIcon(path: outputIconPath)
                .frame(width: 48, height: 60)
        } else if let path = representativeOutputPath ?? task.inputPaths.first {
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

    private var outputIconPath: String {
        representativeOutputPath
            ?? task.outputPath
            ?? task.inputPaths.first
            ?? task.title
    }
}

private struct TaskOutputFileIcon: View {
    let path: String

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .padding(5)
    }
}

private enum TaskOutputAvailability: Equatable {
    case unknown
    case available
    case missing
}

private struct TaskOutputInfo: Sendable {
    let exists: Bool
    let fileSize: Int64?
}

enum TaskDisplayType: String, Hashable {
    case pdfMerge
    case pngMerge
    case jpgMerge
    case wordMerge
    case pdfToPDF
    case pdfToPNG
    case pdfToJPG
    case pdfToWord

    init(task: ProcessingTaskRecord) {
        let path = task.outputPaths?.first ?? task.outputPath ?? task.title
        let fileExtension = URL(fileURLWithPath: path).pathExtension.lowercased()
        if task.kind == .merge {
            self = switch fileExtension {
            case "png": .pngMerge
            case "jpg", "jpeg": .jpgMerge
            case "docx": .wordMerge
            default: .pdfMerge
            }
        } else {
            self = switch fileExtension {
            case "png": .pdfToPNG
            case "jpg", "jpeg": .pdfToJPG
            case "docx": .pdfToWord
            default: .pdfToPDF
            }
        }
    }

    var title: String {
        switch self {
        case .pdfMerge: String(localized: "PDF Merge")
        case .pngMerge: String(localized: "PNG Merge")
        case .jpgMerge: String(localized: "JPG Merge")
        case .wordMerge: String(localized: "Word Merge")
        case .pdfToPDF: String(localized: "PDF to PDF")
        case .pdfToPNG: String(localized: "PDF to PNG")
        case .pdfToJPG: String(localized: "PDF to JPG")
        case .pdfToWord: String(localized: "PDF to Word")
        }
    }

    var color: Color {
        switch self {
        case .pdfMerge: Color(red: 251 / 255, green: 192 / 255, blue: 58 / 255)
        case .pdfToPNG: Color(red: 98 / 255, green: 180 / 255, blue: 232 / 255)
        case .pdfToWord: Color(red: 159 / 255, green: 212 / 255, blue: 70 / 255)
        case .pdfToJPG, .pdfToPDF: Color(red: 189 / 255, green: 205 / 255, blue: 214 / 255)
        case .pngMerge: Color(red: 184 / 255, green: 184 / 255, blue: 176 / 255)
        case .jpgMerge: Color(red: 224 / 255, green: 200 / 255, blue: 192 / 255)
        case .wordMerge: Color(red: 163 / 255, green: 181 / 255, blue: 166 / 255)
        }
    }
}

private extension ProcessingTaskKind {
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
