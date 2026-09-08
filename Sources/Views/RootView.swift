import SwiftUI

// MARK: - 顶层 Tab

enum TopTab: String, CaseIterable, Identifiable {
    case synth = "合成"
    case settings = "设置"
    var id: String { rawValue }
}

// MARK: - 根视图

struct RootView: View {
    @EnvironmentObject var app: AppState
    @State private var tab: TopTab = .synth

    var body: some View {
        VStack(spacing: 0) {
            // Tab 栏
            HStack(spacing: 6) {
                ForEach(TopTab.allCases) { t in
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) { tab = t }
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
                // 当前模式徽章：由是否提供参考音频自动判定
                modeBadge
                Text(app.isRunning ? "生成中…" : readyHint)
                    .font(.caption)
                    .foregroundStyle(app.isRunning ? Color.accentColor : .secondary)
            }
            .padding(.horizontal, 14)

            // 主内容
            Group {
                switch tab {
                case .synth: SynthesisTab()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 日志台（常驻底部）
            Divider()
            LogConsole()
        }
    }

    private var modeBadge: some View {
        Text(app.currentMode == .clone ? "模式：声音克隆" : "模式：纯文本合成")
            .font(.caption.weight(.medium))
            .foregroundStyle(app.currentMode == .clone ? Color.accentColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.08)))
    }

    private var readyHint: String {
        if !FileManager.default.isExecutableFile(atPath: app.settings.binPath) { return "⚠ 未配置 llama-tts" }
        if !FileManager.default.fileExists(atPath: app.settings.modelPath) { return "⚠ 未配置模型" }
        return "就绪"
    }
}
