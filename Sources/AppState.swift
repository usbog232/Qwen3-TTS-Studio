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
    /// 参考音频启用开关：true=使用参考音频(声音克隆)，false=禁用(纯文本合成但音频保留)
    var speakerEnabled: Bool = true
    /// 生成后保温（保持模型页缓存 N 分钟，期间再次生成命中缓存更快）
    var keepAlive: Bool = false
    var keepAliveMinutes: Int = 5
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
        if let v = json["speakerEnabled"] as? Bool { s.speakerEnabled = v }
        if let v = json["keepAlive"] as? Bool { s.keepAlive = v }
        if let v = json["keepAliveMinutes"] as? Int { s.keepAliveMinutes = v }
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
    /// 语调/语气/情感指令（自然语言，拼进文本前缀；Qwen3-TTS 的 controllability 通道）
    /// 留空 = 不做风格指令
    var instruct: String = ""

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
        appStateDelegate.appState = self
        loadSettings()
        loadHistory()
    }

    deinit {
        // 保温进程清理
        keepAliveStopTask?.cancel()
        keepAliveProc?.terminate()
        playbackTimer?.invalidate()
    }

    var settingsDir: String {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("xjtts", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.path
    }

    func saveSettings() {
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
        refreshSpeakerDuration()
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

    // MARK: 模式自动判定

    /// 模式判定：参考音频存在且启用 = 声音克隆；未提供或被开关禁用 = 纯文本合成
    /// 开关禁用时音频仍保留，随时可切回克隆
    var currentMode: GenMode {
        let hasSpeaker = !speakerFile.trimmingCharacters(in: .whitespaces).isEmpty
        return (hasSpeaker && settings.speakerEnabled) ? .clone : .plain
    }

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
        let sp = speakerFile.trimmingCharacters(in: .whitespaces)
        if !sp.isEmpty && !FileManager.default.fileExists(atPath: sp) {
            missing.append("参考音频文件不存在")
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

        // 开关禁用参考音频 → 不传给引擎（纯文本模式），但本地保留音频文件
        let effectiveSpeaker = settings.speakerEnabled ? speakerFile : ""
        let args = Engine.buildArgs(
            settings: settings,
            params: activeParams,
            mode: currentMode,
            text: text,
            speakerFile: effectiveSpeaker,
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
            scheduleKeepAlive(minutes: settings.keepAliveMinutes)
        } else {
            state = .failed("llama-tts 退出码 \(exitCode)（0=正常），请看日志")
        }
    }

    func stopGeneration() {
        process?.terminate()
    }

    // MARK: 播放（暂停/继续 + 时间轴 + 音量）

    @Published var playingFile: String?
    @Published var playPosition: Double = 0
    @Published var playDuration: Double = 0
    @Published var playVolume: Float = 1.0
    private var playbackTimer: Timer?

    /// 参考音频文件时长（不依赖播放，设置文件时即算好，供裁剪用）
    @Published var speakerDuration: Double = 0

    /// 是否真的在发声（播放中、未暂停、未播完）
    var isActive: Bool { player?.isPlaying == true }

    func togglePlay(_ file: String) {
        if playingFile == file {
            if isActive {
                player?.pause()
                stopPlaybackTimer()
            } else {
                // 暂停中 或 已自然播完 → 从暂停处/从头继续
                if (player?.currentTime ?? 0) >= (player?.duration ?? 0) {
                    player?.currentTime = 0
                }
                player?.play()
                startPlaybackTimer()
            }
            return
        }
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
            p.delegate = appStateDelegate
            p.volume = playVolume
            p.prepareToPlay()
            p.play()
            player = p
            playingFile = file
            playPosition = 0
            playDuration = p.duration
            startPlaybackTimer()
        } catch {
            state = .failed("播放失败：\(error.localizedDescription)")
        }
    }

    private func startPlaybackTimer() {
        stopPlaybackTimer()
        playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] t in
            Task { @MainActor in
                guard let self, let p = self.player, self.isActive else { t.invalidate(); return }
                self.playPosition = min(p.currentTime, p.duration)
            }
        }
    }

    private func stopPlaybackTimer() {
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    func seekPlayback(to seconds: Double) {
        guard let p = player else { return }
        let t = max(0, min(seconds, p.duration))
        p.currentTime = t
        playPosition = t
    }

    func setPlaybackVolume(_ v: Float) {
        playVolume = v
        player?.volume = v
    }

    func stopPlayback() {
        stopPlaybackTimer()
        player?.stop()
        player = nil
        playingFile = nil
        playPosition = 0
    }


    // MARK: - 生成后保温（keep 模型页缓存 N 分钟）

    @Published var keepAliveActive: Bool = false
    private var keepAliveProc: Process?
    private var keepAliveStopTask: Task<Void, Never>?

    func scheduleKeepAlive(minutes: Int) {
        guard settings.keepAlive, minutes > 0 else {
            stopKeepAlive()
            return
        }
        startKeepAliveProc()
        keepAliveStopTask?.cancel()
        keepAliveStopTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(minutes) * 60 * 1_000_000_000)
            if !Task.isCancelled { self.stopKeepAlive() }
        }
    }

    private func startKeepAliveProc() {
        // 已有保温进程就复用
        if let p = keepAliveProc, p.isRunning { return }
        let model = settings.modelPath
        guard FileManager.default.fileExists(atPath: model) else { return }
        let sh = Process()
        // 循环 touch 模型文件（每 15s 完整读一遍），把页缓存 keep 热
        sh.executableURL = URL(fileURLWithPath: "/bin/sh")
        sh.arguments = ["-c", "while true; do cat \"\(model)\" > /dev/null; sleep 15; done"]
        sh.standardOutput = FileHandle.nullDevice
        sh.standardError = FileHandle.nullDevice
        do {
            try sh.run()
            keepAliveProc = sh
            keepAliveActive = true
        } catch {
            keepAliveActive = false
        }
    }

    func stopKeepAlive() {
        keepAliveStopTask?.cancel()
        keepAliveStopTask = nil
        keepAliveProc?.terminate()
        keepAliveProc = nil
        keepAliveActive = false
    }

    // MARK: 参考音频裁剪（导出选中段落为新参考）

    @Published var trimFrom: Double = 0
    @Published var trimTo: Double = 0
    @Published var trimMessage: String = ""
    @Published var trimWorking: Bool = false

    /// 文件变更时刷新：时长 + 默认裁剪区间
    func refreshSpeakerDuration() {
        guard !speakerFile.isEmpty,
              let af = try? AVAudioFile(forReading: URL(fileURLWithPath: speakerFile)) else {
            speakerDuration = 0
            return
        }
        let total = Double(af.length) / af.processingFormat.sampleRate
        speakerDuration = total
        trimFrom = 0
        trimTo = min(total, 15)
        trimMessage = "文件时长 \(String(format: "%.2f", total))s，拖动下方滑块选段后导出"
    }

    func applyTrim() {
        guard !speakerFile.isEmpty else { return }
        guard let src = try? AVAudioFile(forReading: URL(fileURLWithPath: speakerFile)) else {
            trimMessage = "无法读取原文件"
            return
        }
        let fmt = src.processingFormat
        let sampleRate = fmt.sampleRate
        let from = min(trimFrom, speakerDuration)
        let to = max(trimTo, from + 0.1)
        let frameCount = AVAudioFrameCount((to - from) * sampleRate)
        guard frameCount >= 1600 else {
            trimMessage = "选段太短（<0.07s）"
            return
        }
        trimWorking = true
        do {
            let buffer = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: frameCount)
            guard let buffer else { throw NSError(domain: "trim", code: 2) }
            src.framePosition = AVAudioFramePosition(from * sampleRate)
            try src.read(into: buffer, frameCount: frameCount)
            buffer.frameLength = frameCount

            let stamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").prefix(15)
            let outPath = (Paths.ensureDir(settings.inputDir) as NSString)
                .appendingPathComponent("ref-trim-\(stamp).wav")
            guard let outFmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: fmt.channelCount) else {
                throw NSError(domain: "trim", code: 1)
            }
            let out = try AVAudioFile(forWriting: URL(fileURLWithPath: outPath), settings: outFmt.settings)
            try out.write(from: buffer)

            stopPlayback()
            speakerFile = outPath
            settings.lastSpeakerFile = outPath
            refreshSpeakerDuration()
            trimMessage = "已导出 \(String(format: "%.2f–%.2f", from, to))s → \((outPath as NSString).lastPathComponent)（已设为当前参考）"
        } catch {
            trimMessage = "裁剪失败：\(error.localizedDescription)"
        }
        trimWorking = false
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
            refreshSpeakerDuration()
        } else {
            recordError = "录音文件为空（没有采到声音），请重试"
            try? FileManager.default.removeItem(atPath: recordFile)
        }
    }
}

// MARK: - 播放结束回调（独立 delegate，规避 @MainActor 与 NSObject 协议冲突）

private let appStateDelegate = PlaybackFinishDelegate()

final class PlaybackFinishDelegate: NSObject, AVAudioPlayerDelegate {
    var appState: AppState?
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.appState?.stopPlayback()
        }
    }
}
