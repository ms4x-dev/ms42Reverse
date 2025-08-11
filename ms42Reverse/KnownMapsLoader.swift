//
//  KnownMapsLoader.swift
//  ms42Reverse
//
//  Created by assistant patcher.
//

import Foundation

public struct KnownMapTemplate: Codable {
    public let title: String?
    public let offset: Int?
    public let indexcountx: String?
    public let indexcounty: String?
    public let elementsizebits: String?
    public let datatype: String?
    public let decimalpl: String?
    public let units: String?
    public let description: String?
    public let raw: String?
}

public final class KnownMapsLoader {
    public private(set) var templatesByOffset: [Int: KnownMapTemplate] = [:]
    public private(set) var rawXmlByOffset: [Int: String] = [:]

    public init() {}

    public func load(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        let arr = try decoder.decode([KnownMapTemplate].self, from: data)
        templatesByOffset = [:]
        rawXmlByOffset = [:]
        for t in arr {
            if let off = t.offset {
                templatesByOffset[off] = t
                if let raw = t.raw {
                    rawXmlByOffset[off] = raw
                }
            }
        }
    }

    // Convenience: try to load the bundled file name from the app bundle path or file-system path
    public func tryLoadBundled(named filename: String = "known_maps_from_original_xdf.json") {
        // First, try bundle
        if let bundleUrl = Bundle.main.url(forResource: filename.replacingOccurrences(of: ".json", with: ""), withExtension: "json") {
            do {
                try load(from: bundleUrl)
                return
            } catch {
                // ignore and try file path
            }
        }
        // Next try app support path (development)
        let devPath = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: devPath.path) {
            do { try load(from: devPath); return } catch {}
        }
    }
}
