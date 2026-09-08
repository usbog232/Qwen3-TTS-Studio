import AppKit
import AVFoundation
import Combine
import Foundation

// MARK: - 设置模型

struct Settings: Codable, Equatable {
    var binPath: String = NSString(string: "~/llama.cpp/llama-tts").expandingTildeInPath
    var modelPath: String = "/Volumes/nas/软件插件/ai/Models/llama/models/Qwen3-TTS-12Hz-1-7B-Base-GGUF/Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf"
    var mmprojPath: String = "/Volumes/nas/软件插件/ai/Models/llama/models/Qwen3-TTS-12Hz-1-7B-Base-GGUF/mmproj-Qwen3-TTS-12Hz-1.7B-Base-Q8_0.gguf"
    /// 输入目录：参考音频 / 录音（clone-ref-*.wav）
    var inputDir: String = NSString(string: "~/Music/xjtts/input").expandingTildeInPath
    /// 输出目录：生成结果（xjtts-*.wav）
    var outputDir: String = NSString(string: "~/Music/xjtts/output").expandingTildeInPath
    /// 记住的上次参考音频
    var lastSpeakerFile: String = ""
    /// 容错读取旧版 settings.json（可能缺 inputDir 等新字段，用默认值补齐）
    static func fromLoose(_ json: [String: Any]) -> Settings? {
        var s = Settings()
        if let v = json["binPath"] as? String { s.binPath = v }
        if let v = json["modelPath"] as? String { s.modelPath = v }
        if let v = json["mmprojPath"] as? String { s.mmprojPath = v }
        if let v = json["inputDir"] as? String { s.inputDir = v }
        if let v = json["outputDir"] as? String {
            // 旧版单目录：outputDir 指向旧根，则 input/output 都派生自它
            let legacy = NSString(string: "~/Music/xjtts").expandingTildeInPath
            if v == legacy {
                s.outputDir = (legacy as NSString).appendingPathComponent("output")
                s.inputDir = (legacy as NSString).appendingPathComponent("input")
            } else {
                s.outputDir = v
            }
        }
        if let v = json["lastSpeakerFile"] as? String { s.lastSpeakerFile = v }
        return s
    }
}

/// 单个模式（克隆 / 纯文本）的生成参数，互相独立
struct ModeParams: Codable, Equatable {
    var language: String = "zh"
    var temperature: Double = 0.80
    var topK: Int = 40
    var topP: Double = 0.95
    var minP: Double = 0.05
    var seed: Int = -1          // -1 = 每次随机
    var ctxSize: Int = 4096
    var maxFrames: Int = -1     // -1 = 不限
    var threads: Int = 0        // 0 = 自动

    static let defaultParams = ModeParams()
}

// MARK: - 生成状态

enum GenState: Equatable {
    case idle
    case running
    case success(Seconds: Double)
    case failed(String)
}

// MARK: - 生成模式

enum GenMode: String, CaseIterable, Identifiable, Codable {
    case clone = "声音克隆"
    case plain = "纯文本合成"
    var id: String { rawValue }
}

// MARK: - 历史记录条目

struct GenRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var mode: GenMode
    var file: String
    var text: String
    var seconds: Double
    var date: Date
}

// MARK: - AppState

@MainActor
final class AppState: ObservableObject {
    // 设置
    @Published var settings = Settings() { didSet { saveSettings() } }
    @Published var cloneParams = ModeParams()
    @Published var plainParams = ModeParams()

    // 输入
    @Published var text: String = ""
    @Published var speakerFile: String = ""

    // 运行
    @Published var state: GenState = .idle
    @Published var currentMode: GenMode = .clone
    @Published var framesSoFar: Int = 0
    @Published var log: [String] = []
    @Published var logExpanded: Bool = false

    // 历史
    @Published var history: [GenRecord] = []

    private var process: Process?
    private var lastOutputFile: String = ""
    private var player: AVAudioPlayer?

    // 麦克风录音
    private var recorder: AVAudioRecorder?
    @Published var isRecording: Bool = false
    @Published var recordSeconds: Double = 0
    private var recordTimer: Timer?
    private var recordFile: String = ""
    @Published var recordError: String = ""

    // MARK: 生命周期

    init() {
        loadSettings()
        loadHistory()
    }

