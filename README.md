# Qwen3-TTS Studio

macOS 原生 App：基于 [llama.cpp](https://github.com/ggml-org/llama.cpp) `llama-tts` 的 **Qwen3-TTS 声音克隆 / 纯文本合成**工作站。

![tab](https://img.shields.io/badge/platform-macOS_13%2B-blue) ![lang](https://img.shields.io/badge/Swift-6.x-orange) ![deps](https://img.shields.io/badge/deps-zero-green)

## 功能

- **声音克隆**：上传/拖入一段参考人声（wav/mp3/m4a/flac），用那个声音读任意文本
- **纯文本合成**：不给人声参考，直接出默认音色
- 文本四种给法：直接输入、粘贴、导入 txt 文件、拖入
- **参数微调**（克隆 / 纯文本两个模式各自独立保存）：
  语言 · 温度 · top-k · top-p · min-p · seed · ctx-size · 最大帧数 · 线程
- **试听**：参考音频可试听、生成结果可试听、历史条目可试听
- **下载 / 另存为**：生成结果一键另存、在 Finder 中显示
- **路径设置**：llama-tts 路径、模型 GGUF、mmproj、默认保存目录，均可点选
- **直达 Finder**：每处路径旁都有「打开文件夹 / 在 Finder 中显示」
- 底部**运行日志台**：流式日志、帧进度、复制、收起/展开
- 历史记录：保留最近 30 条，可播放 / 打开 / 移除

## 前置要求

| 项 | 说明 |
|---|---|
| macOS 13+ | Apple Silicon 或 Intel |
| llama.cpp | **2026-08-04 之后**的构建（PR [#26254](https://github.com/ggml-org/llama.cpp/pull/26254) 合入后才支持 Qwen3-TTS） |
| 模型 | [ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF](https://huggingface.co/ggml-org/Qwen3-TTS-12Hz-1.7B-Base-GGUF)（主模型 + mmproj） |

验证 llama.cpp 版本：

```bash
~/llama.cpp/llama-tts --version
# 需要 build ≥ PR #26254（2026-08-04 合入）
```

## 构建与运行

```bash
git clone https://github.com/usbog232/Qwen3-TTS-Studio
cd Qwen3-TTS-Studio
./build_app.sh
open build/Qwen3-TTS-Studio.app
```

首次使用在「设置」页把四个路径指到你的文件（App 默认值已按常见布局预填）。

## 使用说明（最短路径）

1. 切到 **声音克隆** 页
2. 点「选择音频…」或把参考人声拖进虚线框
3. 输入/粘贴要合成的文字
4. 点「生成音频」
5. 底部绿条出现结果 → 试听 / 另存 / 打开文件夹

纯文本模式：切到 **纯文本合成** 页，跳过参考音频，其余相同。

## 参数说明（llama-tts 映射）

| App | CLI | 默认 | 说明 |
|---|---|---|---|
| 语言 | `--tts-lang` | `zh` | zh/en/ja/ko/fr/de/es/it/pt/ru |
| 参考音频 | `--tts-speaker-file` | — | 仅克隆模式，wav/mp3/m4a/flac |
| 温度 | `--temp` | 0.80 | 越高越发散 |
| top-k | `--top-k` | 40 | 0=关闭 |
| top-p | `--top-p` | 0.95 | 1.0=关闭 |
| min-p | `--min-p` | 0.05 | 0=关闭 |
| seed | `--seed` | -1 | -1=每次随机；固定值可复现 |
| ctx-size | `--ctx-size` | 4096 | **别开 32K**（上游会多吃 3.5GB KV，见 llama.cpp #27937） |
| 最大帧 | `-n` | -1 | 防 runaway 重复（上游 #26700 兜底） |
| 线程 | `-t` | 0 | 0=自动 |

## 已知问题

- 上游 bug [#26700](https://github.com/ggml-org/llama.cpp/issues/26700)：偶发重复短语 / 不停止。App 用「最大帧数」参数兜底。
- 上游 bug [#27937](https://github.com/ggml-org/llama.cpp/issues/27937)：默认 32K 上下文吃 3.5GB KV。App 默认给 4096。

## 架构

详见 [docs/PLAN.md](docs/PLAN.md)。

- Swift 6 / SwiftUI，零第三方依赖
- 不内嵌推理引擎：每次生成拉起一次 `llama-tts` 进程（`Process`），跑完即退
- 参数双份独立：`ModeParams` 按模式分开持久化，互不污染
- 状态机：`idle / running / success / failed`，失败原因写状态行不弹窗
- 日志流式：stderr 逐行追加 + 正则抓 `frames generated: N` 做进度
- 设置持久化：`~/Library/Application Support/Qwen3TTSStudio/settings.json`
- 历史持久化：同目录 `history.json`（≤30 条）

## 文件结构

```
Qwen3-TTS-Studio/
├── Package.swift
├── build_app.sh
├── docs/PLAN.md
└── Sources/
    ├── App.swift
    ├── AppState.swift
    ├── Engine.swift
    ├── Paths.swift
    └── Views/
        ├── RootView.swift
        ├── SynthesisTab.swift
        ├── ParamPanel.swift
        ├── ResultCard.swift
        ├── LogConsole.swift
        └── SettingsView.swift
```

## 授权

内部使用，基于 [Qwen3-TTS](https://huggingface.co/Qwen/Qwen3-TTS-12Hz-1.7B-Base)（Qwen 许可）与 [llama.cpp](https://github.com/ggml-org/llama.cpp)（MIT）。
