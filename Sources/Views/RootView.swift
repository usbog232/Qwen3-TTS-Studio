import SwiftUI

// MARK: - 顶层 Tab

enum TopTab: String, CaseIterable, Identifiable {
    case clone = "声音克隆"
    case plain = "纯文本合成"
    case settings = "设置"
    var id: String { rawValue }
    var genMode: GenMode? {
        switch self {
        case .clone: return .clone
        case .plain: return .plain
        case .settings: return nil
        }
    }
}

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: TopTab = .clone

    var body: some View {
        VStack(spacing: 0) {
            // Tab 栏
            HStack(spacing: 6) {
                ForEach(TopTab.allCases) { t in
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) {
                            tab = t
                            if let m = t.genMode { app.currentMode = m }
                        }
                    } label: {
                        Text(t.rawValue)
                            .font(.system(size: 14, weight: tab == t ? .semibold : .regular))
                            .foregroundStyle(tab == t ? Color.accentColor : .secondary)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(tab == t ? Color.accentColor.opacity(0.12) : .clear)
                            )
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(app.isRunning ? "生成中…" : readyHint)
                    .font(.caption)
                    .foregroundStyle(app.isRunning ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 14)

            // 主内容
            Group {
                switch tab {
                case .clone: SynthesisTab(mode: .clone)
                case .plain: SynthesisTab(mode: .plain)
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 日志台（常驻底部）
            Divider()
            LogConsole()
        }
    }

    private var readyHint: String {
        if !FileManager.default.isExecutableFile(atPath: app.settings.binPath) { return "⚠ 未配置 llama-tts" }
        if !FileManager.default.fileExists(atPath: app.settings.modelPath) { return "⚠ 未配置模型" }
        if tab == .clone && (app.speakerFile.isEmpty || !FileManager.default.fileExists(atPath: app.speakerFile)) { return "待选参考音频" }
        return "就绪"
    }
}
