import AppKit
import ShoutouCore
import SwiftUI

enum ComposerField: Hashable {
    case captureTitle
    case captureSubtask
    case mainTitle(UUID)
    case mainSubtask(UUID)
}

struct QuestBoardView: View {
    var store: QuestStore
    var chrome: AppChrome

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: ComposerField?

    @State private var draftTitle = ""
    @State private var draftNext = ""
    @State private var titleError: String?
    @State private var isComposing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                board
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            bottom
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background(scheme))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .tint(Theme.accent(scheme))
        .onChange(of: isComposing) { _, composing in
            guard composing else { return }
            DispatchQueue.main.async {
                focus = .captureTitle
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("手头")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.primaryText(scheme))
                .accessibilityAddTraits(.isHeader)
            WindowDragHandle()
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .accessibilityHidden(true)
            Button(isComposing ? "取消" : "+") {
                toggleComposer()
            }
            .buttonStyle(QuietButtonStyle(tone: .accent))
            .accessibilityLabel(isComposing ? "取消添加" : "添加任务")
            .help(isComposing ? "收起添加" : "添加一条任务")
            Button(chrome.isPinned ? "已固定" : "固定") {
                chrome.setPinned(!chrome.isPinned)
            }
            .buttonStyle(QuietButtonStyle(tone: chrome.isPinned ? .accent : .neutral))
            .help(chrome.isPinned ? "已留在最前面。再按一次就取消。" : "留在最前面，点别的窗口也不会关。")
            if store.activeCount > 0 {
                Text("\(store.activeCount) 件在做")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText(scheme))
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var board: some View {
        VStack(alignment: .leading, spacing: 22) {
            if store.isCompletelyEmpty {
                emptyState
            } else {
                if store.main == nil && store.sideQuests.isEmpty {
                    Text("现在没有在做的事。")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.primaryText(scheme))
                }
                if let main = store.main {
                    MainQuestCard(
                        quest: main,
                        focus: $focus,
                        onComplete: { animate { store.complete(main.id) } },
                        onPark: { animate { store.park(main.id) } },
                        onTitle: { store.updateText(id: main.id, title: $0) },
                        onAddSubtask: { store.addSubtask(questID: main.id, title: $0) },
                        onToggleSubtask: { subtask, isDone in
                            store.setSubtaskDone(questID: main.id, subtaskID: subtask.id, isDone: isDone)
                        },
                        onRemoveSubtask: { store.removeSubtask(questID: main.id, subtaskID: $0.id) }
                    )
                    .id(main.id)
                }
                if !store.sideQuests.isEmpty {
                    section(title: "支线") {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(store.sideQuests) { quest in
                                SideQuestRow(
                                    quest: quest,
                                    primary: "盯这件",
                                    primaryAction: { animate { store.focus(quest.id) } },
                                    secondary: "放下",
                                    secondaryAction: { animate { store.park(quest.id) } }
                                )
                            }
                        }
                    }
                }
                if !store.parkedQuests.isEmpty {
                    section(title: "放下了") {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(store.parkedQuests) { quest in
                                SideQuestRow(
                                    quest: quest,
                                    primary: "捡回来",
                                    primaryAction: { animate { store.resume(quest.id) } },
                                    secondary: "删掉",
                                    secondaryAction: { animate { store.remove(quest.id) } },
                                    showsWhen: true
                                )
                            }
                        }
                    }
                }
                if !store.doneQuests.isEmpty {
                    section(title: "已完成") {
                        VStack(alignment: .leading, spacing: 16) {
                            ForEach(store.doneQuests) { quest in
                                DoneQuestRow(quest: quest) {
                                    animate { store.resume(quest.id) }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private func animate(_ change: () -> Void) {
        if reduceMotion {
            change()
        } else {
            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                change()
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "flag")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(Theme.accent(scheme))
                .accessibilityHidden(true)
            Text("手头是空的")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.primaryText(scheme))
            Text("点加号，写下正在做的事。菜单栏会留着主线。")
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondaryText(scheme))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var bottom: some View {
        VStack(alignment: .leading, spacing: 14) {
            if isComposing {
                composer
            }
            footer
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(Theme.background(scheme))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Theme.line(scheme))
                .frame(height: 1)
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledInput(
                label: "在做什么",
                text: $draftTitle,
                prompt: "例如：改实验脚本",
                error: titleError,
                isFocused: focus == .captureTitle,
                lineLimit: 1...1,
                focus: $focus,
                field: .captureTitle,
                onSubmit: { focus = .captureSubtask }
            )
            .onChange(of: draftTitle) { _, newValue in
                if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    titleError = nil
                }
            }

            LabeledInput(
                label: "小任务",
                text: $draftNext,
                prompt: "先放一条在这条下面",
                helper: "可以空着。记下之后，还能继续往下加。",
                isFocused: focus == .captureSubtask,
                lineLimit: 1...1,
                focus: $focus,
                field: .captureSubtask,
                onSubmit: commit
            )

            if let saveError = store.saveError {
                Text(saveError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.error(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: commit) {
                Text("记下")
            }
            .buttonStyle(FillButtonStyle())
            .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .keyboardShortcut(.return, modifiers: .command)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "登录时打开",
                isOn: Binding(
                    get: { chrome.launchAtLogin },
                    set: { chrome.setLaunchAtLogin($0) }
                )
            )
            .font(.system(size: 12.5, weight: .medium))
            .foregroundStyle(Theme.primaryText(scheme))
            .toggleStyle(.switch)
            .controlSize(.small)

            HStack(alignment: .firstTextBaseline) {
                Text(chrome.hotkeyReady ? "⌥空格 打开" : "⌥空格 被占用了")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(chrome.hotkeyReady ? Theme.secondaryText(scheme) : Theme.error(scheme))
                Spacer(minLength: 8)
                Button("退出") {
                    store.flush()
                    NSApp.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.secondaryText(scheme))
            }

            if let loginError = chrome.loginError {
                Text(loginError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.error(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func commit() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            titleError = "先写在做什么。"
            focus = .captureTitle
            return
        }
        titleError = nil
        animate {
            store.add(title: title, subtaskTitle: draftNext)
            isComposing = false
        }
        draftTitle = ""
        draftNext = ""
    }

    private func toggleComposer() {
        animate {
            if isComposing {
                isComposing = false
                titleError = nil
            } else {
                isComposing = true
            }
        }
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText(scheme))
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }
}

private struct MainQuestCard: View {
    var quest: Quest
    var focus: FocusState<ComposerField?>.Binding
    var onComplete: () -> Void
    var onPark: () -> Void
    var onTitle: (String) -> Void
    var onAddSubtask: (String) -> Void
    var onToggleSubtask: (Subtask, Bool) -> Void
    var onRemoveSubtask: (Subtask) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var draftSubtask = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("主线")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent(scheme))
                .accessibilityAddTraits(.isHeader)

            TextField(
                "",
                text: Binding(get: { quest.title }, set: onTitle),
                prompt: Text("这条主线叫什么").foregroundStyle(Theme.secondaryText(scheme)),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .font(.system(size: 22, weight: .semibold))
            .foregroundStyle(Theme.primaryText(scheme))
            .focused(focus, equals: .mainTitle(quest.id))
            .focusEffectDisabled()
            .lineLimit(1...3)
            .onSubmit { focus.wrappedValue = .mainSubtask(quest.id) }

            SubtaskEditor(
                quest: quest,
                draft: $draftSubtask,
                isFocused: focus.wrappedValue == .mainSubtask(quest.id),
                focus: focus,
                onAdd: addSubtask,
                onToggle: onToggleSubtask,
                onRemove: onRemoveSubtask
            )

            HStack(spacing: 8) {
                Button("做完", action: onComplete)
                    .buttonStyle(QuietButtonStyle(tone: .accent))
                Button("放下", action: onPark)
                    .buttonStyle(QuietButtonStyle(tone: .neutral))
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card(scheme), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                .strokeBorder(Theme.line(scheme), lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("主线 \(quest.title)")
    }

    private func addSubtask() {
        let title = draftSubtask.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        onAddSubtask(title)
        draftSubtask = ""
        focus.wrappedValue = .mainSubtask(quest.id)
    }
}

private struct SubtaskEditor: View {
    var quest: Quest
    @Binding var draft: String
    var isFocused: Bool
    var focus: FocusState<ComposerField?>.Binding
    var onAdd: () -> Void
    var onToggle: (Subtask, Bool) -> Void
    var onRemove: (Subtask) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("小任务")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText(scheme))

            if quest.subtasks.isEmpty {
                Text("还没有小任务。")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText(scheme))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(quest.subtasks) { subtask in
                        SubtaskRow(
                            subtask: subtask,
                            onToggle: { onToggle(subtask, $0) },
                            onRemove: { onRemove(subtask) }
                        )
                    }
                }
            }

            HStack(spacing: 8) {
                TextField(
                    "",
                    text: $draft,
                    prompt: Text("加一条小任务").foregroundStyle(Theme.secondaryText(scheme))
                )
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(Theme.primaryText(scheme))
                .focused(focus, equals: .mainSubtask(quest.id))
                .focusEffectDisabled()
                .onSubmit(onAdd)

                Button("加上", action: onAdd)
                    .buttonStyle(QuietButtonStyle(tone: .accent))
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Theme.field(scheme), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(isFocused ? Theme.accent(scheme) : Theme.line(scheme), lineWidth: isFocused ? 1.5 : 1)
            )
        }
    }
}

private struct SubtaskRow: View {
    var subtask: Subtask
    var onToggle: (Bool) -> Void
    var onRemove: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(subtask.isDone ? "还原" : "完成") {
                onToggle(!subtask.isDone)
            }
            .buttonStyle(QuietButtonStyle(tone: subtask.isDone ? .neutral : .accent))
            .accessibilityLabel(subtask.isDone ? "还原 \(subtask.title)" : "完成 \(subtask.title)")

            Text(subtask.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(subtask.isDone ? Theme.secondaryText(scheme) : Theme.primaryText(scheme))
                .strikethrough(subtask.isDone, color: Theme.secondaryText(scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Button("删掉", action: onRemove)
                .buttonStyle(QuietButtonStyle(tone: .neutral))
                .accessibilityLabel("删掉 \(subtask.title)")
        }
    }
}

private struct SideQuestRow: View {
    var quest: Quest
    var primary: String
    var primaryAction: () -> Void
    var secondary: String
    var secondaryAction: () -> Void
    var showsWhen: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(quest.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.primaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                if let first = quest.openSubtasks.first {
                    Text(first.title)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondaryText(scheme))
                        .fixedSize(horizontal: false, vertical: true)
                    if quest.openSubtasks.count > 1 {
                        Text("还有 \(quest.openSubtasks.count - 1) 条")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.secondaryText(scheme))
                    }
                }
                if showsWhen {
                    Text(RelativeTime.text(for: quest.updatedAt))
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.secondaryText(scheme))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button(secondary, action: secondaryAction)
                    .buttonStyle(QuietButtonStyle(tone: .neutral))
                    .accessibilityLabel("\(secondary) \(quest.title)")
                Button(primary, action: primaryAction)
                    .buttonStyle(QuietButtonStyle(tone: .accent))
                    .accessibilityLabel("\(primary) \(quest.title)")
            }
        }
    }
}

