//
//  PrivateFile.swift
//  PasteDeck
//
//  私有文件原子写入：0700 目录、0600 文件、同目录临时文件 + rename。
//  行为对齐 codex-router 的 file-security.mjs（writePrivateFile / privateFileIsProtected）。
//

import Foundation

public enum PrivateFileError: LocalizedError {
    case symlinkedPath(String)
    case notProtected(String)

    public var errorDescription: String? {
        switch self {
        case .symlinkedPath(let path):
            return "路径是符号链接，拒绝写入：\(path)"
        case .notProtected(let path):
            return "文件权限不是 0600：\(path)"
        }
    }
}

/// 0600 私有文件的原子写入与校验。
public enum PrivateFile {

    /// 原子写入：临时文件（0600，同目录，独占创建）→ fsync → rename 覆盖。
    /// 目标路径或其父目录为符号链接时拒绝写入。
    static func writeAtomically(_ data: Data, to target: URL, directoryMode: mode_t = 0o700) throws {
        let targetPath = target.path
        // 拒绝符号链接目标（防替换攻击）。
        if isSymlink(at: targetPath) {
            throw PrivateFileError.symlinkedPath(targetPath)
        }
        let directory = target.deletingLastPathComponent()
        if isSymlink(at: directory.path) {
            throw PrivateFileError.symlinkedPath(directory.path)
        }
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryMode]
        )
        if directoryMode == 0o700 {
            try? FileManager.default.setAttributes(
                [.posixPermissions: directoryMode], ofItemAtPath: directory.path)
        }

        let temporaryName = ".tmp.\(getpid()).\(UUID().uuidString.prefix(8))"
        let temporary = directory.appendingPathComponent(temporaryName)
        FileManager.default.createFile(
            atPath: temporary.path, contents: nil,
            attributes: [.posixPermissions: 0o600])
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        try protect(temporary.path)
        if FileManager.default.fileExists(atPath: targetPath) {
            try FileManager.default.removeItem(atPath: targetPath)
        }
        try FileManager.default.moveItem(at: temporary, to: target)
    }

    static func writeAtomically(_ text: String, to target: URL, directoryMode: mode_t = 0o700) throws {
        try writeAtomically(Data(text.utf8), to: target, directoryMode: directoryMode)
    }

    /// 读取文件（存在且可读才返回）。
    static func readText(_ target: URL) -> String? {
        guard let data = FileManager.default.contents(atPath: target.path) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func readJSON<T: Decodable>(_ target: URL, as type: T.Type) -> T? {
        guard let data = FileManager.default.contents(atPath: target.path) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// chmod 0600。
    static func protect(_ path: String) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
    }

    /// 权限是否恰好 0600。
    static func isProtected(_ path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              let mode = attributes[.posixPermissions] as? NSNumber else { return false }
        return mode.uint16Value & 0o777 == 0o600
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    private static func isSymlink(at path: String) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else { return false }
        return (attributes[.type] as? FileAttributeType) == .typeSymbolicLink
    }
}