    var settingsDir: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("xjtts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    private func saveSettings() {
        let url = URL(fileURLWithPath: settingsDir).appendingPathComponent("settings.json")
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: url)
        }
    }

    private func loadSettings() {
        let url = URL(fileURLWithPath: settingsDir).appendingPathComponent("settings.json")
        var loaded = Settings()
        if let data = try? Data(contentsOf: url) {
            if let s = try? JSONDecoder().decode(Settings.self, from: data) {
                loaded = s
            } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let s = Settings.fromLoose(json) {
                loaded = s
            }
        }
        settings = loaded
        speakerFile = settings.lastSpeakerFile
        migrateLegacyRecordingDir()
    }

    /// 旧版（单目录）里攒下的录音，搬到 input/ 保持 input/output 分离
    private func migrateLegacyRecordingDir() {
        let fm = FileManager.default
        let oldRoot = NSString(string: "~/Music/xjtts").expandingTildeInPath
        guard (try? fm.contentsOfDirectory(atPath: oldRoot)) != nil else { return }
        let inDir = Paths.ensureDir(settings.inputDir)
        for name in (try? fm.contentsOfDirectory(atPath: oldRoot)) ?? [] {
            guard name.hasPrefix("clone-ref-"), name.hasSuffix(".wav") else { continue }
            let src = (oldRoot as NSString).appendingPathComponent(name)
            let dst = (inDir as NSString).appendingPathComponent(name)
            try? fm.moveItem(atPath: src, toPath: dst)
        }
        // 老根目录空了就收掉
        if (try? fm.contentsOfDirectory(atPath: oldRoot))?.isEmpty == true,
           oldRoot != inDir, oldRoot != settings.outputDir {
            try? fm.removeItem(atPath: oldRoot)
        }
        // 上次参考音频若指向旧根，重映射到 input/
        if !settings.lastSpeakerFile.isEmpty {
            let oldBase = (settings.lastSpeakerFile as NSString).deletingLastPathComponent
            if oldBase == oldRoot {
                let name = (settings.lastSpeakerFile as NSString).lastPathComponent
                let newPath = (inDir as NSString).appendingPathComponent(name)
                if fm.fileExists(atPath: newPath) {
                    settings.lastSpeakerFile = newPath
                    speakerFile = newPath
                    saveSettings()
                }
            }
        }
    }

    private func loadHistory() {
        let url = URL(fileURLWithPath: settingsDir).appendingPathComponent("history.json")
        if let data = try? Data(contentsOf: url) {
            history = (try? JSONDecoder().decode([GenRecord].self, from: data)) ?? []
        }
    }

    private func saveHistory() {
        let url = URL(fileURLWithPath: settingsDir).appendingPathComponent("history.json")
        if let data = try? JSONEncoder().encode(history) {
            try? data.write(to: url)
        }
    }

    // MARK: 日志

    func appendLog(_ line: String) {
        log.append(line)
        if log.count > 800 { log.removeFirst(log.count - 800) }
    }

    func clearLog() { log.removeAll() }

    // MARK: 参数选择

    var activeParams: ModeParams {
        get { currentMode == .clone ? cloneParams : plainParams }
        set {
            if currentMode == .clone { cloneParams = newValue } else { plainParams = newValue }
        }
    }

    var isRunning: Bool { state == .running }

    // MARK: 生成

    func startGeneration() {
        guard !isRunning else { return }
        let text = self.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            state = .failed("请先输入要合成的文本")
            return
        }

        var missing: [String] = []
        if !FileManager.default.isExecutableFile(atPath: settings.binPath) { missing.append("llama-tts 路径") }
        if !FileManager.default.fileExists(atPath: settings.modelPath) { missing.append("模型 GGUF") }
        if currentMode == .clone {
            let sp = speakerFile.trimmingCharacters(in: .whitespaces)
            if sp.isEmpty { missing.append("参考音频（克隆模式必须）") }
            else if !FileManager.default.fileExists(atPath: sp) { missing.append("参考音频文件不存在") }
        }
        if !missing.isEmpty {
            state = .failed("缺失：\(missing.joined(separator: "、"))")
            return
        }

        // 输出文件
        let outDir = Paths.ensureDir(settings.outputDir)
        let stamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").prefix(15)
        let fname = "xjtts-\(currentMode == .clone ? "clone" : "plain")-\(stamp).wav"
        let outFile = (outDir as NSString).appendingPathComponent(fname)

        let args = Engine.buildArgs(
            settings: settings,
            params: activeParams,
            mode: currentMode,
            text: text,
            speakerFile: speakerFile,
            output: outFile
        )

        framesSoFar = 0
        clearLog()
        appendLog("$ \(settings.binPath) \(args.joined(separator: " "))")
        lastOutputFile = outFile
        state = .running

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: settings.binPath)
        proc.arguments = args
        proc.currentDirectoryURL = URL(fileURLWithPath: (settings.binPath as NSString).deletingLastPathComponent)
        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                self?.finishGeneration(exitCode: p.terminationStatus, outFile: outFile)
            }
        }

        // stderr 流式（llama.cpp 日志走 stderr）
        let pipe = Pipe()
        proc.standardError = pipe
        proc.standardOutput = Pipe()
        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { [weak self] h in
            let data = h.availableData
            guard !data.isEmpty else { return }
            let chunk = String(decoding: data, as: UTF8.self)
            for line in chunk.components(separatedBy: .newlines) where !line.isEmpty {
                Task { @MainActor in self?.handleLogLine(line) }
            }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            handle.readabilityHandler = nil
            state = .failed("启动失败：\(error.localizedDescription)")
        }
    }

    private func handleLogLine(_ line: String) {
        appendLog(line)
        if let m = line.range(of: #"frames generated: (\d+)"#, options: .regularExpression) {
            let numStr = line[m].replacingOccurrences(of: "frames generated: ", with: "")
            if let n = Int(numStr) { framesSoFar = n }
        }
    }

    private func finishGeneration(exitCode: Int32, outFile: String) {
        process = nil
        if exitCode == 0 && FileManager.default.fileExists(atPath: outFile) {
            // 从日志里抓音频时长
            var seconds = 0.0
            for l in log.reversed() {
                if let r = l.range(of: #"output audio = ([\d.]+)s"#, options: .regularExpression) {
                    let s = l[r].replacingOccurrences(of: "output audio = ", with: "").replacingOccurrences(of: "s", with: "")
                    seconds = Double(s) ?? 0
                    break
                }
            }
            if seconds == 0 {
                let attrs = try? FileManager.default.attributesOfItem(atPath: outFile)
                seconds = Double((attrs?[.size] as? Int) ?? 0) / 24000.0
            }
            state = .success(Seconds: seconds)
            let rec = GenRecord(id: UUID(), mode: currentMode, file: outFile,
                                text: text.prefix(80).description, seconds: seconds, date: Date())
            history.insert(rec, at: 0)
            if history.count > 30 { history.removeLast(history.count - 30) }
            saveHistory()
        } else {
            state = .failed("llama-tts 退出码 \(exitCode)（0=正常），请看日志")
        }
    }

    func stopGeneration() {
        process?.terminate()
    }

    // MARK: 播放

    var playingFile: String?

    func togglePlay(_ file: String) {
        if playingFile == file { stopPlayback(); return }
        play(file)
    }

    func play(_ file: String) {
        stopPlayback()
        guard FileManager.default.fileExists(atPath: file) else {
            state = .failed("音频文件不存在：\(file)")
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: URL(fileURLWithPath: file))
            p.prepareToPlay()
            p.play()
            player = p
            playingFile = file
        } catch {
            state = .failed("播放失败：\(error.localizedDescription)")
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        playingFile = nil
    }

    func deleteRecord(_ id: UUID) {
        history.removeAll { $0.id == id }
        saveHistory()
    }

    // MARK: 麦克风录音（参考声）

    func toggleRecording() {
        recordError = ""
        if isRecording { stopRecording(); return }
        startRecording()
    }

    private func startRecording() {
        // macOS：无需 AVAudioSession（那是 iOS 的），系统会在首次访问麦克风时弹 TCC 权限
        let inDir = Paths.ensureDir(settings.inputDir)
        let stamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").prefix(15)
        recordFile = (inDir as NSString).appendingPathComponent("clone-ref-\(stamp).wav")

        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: 24000, channels: 1) else {
            recordError = "无法创建音频格式"
            return
        }
        do {
            let rec = try AVAudioRecorder(url: URL(fileURLWithPath: recordFile),
                                          format: fmt)
            rec.isMeteringEnabled = true
            rec.prepareToRecord()
            rec.record()
            recorder = rec
            isRecording = true
            recordSeconds = 0
            recordTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] t in
                Task { @MainActor in
                    guard let self, let rec = self.recorder, rec.isRecording else {
                        t.invalidate(); return
                    }
                    self.recordSeconds = rec.currentTime
                }
            }
        } catch {
            recordError = "无法开始录音：\(error.localizedDescription)"
            if error.localizedDescription.lowercased().contains("permission") {
                recordError = "麦克风权限被拒绝。到 系统设置 → 隐私与安全性 → 麦克风 中开启，然后重试"
            }
        }
    }

    private func stopRecording() {
        recorder?.stop()
        recordTimer?.invalidate()
        recordTimer = nil
        recorder = nil
        isRecording = false
        let size = (try? FileManager.default.attributesOfItem(atPath: recordFile))?[.size] as? Int ?? 0
        if size > 0 {
            speakerFile = recordFile
            settings.lastSpeakerFile = recordFile
            stopPlayback()
        } else {
            recordError = "录音文件为空（没有采到声音），请重试"
            try? FileManager.default.removeItem(atPath: recordFile)
        }
    }
}
