import AppKit
import Foundation

/// 路径工具：展开 ~/、打开文件夹、选文件、另存为
enum Paths {
    /// 展开 ~ 与环境变量
    static func expand(_ raw: String) -> String {
        var s = (raw as NSString).expandingTildeInPath
        s = s.replacingOccurrences(of: "\\$", with: "$")
        return s
    }

    static func isExecutable(_ path: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: expand(path))
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: expand(path))
    }

    static func ensureDir(_ path: String) -> String {
        let p = expand(path)
        try? FileManager.default.createDirectory(atPath: p, withIntermediateDirectories: true)
        return p
    }

    /// 弹「选择文件夹」，返回路径或 nil
    static func pickDirectory(prompt: String = "选择文件夹") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = prompt
        return panel.runModal() == .OK ? panel.url!.path : nil
    }

    /// 弹「选择文件」，允许扩展名列表
    static func pickFile(allowTypes: [String], prompt: String = "选择文件") -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedFileTypes = allowTypes
        panel.prompt = "选择"
        panel.message = prompt
        return panel.runModal() == .OK ? panel.url!.path : nil
    }

    /// 在 Finder 中显示文件（不存在则显示其父目录）
    static func revealInFinder(_ path: String) {
        let p = expand(path)
        if FileManager.default.fileExists(atPath: p) {
            NSWorkspace.shared.selectFile(p, inFileViewerRootedAtPath: "")
        } else {
            let parent = (p as NSString).deletingLastPathComponent
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: parent)])
        }
    }

    /// 打开所在文件夹
    static func openFolder(containing path: String) {
        let parent = (expand(path) as NSString).deletingLastPathComponent
        NSWorkspace.shared.open(URL(fileURLWithPath: parent))
    }

    /// 另存为（音频文件）
    static func saveCopy(of source: String, to suggestedName: String) {
        let src = expand(source)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.canCreateDirectories = true
        panel.begin { resp in
            guard resp == .OK, let dest = panel.url else { return }
            do {
                if FileManager.default.fileExists(atPath: dest.path) {
                    try FileManager.default.removeItem(at: dest)
                }
                try FileManager.default.copyItem(atPath: src, toPath: dest.path)
                NSWorkspace.shared.selectFile(dest.path, inFileViewerRootedAtPath: "")
            } catch {
                NSLog("saveCopy failed: \(error)")
            }
        }
    }
}

/// 文件类型显示
extension String {
    var humanSize: String {
        let b = Int64(self) ?? 0
        if b > 1_000_000_000 { return String(format: "%.2f GB", Double(b) / 1_000_000_000) }
        if b > 1_000_000 { return String(format: "%.1f MB", Double(b) / 1_000_000) }
        if b > 1_000 { return String(format: "%.0f KB", Double(b) / 1_000) }
        return "\(b) B"
    }
}
