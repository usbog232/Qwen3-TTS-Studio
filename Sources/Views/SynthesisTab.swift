import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 生成页（克隆 / 纯文本共用）

struct SynthesisTab: View {
    @EnvironmentObject var app: AppState
    let mode: GenMode
    @State private var showImportAlert = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // 输入区：文本 + 参考音频（两列）
                HStack(alignment: .top, spacing: 16) {
                    TextPanel(mode: mode)
                    if mode == .clone {
                        SpeakerPanel()
                    }
                }

                // 参数面板
                ParamPanel(mode: mode)

                // 操作行
                HStack(spacing: 12) {
                    if app.isRunning {
                        Button { app.stopGeneration() } label: {
                            Label("停止", systemImage: "stop.fill").frame(width: 110)
                        }
                        .buttonStyle(.bordered)
                        .tint(.orange)
                    } else {
                        Button { app.startGeneration() } label: {
                            Label("生成音频", systemImage: "waveform.circle.fill").frame(width: 140)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    statusLabel
                    Spacer()
                    if app.framesSoFar > 0 {
                        Text("\(app.framesSoFar) 帧")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                // 结果卡 + 历史
                ResultCard()
            }
            .padding(16)
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard mode == .clone, let u = urls.first else { return false }
            if u.pathExtension.lowercased().hasPrefix("wav") || ["mp3","m4a","wav","flac","aac"].contains(u.pathExtension.lowercased()) {
                app.speakerFile = u.path
                app.settings.lastSpeakerFile = u.path
                return true
            }
            return false
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch app.state {
        case .idle:
            Text("—").foregroundStyle(.tertiary)
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("正在合成…").foregroundStyle(.secondary)
            }
        case .success(let s):
            Label(String(format: "成功 · %.2fs 音频", s), systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let msg):
            Text(msg).foregroundStyle(.red).lineLimit(2)
        }
    }
}

// MARK: - 文本面板

struct TextPanel: View {
    @EnvironmentObject var app: AppState
    let mode: GenMode
    @State private var importError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("文本", systemImage: "text.quote")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(app.text.count) 字").font(.caption).foregroundStyle(.tertiary)
            }
            TextEditor(text: $app.text)
                .font(.body)
                .frame(minHeight: 130)
                .padding(6)
                .background(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
                .overlay(alignment: .topLeading) {
                    if app.text.isEmpty {
                        Text(mode == .clone
                             ? "要合成的文字，可直接输入或粘贴…"
                             : "要合成的文字，可直接输入或粘贴…")
                            .foregroundStyle(.tertiary)
                            .padding(14)
                            .allowsHitTesting(false)
                    }
                }

            HStack(spacing: 10) {
                Button { importText() } label: { Label("导入 txt…", systemImage: "doc.badge.arrow.up") }
                Button("清空") { app.text = "" }
                    .disabled(app.text.isEmpty)
                if !importError.isEmpty {
                    Text(importError).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }
            .font(.callout)
        }
    }

    private func importText() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["txt", "text", "md", "markdown", "rtf"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            if let s = try? String(contentsOf: url, encoding: .utf8) {
                app.text = s.trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let s = try? String(contentsOf: url) {
                app.text = s.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                importError = "读取失败"
            }
        }
    }
}

// MARK: - 参考音频面板

struct SpeakerPanel: View {
    @EnvironmentObject var app: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("参考音频（克隆音色）", systemImage: "mic.circle.fill")
                    .font(.subheadline.weight(.semibold))
            }
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(app.speakerFile.isEmpty ? 0 : 0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary, style: StrokeStyle(lineWidth: 1.2, dash: app.speakerFile.isEmpty ? [5] : [])))
                if app.speakerFile.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform").font(.title2).foregroundStyle(.tertiary)
                        Text("把一段人声拖进这里，\n或点下方按钮选择（wav / mp3 / m4a）")
                            .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "play.circle.fill").font(.largeTitle)
                            .foregroundStyle(app.playingFile == app.speakerFile ? Color.accentColor : .secondary)
                        Text((app.speakerFile as NSString).lastPathComponent)
                            .font(.callout.weight(.medium)).lineLimit(1)
                        Text(speakerPath)
                            .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .contentShape(Rectangle())
                    .onTapGesture { app.togglePlay(app.speakerFile) }
                }
            }

            HStack(spacing: 10) {
                if !app.speakerFile.isEmpty {
                    Button { app.togglePlay(app.speakerFile) } label: {
                        Label(app.playingFile == app.speakerFile ? "停止" : "试听",
                              systemImage: app.playingFile == app.speakerFile ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.bordered)
                    Button { app.speakerFile = ""; app.settings.lastSpeakerFile = "" } label: {
                        Label("移除", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }
                Button { pickFile() } label: { Label(app.speakerFile.isEmpty ? "选择音频…" : "更换…", systemImage: "folder") }
                    .buttonStyle(.bordered)
                Button { Paths.revealInFinder(app.speakerFile) } label: {
                    Image(systemName: "arrow.up.forward.app")
                }
                .buttonStyle(.bordered)
                .help("在 Finder 中显示")
            }
            .font(.callout)
        }
    }

    private var speakerPath: String { app.speakerFile }

    private func pickFile() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["wav", "mp3", "m4a", "flac", "aac", "wave"]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            app.speakerFile = url.path
            app.settings.lastSpeakerFile = url.path
        }
    }
}
