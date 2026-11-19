import AppKit

/// 访达扩展发来的动作在主 App 里统一执行，错误统一映射成用户看得懂的中文。
enum FinderActionError: LocalizedError {
    case readOnlyVolume
    case noPermission
    case missingDirectory
    case diskFull
    case tooManyDuplicates
    case other(String)

    var errorDescription: String? {
        switch self {
        case .readOnlyVolume:
            return "目标磁盘为只读"
        case .noPermission:
            return "没有写入权限"
        case .missingDirectory:
            return "目标文件夹已被移动或删除"
        case .diskFull:
            return "磁盘空间不足"
        case .tooManyDuplicates:
            return "同名文件过多"
        case .other(let message):
            return message
        }
    }
}

struct CreatedFile {
    let url: URL
    /// 非致命提示（例如 exFAT 卷不支持可执行位）
    let permissionWarning: String?
}

/// 新建文件 / 打开终端 / 打开编辑器 的具体实现。
/// 与扩展里的编辑器列表保持一致（appex 是独立二进制，无法直接复用本文件）。
enum FinderActions {

    // MARK: - 新建文件

    @discardableResult
    static func createFile(in directory: URL,
                           ext: String,
                           name: String? = nil) throws -> CreatedFile {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw FinderActionError.missingDirectory
        }

        let suffix = sanitizedExtension(ext)
        var base = sanitizedFileName(name) ?? "未命名"
        // 用户自己带了同名后缀时不要重复追加（api.md + Markdown → api.md）
        if base.lowercased().hasSuffix("." + suffix.lowercased()), base.count > suffix.count + 1 {
            base = String(base.dropLast(suffix.count + 1))
        }

        var index = 1
        while index <= 999 {
            let fileName = index == 1 ? "\(base).\(suffix)" : "\(base) \(index).\(suffix)"
            let candidate = directory.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: candidate.path) {
                index += 1
                continue
            }

            do {
                try skeleton(for: suffix).write(to: candidate, options: .withoutOverwriting)
            } catch let error as NSError {
                // 与另一个写入者撞名：继续递增，而不是直接报错
                if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteFileExistsError {
                    index += 1
                    continue
                }
                throw map(error)
            }

            var warning: String?
            if suffix == "sh" || suffix == "py" {
                do {
                    try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                          ofItemAtPath: candidate.path)
                } catch {
                    warning = "脚本已创建，但此磁盘不支持可执行权限"
                }
            }
            return CreatedFile(url: candidate, permissionWarning: warning)
        }
        throw FinderActionError.tooManyDuplicates
    }

    static func skeleton(for ext: String) -> Data {
        switch ext {
        case "json":
            return Data("{}\n".utf8)
        case "py":
            return Data("#!/usr/bin/env python3\n\n".utf8)
        case "sh":
            return Data("#!/bin/bash\n\n".utf8)
        default:
            return Data()
        }
    }

    /// 去掉路径分隔符、控制字符，并拒绝 "." / ".." / 隐藏文件开头
    static func sanitizedFileName(_ name: String?) -> String? {
        guard let name else { return nil }
        var cleaned = name
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "\u{0}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        while cleaned.hasSuffix(".") || cleaned.hasSuffix(" ") { cleaned.removeLast() }

        if cleaned.count > 80 {
            cleaned = String(cleaned.prefix(80))
        }
        return cleaned.isEmpty ? nil : cleaned
    }

    static func sanitizedExtension(_ ext: String) -> String {
        var cleaned = ext.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleaned.hasPrefix(".") { cleaned.removeFirst() }
        cleaned = cleaned
            .replacingOccurrences(of: "/", with: "")
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: " ", with: "")
        if cleaned.isEmpty { return "txt" }
        if cleaned.count > 12 { cleaned = String(cleaned.prefix(12)) }
        return cleaned
    }

    private static func map(_ error: Error) -> FinderActionError {
        let nsError = error as NSError
        switch (nsError.domain, nsError.code) {
        case (NSCocoaErrorDomain, NSFileWriteNoPermissionError):
            return .noPermission
        case (NSCocoaErrorDomain, NSFileWriteVolumeReadOnlyError):
            return .readOnlyVolume
        case (NSCocoaErrorDomain, NSFileNoSuchFileError):
            return .missingDirectory
        case (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError):
            return .diskFull
        case (NSPOSIXErrorDomain, Int(EACCES)), (NSPOSIXErrorDomain, Int(EPERM)):
            return .noPermission
        case (NSPOSIXErrorDomain, Int(EROFS)):
            return .readOnlyVolume
        case (NSPOSIXErrorDomain, Int(ENOENT)):
            return .missingDirectory
        case (NSPOSIXErrorDomain, Int(ENOSPC)):
            return .diskFull
        default:
            return .other(nsError.localizedDescription)
        }
    }

    // MARK: - 打开

    static func openTerminal(at directory: URL) {
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.open([directory],
                                withApplicationAt: terminal,
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                NSLog("FinderBridge: 打开终端失败 %@", error.localizedDescription)
            }
        }
    }

    static func open(paths: [URL], bundleID: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            NSLog("FinderBridge: 找不到应用 %@", bundleID)
            return
        }
        NSWorkspace.shared.open(paths,
                                withApplicationAt: app,
                                configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error {
                NSLog("FinderBridge: 打开 %@ 失败 %@", bundleID, error.localizedDescription)
            }
        }
    }
}