private struct DoneQuestRow: View {
    var quest: Quest
    var onResume: () -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(quest.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.secondaryText(scheme))
                    .strikethrough(true, color: Theme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
                Text(RelativeTime.text(for: quest.completedAt ?? quest.updatedAt))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button("收回", action: onResume)
                .buttonStyle(QuietButtonStyle(tone: .neutral))
                .accessibilityLabel("收回 \(quest.title)")
        }
    }
}

private struct LabeledInput: View {
    @Environment(\.colorScheme) private var scheme

    var label: String
    @Binding var text: String
    var prompt: String
    var helper: String?
    var error: String?
    var isFocused: Bool
    var lineLimit: ClosedRange<Int>
    var focus: FocusState<ComposerField?>.Binding
    var field: ComposerField
    var onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.secondaryText(scheme))
            TextField(
                "",
                text: $text,
                prompt: Text(prompt).foregroundStyle(Theme.secondaryText(scheme)),
                axis: lineLimit.upperBound > 1 ? .vertical : .horizontal
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Theme.primaryText(scheme))
            .focused(focus, equals: field)
            .focusEffectDisabled()
            .lineLimit(lineLimit)
            .onSubmit(onSubmit)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.field(scheme), in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: isFocused || error != nil ? 1.5 : 1)
            )
            if let error {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.error(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            } else if let helper {
                Text(helper)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var borderColor: Color {
        if error != nil {
            return Theme.error(scheme)
        }
        if isFocused {
            return Theme.accent(scheme)
        }
        return Theme.line(scheme)
    }
}

private struct FillButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isEnabled ? Theme.onAccent(scheme) : Theme.disabledText(scheme))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                isEnabled ? Theme.accent(scheme) : Theme.disabledFill(scheme),
                in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
            )
            .scaleEffect(!reduceMotion && configuration.isPressed && isEnabled ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct QuietButtonStyle: ButtonStyle {
    enum Tone {
        case accent
        case neutral
    }

    var tone: Tone

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(foreground)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .scaleEffect(!reduceMotion && configuration.isPressed ? 0.98 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch tone {
        case .accent:
            Theme.accent(scheme)
        case .neutral:
            Theme.primaryText(scheme)
        }
    }

    private var background: Color {
        switch tone {
        case .accent:
            Theme.quietFill(scheme)
        case .neutral:
            Theme.field(scheme)
        }
    }

    private var border: Color {
        switch tone {
        case .accent:
            Theme.accent(scheme).opacity(0.45)
        case .neutral:
            Theme.line(scheme)
        }
    }
}

@MainActor
private enum RelativeTime {
    static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter
    }()

    static func text(for date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        DragView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

