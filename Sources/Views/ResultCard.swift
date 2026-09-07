import SwiftUI
import AppKit

// MARK: - 结果卡（当前结果 + 历史）

struct ResultCard: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 当前成功结果
            if case .success(let s) = app.state,
               let first = app.history.first {
                HStack(spacing: 12) {
                    Image(systemName: "waveform.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text((first.file as NSString).lastPathComponent)
                            .font(.callout.weight(.medium))
                        Text(String(format: "%.2fs 音频 · %s", s, first.date.formatted(date: .omitted, time: .shortened)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { app.togglePlay(first.file) } label: {
                        Label(app.playingFile == first.file ? "停止" : "试听",
                              systemImage: app.playingFile == first.file ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    Button { Paths.saveCopy(of: first.file, to: (first.file as NSString).lastPathComponent) } label: {
                        Label("另存", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.bordered)
                    Button { Paths.revealInFinder(first.file) } label: {
                        Label("文件夹", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 10).fill(.green.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.green.opacity(0.25)))
            }

            // 历史
            if !app.history.isEmpty {
                HStack {
                    Label("历史", systemImage: "clock.arrow.circlepath")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("保留最近 30 条").font(.caption).foregroundStyle(.tertiary)
                }
                ForEach(app.history) { rec in
                    HStack(spacing: 10) {
                        Text(rec.mode == .clone ? "克" : "文")
                            .font(.caption2.weight(.bold))
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(rec.mode == .clone ? Color.purple.opacity(0.15) : Color.blue.opacity(0.15)))
                            .foregroundStyle(rec.mode == .clone ? .purple : .blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text((rec.file as NSString).lastPathComponent)
                                .font(.callout).lineLimit(1).truncationMode(.middle)
                            Text("\(rec.text)…")
                                .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                        Spacer()
                        Text(String(format: "%.1fs", rec.seconds))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        Button { app.togglePlay(rec.file) } label: {
                            Image(systemName: app.playingFile == rec.file ? "stop.fill" : "play.fill")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(app.playingFile == rec.file ? Color.accentColor : .secondary)
                        Button { Paths.revealInFinder(rec.file) } label: {
                            Image(systemName: "folder")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("打开文件夹")
                        Button { app.deleteRecord(rec.id) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help("从历史移除（不删文件）")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor).opacity(0.4)))
                }
            }
        }
        .padding(14)
    }
}
