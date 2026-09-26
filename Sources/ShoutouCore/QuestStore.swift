import Foundation
import Observation

public struct QuestSnapshot: Codable, Equatable, Sendable {
    public var quests: [Quest]
    public var focusedID: UUID?

    public init(quests: [Quest], focusedID: UUID?) {
        self.quests = quests
        self.focusedID = focusedID
    }
}

@MainActor
@Observable
public final class QuestStore {
    public private(set) var quests: [Quest] = []
    public private(set) var focusedID: UUID?
    public private(set) var revision: Int = 0
    public private(set) var saveError: String?
    public var composeToken: Int = 0

    @ObservationIgnored public var onChange: (@MainActor () -> Void)?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let encoder: JSONEncoder
    @ObservationIgnored private let decoder: JSONDecoder

    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Shoutou/quests.json")
    }

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        load()
    }

    public var main: Quest? {
        guard let focusedID else { return nil }
        return quests.first { $0.id == focusedID && $0.status == .active }
    }

    public var sideQuests: [Quest] {
        quests
            .filter { $0.status == .active && $0.id != focusedID }
            .sorted(by: newerFirst)
    }

    public var parkedQuests: [Quest] {
        quests
            .filter { $0.status == .parked }
            .sorted(by: newerFirst)
    }

    public var doneQuests: [Quest] {
        quests
            .filter { $0.status == .done }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
    }

    public var activeCount: Int {
        (main == nil ? 0 : 1) + sideQuests.count
    }

    public var isCompletelyEmpty: Bool {
        quests.isEmpty
    }

    public var menuBarTitle: String {
        if let main {
            let flat = main.title
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let shown = flat.isEmpty ? "未命名" : flat
            return Self.clip(shown, limit: 12)
        }
        if sideQuests.isEmpty {
            return "手头"
        }
        return "选主线"
    }

    public var menuBarToolTip: String {
        if let main {
            if let step = main.openSubtasks.first?.title
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !step.isEmpty
            {
                return Self.clip(step, limit: 80)
            }
            return main.title.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if !sideQuests.isEmpty {
            return "打开手头，选一条主线"
        }
        return "手头，正在做的事"
    }

    public func requestComposeFocus() {
        composeToken += 1
    }

    @discardableResult
    public func add(title: String, subtaskTitle: String = "") -> Quest? {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return nil }
        let now = Date()
        var subtasks: [Subtask] = []
        let trimmedSubtask = subtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSubtask.isEmpty {
            subtasks.append(Subtask(id: UUID(), title: trimmedSubtask, isDone: false))
        }
        let quest = Quest(
            id: UUID(),
            title: trimmedTitle,
            subtasks: subtasks,
            status: .active,
            createdAt: now,
            updatedAt: now,
            completedAt: nil
        )
        quests.append(quest)
        focusedID = quest.id
        revision += 1
        persistNow()
        return quest
    }

    @discardableResult
    public func addSubtask(questID: UUID, title: String) -> Subtask? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let index = quests.firstIndex(where: { $0.id == questID }) else { return nil }
        let subtask = Subtask(id: UUID(), title: trimmed, isDone: false)
        quests[index].subtasks.append(subtask)
        quests[index].updatedAt = Date()
        revision += 1
        persistNow()
        return subtask
    }

    public func setSubtaskDone(questID: UUID, subtaskID: UUID, isDone: Bool) {
        guard let questIndex = quests.firstIndex(where: { $0.id == questID }),
              let subtaskIndex = quests[questIndex].subtasks.firstIndex(where: { $0.id == subtaskID })
        else { return }
        guard quests[questIndex].subtasks[subtaskIndex].isDone != isDone else { return }
        quests[questIndex].subtasks[subtaskIndex].isDone = isDone
        quests[questIndex].updatedAt = Date()
        revision += 1
        persistNow()
    }

    public func removeSubtask(questID: UUID, subtaskID: UUID) {
        guard let index = quests.firstIndex(where: { $0.id == questID }) else { return }
        let before = quests[index].subtasks.count
        quests[index].subtasks.removeAll { $0.id == subtaskID }
        guard quests[index].subtasks.count != before else { return }
        quests[index].updatedAt = Date()
        revision += 1
        persistNow()
    }

    public func updateText(id: UUID, title: String) {
        guard let index = quests.firstIndex(where: { $0.id == id }) else { return }
        quests[index].title = title
        scheduleSave()
    }

    public func focus(_ id: UUID) {
        guard let index = quests.firstIndex(where: { $0.id == id && $0.status == .active }) else { return }
        guard focusedID != id else { return }
        focusedID = id
        quests[index].updatedAt = Date()
        revision += 1
        persistNow()
    }

    public func park(_ id: UUID) {
        guard let index = quests.firstIndex(where: { $0.id == id && $0.status == .active }) else { return }
        quests[index].status = .parked
        quests[index].updatedAt = Date()
        if focusedID == id {
            focusedID = nil
        }
        revision += 1
        persistNow()
    }

    public func complete(_ id: UUID) {
        guard let index = quests.firstIndex(where: { $0.id == id && $0.status != .done }) else { return }
        let now = Date()
        quests[index].status = .done
        quests[index].updatedAt = now
        quests[index].completedAt = now
        if focusedID == id {
            focusedID = nil
        }
        trimDone()
        revision += 1
        persistNow()
    }

    public func resume(_ id: UUID) {
        guard let index = quests.firstIndex(where: { $0.id == id && $0.status != .active }) else { return }
        quests[index].status = .active
        quests[index].completedAt = nil
        quests[index].updatedAt = Date()
        if focusedID == nil {
            focusedID = id
        }
        revision += 1
        persistNow()
    }

    public func remove(_ id: UUID) {
        quests.removeAll { $0.id == id }
        if focusedID == id {
            focusedID = nil
        }
        revision += 1
        persistNow()
    }

    public func flush() {
        persistNow()
    }

    public static func clip(_ text: String, limit: Int) -> String {
        if text.count <= limit {
            return text
        }
        return String(text.prefix(limit)) + "…"
    }

    private func newerFirst(_ lhs: Quest, _ rhs: Quest) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private func scheduleSave() {
        onChange?()
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    private func persistNow() {
        saveTask?.cancel()
        onChange?()
        do {
            try write()
            saveError = nil
        } catch {
            saveError = "没能保存，再试一次。"
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let snapshot = try decoder.decode(QuestSnapshot.self, from: data)
            quests = snapshot.quests
            focusedID = snapshot.focusedID
            let loadedFocus = focusedID
            let loadedCount = quests.count
            repairFocus()
            trimDone()
            if focusedID != loadedFocus || quests.count != loadedCount || legacyFileNeedsMigration(data) {
                try? write()
            }
        } catch {
            let backup = fileURL.appendingPathExtension("corrupt")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: fileURL, to: backup)
            quests = []
            focusedID = nil
            saveError = "原来的记录读不了，已另存一份。"
        }
    }

    private func legacyFileNeedsMigration(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questsJSON = object["quests"] as? [[String: Any]]
        else { return false }
        return questsJSON.contains { quest in
            quest["subtasks"] == nil && quest["nextStep"] != nil
        }
    }

    private func repairFocus() {
        if let focusedID, quests.contains(where: { $0.id == focusedID && $0.status == .active }) {
            return
        }
        self.focusedID = nil
    }

    private func trimDone() {
        let done = quests
            .filter { $0.status == .done }
            .sorted { ($0.completedAt ?? $0.updatedAt) > ($1.completedAt ?? $1.updatedAt) }
        guard done.count > 8 else { return }
        let extra = Set(done.dropFirst(8).map(\.id))
        quests.removeAll { extra.contains($0.id) }
    }

    private func write() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let snapshot = QuestSnapshot(quests: quests, focusedID: focusedID)
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }
}
