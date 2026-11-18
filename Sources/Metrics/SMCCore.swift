// 部分实现参考自 Stats (https://github.com/exelban/stats)
// MIT License, Copyright (c) 2019 Serhiy Mytrovtsiy
// 详见项目根目录的 THIRD_PARTY_NOTICES.md

import Foundation
import IOKit

/// 精简版 AppleSMC 客户端：只做读取（温度/风扇），不需要 root 权限。
final class SMCConnection {
    struct KeyInfo {
        var dataSize: UInt32
        var dataType: UInt32
    }

    private var conn: io_connect_t = 0
    private var keyInfoCache: [UInt32: KeyInfo] = [:]
    private let lock = NSLock()

    private(set) var isOpen = false
    private(set) var lastOpenError: kern_return_t = KERN_SUCCESS

    // 与内核交互的数据结构（保持与 AppleSMC 期望的内存布局一致）
    private struct KeyDataVersion {
        var major: UInt8 = 0
        var minor: UInt8 = 0
        var build: UInt8 = 0
        var reserved: UInt8 = 0
        var release: UInt16 = 0
    }

    private struct KeyDataPLimit {
        var version: UInt16 = 0
        var length: UInt16 = 0
        var cpuPLimit: UInt32 = 0
        var gpuPLimit: UInt32 = 0
        var memPLimit: UInt32 = 0
    }

    private struct KeyDataKeyInfo {
        var dataSize: UInt32 = 0
        var dataType: UInt32 = 0
        var dataAttributes: UInt8 = 0
    }

    private struct KeyData {
        var key: UInt32 = 0
        var vers = KeyDataVersion()
        var pLimitData = KeyDataPLimit()
        var keyInfo = KeyDataKeyInfo()
        var padding: UInt16 = 0
        var result: UInt8 = 0
        var status: UInt8 = 0
        var data8: UInt8 = 0
        var data32: UInt32 = 0
        var bytes: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
                    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    }

    private enum Command: UInt8 {
        case readBytes = 5
        case readIndex = 8
        case readKeyInfo = 9
    }

    private static let kernelIndex: UInt32 = 2

    init() {
        open()
    }

    deinit {
        close()
    }

