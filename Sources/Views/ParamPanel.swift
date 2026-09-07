import SwiftUI

// MARK: - 参数微调面板（按模式独立保存）

struct ParamPanel: View {
    @EnvironmentObject var app: AppState
    let mode: GenMode
    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("参数微调（\(mode.rawValue)独立保存）", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("恢复默认") {
                    withAnimation { app.activeParams = .defaultParams }
                }
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            // 主行
            HStack(spacing: 18) {
                LangPicker(p: $app.activeParams.language)
                SliderRow(title: "温度", value: $app.activeParams.temperature, range: 0.1...2.0, format: "%.2f", tip: "越高越有变化，越低越稳")
                IntRow(title: "top-k", value: $app.activeParams.topK, range: 0...200, tip: "0 = 关闭")
                SliderRow(title: "top-p", value: $app.activeParams.topP, range: 0.0...1.0, format: "%.2f", tip: "1.0 = 关闭")
                SliderRow(title: "min-p", value: $app.activeParams.minP, range: 0.0...0.5, format: "%.2f", tip: "0 = 关闭")
            }
            .frame(height: 44)

            // 高级行
            HStack(spacing: 18) {
                IntRow(title: "seed（-1 随机）", value: $app.activeParams.seed, range: -1...99999, tip: "固定种子可复现同一条音频")
                IntRow(title: "ctx-size", value: $app.activeParams.ctxSize, range: 512...32768, step: 512, tip: "别开 32K：会多吃 3.5GB 显存")
                IntRow(title: "最大帧（-1 不限）", value: $app.activeParams.maxFrames, range: -1...2000, tip: "防止重复不停（上游 bug 兜底）")
                IntRow(title: "线程（0 自动）", value: $app.activeParams.threads, range: 0...16, tip: "0 = 让 llama.cpp 自己决定")
                Button(showAdvanced ? "收起" : "展开") { withAnimation { showAdvanced.toggle() } }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
            .frame(height: 44)
            .opacity(showAdvanced ? 1 : 0.75)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor).opacity(0.55)))
    }
}

// MARK: - 行控件

struct LangPicker: View {
    @Binding var p: String
    private let langs = ["zh","en","ja","ko","fr","de","es","it","pt","ru"]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("语言").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $p) {
                ForEach(langs, id: \.self) { l in Text(l).tag(l) }
            }
            .pickerStyle(.menu)
            .frame(width: 84)
        }
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var format: String = "%.2f"
    var tip: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: format, value))
                    .font(.caption.monospacedDigit()).foregroundStyle(.primary)
            }
            Slider(value: $value, in: range)
                .controlSize(.small)
        }
        .frame(width: 150)
        .help(tip)
    }
}

struct IntRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    var step: Int = 1
    var tip: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Button("-") { value = max(range.lowerBound, value - step) }
                    .buttonStyle(.borderless).font(.caption)
                TextField("", value: $value, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)
                    .font(.caption.monospacedDigit())
                    .onSubmit { value = min(max(value, range.lowerBound), range.upperBound) }
                Button("+") { value = min(range.upperBound, value + step) }
                    .buttonStyle(.borderless).font(.caption)
            }
        }
        .frame(width: 150)
        .help(tip)
    }
}
