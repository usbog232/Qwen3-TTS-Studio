import Foundation

/// 把 App 参数映射成 llama-tts 命令行
enum Engine {
    static func buildArgs(
        settings: Settings,
        params: ModeParams,
        mode: GenMode,
        text: String,
        speakerFile: String,
        output: String
    ) -> [String] {
        var args: [String] = []

        // 模型与编码器
        args += ["-m", settings.modelPath]
        let mm = settings.mmprojPath.trimmingCharacters(in: .whitespaces)
        if !mm.isEmpty && FileManager.default.fileExists(atPath: mm) {
            args += ["--mmproj", mm]
        }

        // 文本（可选风格/情感指令前缀）
        let plainText = text
        if !params.instruct.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let ins = params.instruct.trimmingCharacters(in: .whitespacesAndNewlines)
            args += ["-p", "用以下风格说：\(ins)。原文：\(plainText)"]
        } else {
            args += ["-p", plainText]
        }

        // 语言
        args += ["--tts-lang", params.language]

        // 参考音频（克隆 & 纯文本均可指定音色）
        let sp = speakerFile.trimmingCharacters(in: .whitespaces)
        if !sp.isEmpty { args += ["--tts-speaker-file", sp] }

        // 采样参数
        args += ["--temp", String(format: "%.4f", params.temperature)]
        args += ["--top-k", String(params.topK)]
        args += ["--top-p", String(format: "%.4f", params.topP)]
        args += ["--min-p", String(format: "%.4f", params.minP)]
        args += ["--seed", String(params.seed)]
        if params.ctxSize > 0 { args += ["--ctx-size", String(params.ctxSize)] }
        args += ["-n", String(params.maxFrames)]
        if params.threads > 0 { args += ["-t", String(params.threads)] }

        // 输出
        args += ["--output", output]
        return args
    }
}
