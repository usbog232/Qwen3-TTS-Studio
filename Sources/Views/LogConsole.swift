import SwiftUI
import AppKit

// MARK: - 底部日志台

struct LogConsole: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(spacing: 0) {
            // 标题条
            HStack {
                Label("运行日志", systemImage: "terminal")
                    .font(.caption.weight(.semibold))
                if app.isRunning {
                    ProgressView().controlSize(.mini)
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(app.log.joined(separator: "\n"), forType: .string)
                } label: { Image(systemName: "doc.on.doc") }
                    .buttonStyle(.plain).help("复制全部日志")
                Button { app.clearLog() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).help("清空")
                Button { withAnimation(.easeOut(duration: 0.15)) { app.logExpanded.toggle() } } label: {
                    Image(systemName: app.logExpanded ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(.plain).help(app.logExpanded ? "收起" : "展开")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.6))

            if app.logExpanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        ForEach(Array(app.log.enumerated()), id: \.offset) { i, line in
                            Text(line)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(lineColor(line))
                                .textSelection(.enabled)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(i)
                        }
                    }
                    .frame(height: 300)
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: app.log.count) { _ in
                        if let last = app.log.indices.last {
                            withAnimation { proxy.scrollTo(last, anchor: .bottom) }
                        }
                    }
                }
            } else {
                // 收起时显示最后一行
                HStack {
                    if let last = app.log.last {
                        Text(last).font(.system(size: 11.5, design: .monospaced))
                            .lineLimit(1).truncationMode(.head)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("（空）").font(.caption).foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    private func lineColor(_ line: String) -> Color {
        if line.contains("error") || line.contains("W ") { return .orange }
        if line.contains(" I ") { return .primary }
        return .secondary
    }
}
