import Foundation
import Testing
@testable import ShoutouCore

@MainActor
struct QuestStoreTests {
    private func makeStore() throws -> QuestStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shoutou-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return QuestStore(fileURL: directory.appendingPathComponent("quests.json"))
    }

    @Test func newQuestBecomesMainAndPreviousStaysActive() throws {
        let store = try makeStore()
        store.add(title: "  改实验脚本  ", subtaskTitle: " 重跑 seed 3 ")
        store.add(title: "写方法", subtaskTitle: "补样本量")

        #expect(store.main?.title == "写方法")
        #expect(store.main?.openSubtasks.map(\.title) == ["补样本量"])
        #expect(store.sideQuests.map(\.title) == ["改实验脚本"])
        #expect(store.sideQuests.first?.openSubtasks.map(\.title) == ["重跑 seed 3"])
        #expect(store.menuBarTitle == "写方法")
        #expect(store.activeCount == 2)
    }

    @Test func emptyTitleIsIgnored() throws {
        let store = try makeStore()
        #expect(store.add(title: "   ", subtaskTitle: "还有内容") == nil)
        #expect(store.quests.isEmpty)
        #expect(store.menuBarTitle == "手头")
    }

    @Test func completingMainLeavesSideQuestsUnpicked() throws {
        let store = try makeStore()
        store.add(title: "支线那件", subtaskTitle: "先放着")
        let main = try #require(store.add(title: "主线那件", subtaskTitle: "收尾"))
        store.complete(main.id)

        #expect(store.main == nil)
        #expect(store.sideQuests.map(\.title) == ["支线那件"])
        #expect(store.doneQuests.map(\.title) == ["主线那件"])
        #expect(store.menuBarTitle == "选主线")
        #expect(store.menuBarToolTip == "打开手头，选一条主线")
    }

    @Test func parkResumeAndFocus() throws {
        let store = try makeStore()
        let first = try #require(store.add(title: "先做的", subtaskTitle: "写开头"))
        let second = try #require(store.add(title: "后做的", subtaskTitle: "对一下数据"))
        store.park(second.id)
        #expect(store.main?.id == nil)
        #expect(store.parkedQuests.map(\.id) == [second.id])
        #expect(store.menuBarTitle == "选主线")

        store.focus(first.id)
        #expect(store.main?.id == first.id)
        #expect(store.menuBarTitle == "先做的")

        store.resume(second.id)
        #expect(store.main?.id == first.id)
        #expect(store.sideQuests.map(\.id) == [second.id])
    }

    @Test func resumeBecomesMainWhenNothingIsFocused() throws {
        let store = try makeStore()
        let quest = try #require(store.add(title: "放下的文献", subtaskTitle: "删重复条目"))
        store.park(quest.id)
        store.resume(quest.id)
        #expect(store.main?.id == quest.id)
        #expect(store.menuBarToolTip == "删重复条目")
    }

    @Test func menuTitleClipsLongChinese() throws {
        let store = try makeStore()
        store.add(title: "把预实验里反应时过短的试次剪掉", subtaskTitle: "先标出来")
        #expect(store.menuBarTitle == "把预实验里反应时过短的试…")
        #expect(store.menuBarTitle.hasSuffix("…"))
        #expect(store.menuBarTitle.count == 13)
    }

    @Test func persistenceRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shoutou-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("quests.json")

        let store = QuestStore(fileURL: url)
        store.add(title: "回邮件", subtaskTitle: "附进度表")
        let kept = try #require(store.add(title: "改图", subtaskTitle: "导出 svg"))
        store.addSubtask(questID: kept.id, title: "导出 png")
        let first = try #require(kept.subtasks.first)
        store.setSubtaskDone(questID: kept.id, subtaskID: first.id, isDone: true)
        store.flush()

        let reloaded = QuestStore(fileURL: url)
        #expect(reloaded.main?.title == "改图")
        #expect(reloaded.main?.openSubtasks.map(\.title) == ["导出 png"])
        #expect(reloaded.main?.subtasks.map(\.title) == ["导出 svg", "导出 png"])
        #expect(reloaded.sideQuests.map(\.title) == ["回邮件"])
        #expect(reloaded.menuBarToolTip == "导出 png")
    }

    @Test func corruptFileIsKeptAside() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shoutou-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("quests.json")
        try Data("this is not json".utf8).write(to: url)

        let store = QuestStore(fileURL: url)
        #expect(store.quests.isEmpty)
        #expect(store.saveError == "原来的记录读不了，已另存一份。")
        #expect(FileManager.default.fileExists(atPath: url.appendingPathExtension("corrupt").path))
        let original = try String(contentsOf: url, encoding: .utf8)
        #expect(original == "this is not json")
    }

    @Test func legacyNextStepBecomesASubtask() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("shoutou-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("quests.json")
        let id = UUID()
        let json = """
        {
          "focusedID" : "\(id.uuidString)",
          "quests" : [
            {
              "completedAt" : null,
              "createdAt" : "2026-09-24T10:00:00Z",
              "id" : "\(id.uuidString)",
              "nextStep" : "导出 png",
              "status" : "active",
              "title" : "改图",
              "updatedAt" : "2026-09-24T10:00:00Z"
            }
          ]
        }
        """
        try Data(json.utf8).write(to: url)

        let store = QuestStore(fileURL: url)
        #expect(store.main?.title == "改图")
        #expect(store.main?.openSubtasks.map(\.title) == ["导出 png"])
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains("\"subtasks\""))
        #expect(!saved.contains("\"nextStep\""))
    }

    @Test func doneListKeepsTheEightMostRecent() throws {
        let store = try makeStore()
        for index in 0..<10 {
            let quest = try #require(store.add(title: "第\(index)件", subtaskTitle: ""))
            store.complete(quest.id)
        }
        #expect(store.doneQuests.count == 8)
        #expect(store.doneQuests.first?.title == "第9件")
        #expect(!store.doneQuests.contains(where: { $0.title == "第0件" }))
        #expect(!store.doneQuests.contains(where: { $0.title == "第1件" }))
    }
}
