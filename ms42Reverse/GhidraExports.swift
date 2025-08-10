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
        let dataRefs: [UInt32]
        let labels: [String: UInt32]
        
        init(
            name: String,
            startAddress: UInt32,
            endAddress: UInt32,
            dataRefs: [UInt32] = [],
            labels: [String: UInt32] = [:]
        ) {
            self.name = name
            self.startAddress = startAddress
            self.endAddress = endAddress
            self.dataRefs = dataRefs
            self.labels = labels
        }
    }
    
    let functions: [FunctionInfo]
    let labels: [String: UInt32]
    
    init(functions: [FunctionInfo] = [], labels: [String: UInt32] = [:]) {
        self.functions = functions
        self.labels = labels
    }
    
    static func load(from url: URL) throws -> GhidraExports {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(GhidraExports.self, from: data)
    }
}
