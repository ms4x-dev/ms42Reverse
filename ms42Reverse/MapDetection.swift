//
//  MapDetection.swift
//  ms42Reverse
//
//  Created by Richard on 9/8/2025.
//

import Foundation

enum MapType: String, Codable {
    case unknown, fuel, ignition, boost, maf, injector
}

struct DetectedMap: Identifiable {
    let id = UUID()
    var name: String
    let offset: Int
    let rows: Int
    let cols: Int
    let elementSize: Int
    var values: [UInt16] // flattened row-major
    var axisX: [Double]?
    var axisY: [Double]?
    var score: Double
    var type: MapType
    var accepted: Bool = false
}

struct MapKey: Hashable {
    let offset: Int
    let rows: Int
    let cols: Int
}

// Primary detection class
final class MapDetector {
    let image: BinaryImage
    let ghidraExports: GhidraExports?

    init(image: BinaryImage, ghidraExports: GhidraExports? = nil) {
        self.image = image
        self.ghidraExports = ghidraExports
    }

    /// Brute-force search for 2D uint16 arrays where consecutive rows are correlated.
    func findCandidates(minRows: Int = 3, maxCols: Int = 128) -> [DetectedMap] {
        var results: [DetectedMap] = []
        let e = 2
        let limit = image.size - e * minRows
        var offset = 0
        while offset < limit {
            if offset % 1000 == 0 {
                print("Scanning offset \(offset) / \(limit)")
            }
            if let v = image.readUInt16LE(at: offset), v == 0 && (offset % 2 == 0) {
                var zeroRun = 2
                while offset + zeroRun < limit,
                      let val = image.readUInt16LE(at: offset + zeroRun),
                      val == 0 {
                    zeroRun += 2
                }
                print("Skipping zero run of length \(zeroRun) at offset \(offset)")
                offset += zeroRun
                continue
            }
            for cols in 2...maxCols {
                let required = cols * minRows * e
                if offset + required > image.size { break }
                guard let raw = image.readUInt16Array(at: offset, count: cols * minRows) else { continue }
                let row0 = Array(raw[0..<cols]).map { Double($0) }
                let row1 = Array(raw[cols..<(2*cols)]).map { Double($0) }
                let corr = pearson(row0, row1)
                if corr > 0.86 {
                    var rows = minRows
                    while offset + cols * (rows + 1) * e <= image.size {
                        guard let rawExtended = image.readUInt16Array(at: offset, count: cols * (rows + 1)) else { break }
                        guard let nextRow = image.readUInt16Array(at: offset + cols * rows * e, count: cols) else { break }
                        let next = nextRow.map { Double($0) }
                        let prevStart = (rows - 1) * cols
                        let prevEnd = rows * cols
                        let corrToPrev = pearson(Array(rawExtended[prevStart..<prevEnd]).map(Double.init), next)
                        if corrToPrev > 0.7 { rows += 1 } else { break }
                    }
                    let totalCount = cols * rows
                    guard let full = image.readUInt16Array(at: offset, count: totalCount) else { continue }
                    let axes = findNearbyAxes(offset: offset, rows: rows, cols: cols)
                    let (ax, ay) = axes
                    var score = corr + Double(rows)/50.0 + Double(cols)/200.0
                    if ax != nil { score += 0.6 }
                    if ay != nil { score += 0.6 }
                    let type = classify(values: full, axisX: ax, axisY: ay, ghidra: ghidraExports, offset: offset)
                    let nameGuess = "\(type.rawValue.capitalized)Map_0x\(String(offset, radix:16))"
                    let map = DetectedMap(name: nameGuess, offset: offset, rows: rows, cols: cols, elementSize: e, values: full, axisX: ax, axisY: ay, score: score, type: type)
                    results.append(map)
                }
            }
            offset += 1
        }
        let unique = Dictionary(grouping: results, by: { MapKey(offset: $0.offset, rows: $0.rows, cols: $0.cols) })
            .compactMap { (_, maps) in maps.first }
        return unique
    }

    private func findNearbyAxes(offset: Int, rows: Int, cols: Int) -> ([Double]?, [Double]?) {
        // Heuristic: X axis often stored right after table, Y axis before table, or in adjacent block.
        // Test a few candidate offsets and see if we can read monotonic uint16 vectors of length cols/rows.
        func tryVec(at off: Int, length: Int) -> [Double]? {
            guard off >= 0, off + length*2 <= image.size else { return nil }
            guard let arr = image.readUInt16Array(at: off, count: length) else { return nil }
            let d = arr.map { Double($0) }
            // monotonicity check
            let increasing = zip(d, d.dropFirst()).filter { $0.1 >= $0.0 }.count
            let decreasing = zip(d, d.dropFirst()).filter { $0.1 <= $0.0 }.count
            if increasing >= length - 1 || decreasing >= length - 1 {
                return d
            }
            return nil
        }

        // try right after the table for X axis
        let after = offset + rows * cols * 2
        let ax = tryVec(at: after, length: cols) ?? tryVec(at: after + cols*2, length: cols)
        // try before table for Y axis
        let before = max(0, offset - rows*2)
        let ay = tryVec(at: before - max(0, rows*2), length: rows) ?? tryVec(at: before, length: rows)
        return (ax, ay)
    }

    private func classify(values: [UInt16], axisX: [Double]?, axisY: [Double]?, ghidra: GhidraExports?, offset: Int) -> MapType {
        // Very simple rule-based classifier. Replace with ML later.
        let maxV = values.max() ?? 0
        let meanV = values.map(Double.init).reduce(0,+)/Double(values.count)
        if maxV > 15000 { return .ignition } // large numbers usually ignition timing scaled
        if meanV < 50 && maxV < 3000 { return .fuel }
        if axisX != nil && axisX!.first ?? 0 > 1000 { return .maf }
        // look for function crossrefs (if ghidra available)
        if let gh = ghidra {
            for f in gh.functions {
                // if the map address falls in a function's data refs or proximity, mark unknown for now
                // This is a placeholder — real logic should use dataRefs from Ghidra.
                if Int(f.startAddress) <= offset && offset <= Int(f.endAddress) { return .unknown }
            }
        }
        return .unknown
    }

    // Pearson correlation
    private func pearson(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, a.count > 1 else { return 0.0 }
        let meanA = a.reduce(0,+)/Double(a.count)
        let meanB = b.reduce(0,+)/Double(b.count)
        var num = 0.0, denA = 0.0, denB = 0.0
        for i in 0..<a.count {
            let da = a[i] - meanA, db = b[i] - meanB
            num += da*db
            denA += da*da
            denB += db*db
        }
        let den = sqrt(denA*denB)
        return den == 0 ? 0 : num/den
    }
}
