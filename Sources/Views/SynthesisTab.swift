import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - 生成页（克隆 / 纯文本共用）

struct SynthesisTab: View {
    @EnvironmentObject var app: AppState
    let mode: GenMode

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

// MARK: - 拖拽类型常量

enum DropTypes {
    static let audioExts: Set<String> = ["wav", "wave", "mp3", "m4a", "flac", "aac", "ogg"]
    static let textExts: Set<String> = ["txt", "text", "md", "markdown", "rtf"]
    static func accepts(_ url: URL, in set: Set<String>) -> Bool {
        set.contains(url.pathExtension.lowercased())
    }
}

// MARK: - 文本面板（支持拖入 txt）

struct TextPanel: View {
    @EnvironmentObject var app: AppState
    let mode: GenMode
    @State private var textError = ""
    @State private var dropHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("文本", systemImage: "text.quote")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(app.text.count) 字").font(.caption).foregroundStyle(.tertiary)
            }

            ZStack {
                TextEditor(text: $app.text)
                    .font(.body)
                    .frame(minHeight: 130)
                    .padding(6)
                    .overlay(alignment: .topLeading) {
                        if app.text.isEmpty {
                            Text("要合成的文字，可直接输入、粘贴，\n或把 txt / md 文件拖进这个框…")
                                .foregroundStyle(.tertiary)
                                .padding(14)
                                .allowsHitTesting(false)
                        }
                    }
                if dropHover {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.08))
                        .allowsHitTesting(false)
                        .overlay {
                            Label("松开导入文本", systemImage: "doc.badge.arrow.up")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).stroke(dropHover ? Color.clear : Color(nsColor: .quaternaryLabelColor)))
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first, DropTypes.accepts(u, in: DropTypes.textExts) else { return false }
                importText(from: u.path)
                return true
            } isTargeted: { dropHover = $0 }

            HStack(spacing: 10) {
                Button { importTextViaPanel() } label: { Label("导入 txt…", systemImage: "doc.badge.arrow.up") }
                Button("清空") { app.text = "" }
                    .disabled(app.text.isEmpty)
                if !textError.isEmpty {
                    Text(textError).font(.caption).foregroundStyle(.red).lineLimit(1)
                }
            }
            .font(.callout)
        }
    }

    private func importText(from path: String) {
        textError = ""
        if let s = try? String(contentsOfFile: path, encoding: .utf8) {
            app.text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let s = try? String(contentsOfFile: path) {
            app.text = s.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            textError = "读取失败：\(path)"
        }
    }

    private func importTextViaPanel() {
        let panel = NSOpenPanel()
        panel.allowedFileTypes = ["txt", "text", "md", "markdown", "rtf"]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            importText(from: url.path)
        }
    }
}

// MARK: - 参考音频面板（录音 + 拖入）

struct SpeakerPanel: View {
    @EnvironmentObject var app: AppState
    @State private var dropHover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("参考音频（克隆音色）", systemImage: "mic.circle.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if app.isRecording {
                    HStack(spacing: 6) {
                        Circle().fill(.red).frame(width: 8, height: 8)
                            .opacity(app.recordSeconds > 0 ? 1 : 0.4)
                        Text(String(format: "录音中 %.1fs", app.recordSeconds))
                            .font(.caption.monospacedDigit()).foregroundStyle(.red)
                    }
                }
            }

            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(app.speakerFile.isEmpty ? 0 : 0.06))
                    .overlay(RoundedRectangle(cornerRadius: 8)
                        .stroke(dropHover ? Color.accentColor : Color(nsColor: .quaternaryLabelColor),
                                style: StrokeStyle(lineWidth: dropHover ? 2 : 1.2, dash: app.speakerFile.isEmpty && !dropHover ? [5] : [])))
                if app.speakerFile.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "waveform").font(.title2).foregroundStyle(.tertiary)
                        Text("把一段人声文件拖进这里，\n或用下方「录音」直接录一段参考声\n（wav / mp3 / m4a / flac）")
                            .font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .padding(8)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "play.circle.fill").font(.largeTitle)
                            .foregroundStyle(app.playingFile == app.speakerFile ? Color.accentColor : .secondary)
                        Text((app.speakerFile as NSString).lastPathComponent)
                            .font(.callout.weight(.medium)).lineLimit(1)
                        Text(app.speakerFile)
                            .font(.caption).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, minHeight: 150)
                    .contentShape(Rectangle())
                    .onTapGesture { app.togglePlay(app.speakerFile) }
                }
                if dropHover {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.accentColor, lineWidth: 2)
                        .background(Color.accentColor.opacity(0.08))
                        .allowsHitTesting(false)
                        .overlay {
                            Label("松开设为参考音频", systemImage: "waveform")
                                .font(.callout.weight(.medium))
                                .foregroundStyle(Color.accentColor)
                        }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                guard let u = urls.first, DropTypes.accepts(u, in: DropTypes.audioExts) else { return false }
                app.speakerFile = u.path
                app.settings.lastSpeakerFile = u.path
                app.stopPlayback()
                return true
            } isTargeted: { dropHover = $0 }

            // 录音 / 文件操作行
            HStack(spacing: 10) {
                Button { app.toggleRecording() } label: {
                    Label(app.isRecording
                          ? String(format: "停止（%.0fs）", app.recordSeconds)
                          : "录音",
                          systemImage: app.isRecording ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(app.isRecording ? Color.red : Color.accentColor)
                .help(app.isRecording ? "点击停止并自动填入参考音频" : "用麦克风录一段参考人声（wav，自动填入）")

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
                } else {
                    Button { pickFile() } label: { Label("选择音频…", systemImage: "folder") }
                        .buttonStyle(.bordered)
                }

                if !app.speakerFile.isEmpty {
                    Button { Paths.revealInFinder(app.speakerFile) } label: {
                        Image(systemName: "arrow.up.forward.app")
                    }
                    .buttonStyle(.bordered)
                    .help("在 Finder 中显示")
                }
            }
            .font(.callout)

            if !app.recordError.isEmpty {
                Text(app.recordError)
                    .font(.caption).foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

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
