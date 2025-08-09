//
//  GhidraExports.swift
//  ms42Reverse
//
//  Created by Richard on 9/8/2025.
//

import Foundation

struct GhidraExports: Codable {
    struct FunctionInfo: Codable {
        let name: String
        let startAddress: UInt32
        let endAddress: UInt32
        let dataRefs: [UInt32]?
    }
    let functions: [FunctionInfo]
    let labels: [String: UInt32]?

    static func load(from url: URL) throws -> GhidraExports {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(GhidraExports.self, from: data)
    }
}
