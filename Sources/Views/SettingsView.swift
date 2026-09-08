import SwiftUI
import AppKit

// MARK: - 设置页：路径管理 + 直达 Finder

struct SettingsView: View {
    @EnvironmentObject var app: AppState

    /// 保温时长的 Binding（slider 用）
    private var keepMinutesBinding: Binding<Double> {
        Binding {
            Double(app.settings.keepAliveMinutes)
        } set: { v in
            app.settings.keepAliveMinutes = Int(v)
            app.saveSettings()
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("路径设置")
                    .font(.title3.weight(.semibold))
                Text("改完即时保存。每行右侧：选择 / 打开文件夹 / 状态")
                    .font(.caption).foregroundStyle(.secondary)

                // llama-tts 可执行文件
                PathRow(title: "llama-tts 可执行文件", tip: "需要 2026-08 之后的 llama.cpp 构建（PR #26254）",
                        path: $app.settings.binPath,
                        valid: FileManager.default.isExecutableFile(atPath: app.settings.binPath), kind: .bin)

                PathRow(title: "模型 GGUF（backbone）", tip: "Qwen3-TTS 主模型",
                        path: $app.settings.modelPath,
                        valid: FileManager.default.fileExists(atPath: app.settings.modelPath), kind: .file)

                PathRow(title: "说话人编码器 mmproj", tip: "speaker encoder；纯文本模式没有它也能跑",
                        path: $app.settings.mmprojPath,
                        valid: !app.settings.mmprojPath.isEmpty && FileManager.default.fileExists(atPath: app.settings.mmprojPath), kind: .file)

                PathRow(title: "音频输入目录（参考/录音）", tip: "录音参考声落这里；拖入/选择的参考音频也可放这",
                        path: $app.settings.inputDir,
                        valid: true, kind: .dir)

                PathRow(title: "音频输出目录（生成结果）", tip: "每次生成自动创建",
                        path: $app.settings.outputDir,
                        valid: true, kind: .dir)

                Divider().padding(.vertical, 4)

                // 性能：生成后保温
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("性能", systemImage: "speedometer")
                            .font(.title3.weight(.semibold))
                    }
                    HStack(spacing: 10) {
                        Toggle(isOn: $app.settings.keepAlive.animation()) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("生成后保温模型（推荐）")
                                    .font(.subheadline.weight(.medium))
                                Text("开启后，每次成功生成会后台 keep 住模型页缓存一段时间，期间再次生成跳过冷加载，明显变快。App 退出自动释放。")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    if app.settings.keepAlive {
                        HStack(spacing: 10) {
                            Text("保温时长").font(.subheadline)
                            Slider(value: keepMinutesBinding, in: 1...30)
                                .frame(width: 180)
                            Text("\(app.settings.keepAliveMinutes) 分钟")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 4)
                        HStack(spacing: 8) {
                            Circle().fill(app.keepAliveActive ? .green : .gray)
                                .frame(width: 8, height: 8)
                            Text(app.keepAliveActive
                                 ? "保温中（下次生成将命中缓存）"
                                 : "当前未保温（最近未生成，或开关刚开）")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .padding(.leading, 4)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor).opacity(0.55)))

                Divider().padding(.vertical, 4)

                HStack {
                    Label("当前输出目录", systemImage: "music.note.list")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("打开音频文件夹") {
                        Paths.ensureDir(app.settings.outputDir)
                        NSWorkspace.shared.open(URL(fileURLWithPath: Paths.ensureDir(app.settings.outputDir)))
                    }
                    .buttonStyle(.bordered)
                }

                if let rec = app.history.first {
                    HStack {
                        Label("最新生成的音频", systemImage: "waveform")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("在 Finder 中显示") { Paths.revealInFinder(rec.file) }
                            .buttonStyle(.bordered)
                    }
                }

                Divider().padding(.vertical, 4)

                Text("关于")
                    .font(.subheadline.weight(.semibold))
                VStack(alignment: .leading, spacing: 4) {
                    Text("• App 每次生成拉起一次 llama-tts 进程，跑完即退，不常驻")
                    Text("• 「生成后保温」= 后台 keep 模型页缓存 N 分钟，期间再生成跳过冷加载")
                    Text("• 语调/语气/情感 = 自然语言指令拼进文本前缀（Qwen3-TTS controllability），克隆与纯文本都生效")
                    Text("• 纯文本模式也可指定音色；不指定则用默认音色")
                    Text("• 设置保存在 ~/Library/Application Support/xjtts/")
                    Text("• 上游已知问题：偶发重复短语（llama.cpp #26700），可用「最大帧」兜底")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(18)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - 单行路径控件

private struct PathRow: View {
    enum Kind { case bin, file, dir }
    let title: String
    var tip: String = ""
    @Binding var path: String
    let valid: Bool
    let kind: Kind

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(.subheadline.weight(.medium))
                Spacer()
                Circle().fill(valid ? .green : .red)
                    .frame(width: 8, height: 8)
                    .help(valid ? "路径有效" : "路径无效")
            }
            HStack(spacing: 8) {
                Text(path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button { pick() } label: { Image(systemName: "folder") }
                    .buttonStyle(.bordered)
                    .help("选择…")
                Button { openContaining() } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.bordered)
                    .help("打开所在文件夹")
            }
            if !tip.isEmpty {
                Text(tip).font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    private func pick() {
        let panel = NSOpenPanel()
        switch kind {
        case .bin:
            panel.canChooseFiles = true; panel.canChooseDirectories = false
            panel.message = "选择 llama-tts 可执行文件"
        case .file:
            panel.allowedFileTypes = ["gguf"]
            panel.canChooseFiles = true; panel.canChooseDirectories = false
            panel.message = "选择 GGUF 文件"
        case .dir:
            panel.canChooseDirectories = true; panel.canChooseFiles = false
            panel.message = "选择保存目录"
        }
        if panel.runModal() == .OK, let url = panel.url {
            path = url.path
        }
    }

    private func openContaining() {
        let p = (path as NSString).expandingTildeInPath
        if kind == .dir {
            Paths.ensureDir(p)
            NSWorkspace.shared.open(URL(fileURLWithPath: p))
        } else {
            Paths.openFolder(containing: p)
        }
    }
}
