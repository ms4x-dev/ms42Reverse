//
//  Binaryimage.swift
//  ms42Reverse
//
//  Created by Richard on 9/8/2025.
//

import Foundation

/// Simple view over raw binary data.
struct BinaryImage {
    let data: Data
    let filename: String
    let baseAddress: UInt32 // optional use, default 0

    init(fileURL: URL, baseAddress: UInt32 = 0) throws {
        self.data = try Data(contentsOf: fileURL)
        self.filename = fileURL.lastPathComponent
        self.baseAddress = baseAddress
    }

    var size: Int { data.count }

    func slice(offset: Int, length: Int) -> Data? {
        guard offset >= 0, length >= 0, offset + length <= data.count else { return nil }
        return data.subdata(in: offset..<(offset + length))
    }

    func readUInt16LE(at offset: Int) -> UInt16? {
        guard let s = slice(offset: offset, length: 2) else { return nil }
        return UInt16(littleEndian: s.withUnsafeBytes { $0.load(as: UInt16.self) })
    }

    func readUInt8(at offset: Int) -> UInt8? {
        guard let s = slice(offset: offset, length: 1) else { return nil }
        return s.first
    }

    func readUInt16Array(at offset: Int, count: Int) -> [UInt16]? {
        guard let s = slice(offset: offset, length: count*2) else { return nil }
        return stride(from: 0, to: s.count, by: 2).compactMap {
            let v = s.subdata(in: $0..<$0+2)
            return UInt16(littleEndian: v.withUnsafeBytes { $0.load(as: UInt16.self) })
        }
    }
}