    private func open() {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("AppleSMC")
        var result = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator)
        guard result == KERN_SUCCESS else {
            lastOpenError = result
            return
        }
        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)
        guard device != 0 else {
            lastOpenError = kIOReturnNotFound
            return
        }
        result = IOServiceOpen(device, mach_task_self_, 0, &conn)
        IOObjectRelease(device)
        lastOpenError = result
        isOpen = (result == KERN_SUCCESS)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        keyInfoCache.removeAll()
        if conn != 0 {
            IOServiceClose(conn)
            conn = 0
        }
        isOpen = false
    }

    private func call(_ input: inout KeyData, _ output: inout KeyData) -> kern_return_t {
        let inputSize = MemoryLayout<KeyData>.stride
        var outputSize = MemoryLayout<KeyData>.stride
        return IOConnectCallStructMethod(conn, SMCConnection.kernelIndex, &input, inputSize,
                                         &output, &outputSize)
    }

    private func fourCC(_ string: String) -> UInt32 {
        var result: UInt32 = 0
        for byte in string.utf8.prefix(4) {
            result = (result << 8) | UInt32(byte)
        }
        return result
    }

    private func fourCCString(_ value: UInt32) -> String {
        let bytes = [
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff),
        ]
        return String(bytes: bytes, encoding: .ascii) ?? "????"
    }

    /// 读取原始字节
    private func readRaw(key: String) -> (info: KeyInfo, bytes: [UInt8])? {
        guard isOpen else { return nil }
        lock.lock()
        defer { lock.unlock() }

        var input = KeyData()
        var output = KeyData()
        input.key = fourCC(key)

        let keyInfo: KeyDataKeyInfo
        if let cached = keyInfoCache[input.key] {
            keyInfo = KeyDataKeyInfo(dataSize: cached.dataSize, dataType: cached.dataType)
        } else {
            input.data8 = Command.readKeyInfo.rawValue
            guard call(&input, &output) == KERN_SUCCESS, output.result == 0 else { return nil }
            keyInfo = output.keyInfo
            if keyInfo.dataSize > 0 && keyInfo.dataSize <= 32 && keyInfo.dataType != 0 {
                keyInfoCache[input.key] = KeyInfo(dataSize: keyInfo.dataSize, dataType: keyInfo.dataType)
            }
        }

        input.keyInfo.dataSize = keyInfo.dataSize
        input.data8 = Command.readBytes.rawValue
        guard call(&input, &output) == KERN_SUCCESS, output.result == 0 else { return nil }
        guard keyInfo.dataSize > 0, keyInfo.dataSize <= 32 else { return nil }

        let tuple = output.bytes
        let all: [UInt8] = [tuple.0, tuple.1, tuple.2, tuple.3, tuple.4, tuple.5, tuple.6, tuple.7,
                            tuple.8, tuple.9, tuple.10, tuple.11, tuple.12, tuple.13, tuple.14, tuple.15,
                            tuple.16, tuple.17, tuple.18, tuple.19, tuple.20, tuple.21, tuple.22, tuple.23,
                            tuple.24, tuple.25, tuple.26, tuple.27, tuple.28, tuple.29, tuple.30, tuple.31]
        let size = Int(keyInfo.dataSize)
        return (KeyInfo(dataSize: keyInfo.dataSize, dataType: keyInfo.dataType), Array(all.prefix(size)))
    }

    /// 解码为数值（温度、风扇转速等）
    func readValue(_ key: String) -> Double? {
        guard let (info, bytes) = readRaw(key: key), bytes.count >= 2 else { return nil }
        if bytes.allSatisfy({ $0 == 0 }) { return nil }
        let type = fourCCString(info.dataType)
        let b0 = Double(bytes[0])
        let b1 = Double(bytes[1])
        let u16 = b0 * 256 + b1
        switch type {
        case "flt ":
            guard bytes.count >= 4 else { return nil }
            let raw = UInt32(bytes[0]) | (UInt32(bytes[1]) << 8) | (UInt32(bytes[2]) << 16) | (UInt32(bytes[3]) << 24)
            return Double(Float(bitPattern: raw))
        case "sp78":
            return Double(Int8(bitPattern: bytes[0])) + b1 / 256.0
        case "sp87":
            return Double(Int8(bitPattern: bytes[0])) + b1 / 128.0
        case "sp5a":
            return u16 / 1024.0
        case "sp69":
            return u16 / 512.0
        case "sp4b":
            return u16 / 2048.0
        case "sp3c":
            return u16 / 4096.0
        case "sp1e":
            return u16 / 16384.0
        case "fpe2":
            return (b0 * 256 + b1) / 4.0
        case "ui8 ":
            return b0
        case "ui16":
            return u16
        case "ui32":
            guard bytes.count >= 4 else { return nil }
            return Double(UInt32(bytes[0]) << 24 | UInt32(bytes[1]) << 16 | UInt32(bytes[2]) << 8 | UInt32(bytes[3]))
        default:
            return nil
        }
    }

    /// 枚举所有键（首次调用较慢）
    func allKeys() -> [String] {
        guard isOpen else { return [] }
        guard let count = readValue("#KEY"), count > 0, count < 4096 else { return [] }
        var keys: [String] = []
        keys.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            var input = KeyData()
            var output = KeyData()
            input.data8 = Command.readIndex.rawValue
            input.data32 = UInt32(index)
            lock.lock()
            let result = call(&input, &output)
            lock.unlock()
            if result == KERN_SUCCESS && output.result == 0 {
                keys.append(fourCCString(output.key))
            }
        }
        return keys
    }
}
