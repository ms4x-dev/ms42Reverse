//
//  MapDetection.swift
//  ms42Reverse
//
//  Created by Richard on 9/8/2025.
//

import Foundation
import Accelerate

class AtomicCounter {
    private let lock = NSLock()
    private var _value: Int = 0

    func increment(by amount: Int = 1) -> Int {
        lock.lock()
        defer { lock.unlock() }
        _value += amount
        return _value
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return _value
    }
}

enum MapType: String, Codable {
    case unknown, fuel, ignition, boost, maf, injector
}

struct DetectedMap: Identifiable, Codable {
    let id: UUID
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
    var accepted: Bool

    init(name: String, offset: Int, rows: Int, cols: Int, elementSize: Int, values: [UInt16], axisX: [Double]? = nil, axisY: [Double]? = nil, score: Double, type: MapType, accepted: Bool = false) {
        self.id = UUID()
        self.name = name
        self.offset = offset
        self.rows = rows
        self.cols = cols
        self.elementSize = elementSize
        self.values = values
        self.axisX = axisX
        self.axisY = axisY
        self.score = score
        self.type = type
        self.accepted = accepted
    }
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
    ///
    /// This concurrent version:
    /// - guards against tiny/negative images
    /// - ensures chunkSize >= 1
    /// - adds a small overlap to avoid missing tables on chunk boundaries
    func findCandidatesConcurrent(minRows: Int = 3, maxCols: Int = 128) -> [DetectedMap] {
        let elementSize = 2
        // safety guard
        let requiredMin = elementSize * minRows * 2 // minimal bytes to attempt a couple columns
        guard image.size > requiredMin else { return [] }

        let processorCount = max(1, ProcessInfo.processInfo.activeProcessorCount)
        let e = elementSize
        let limit = max(0, image.size - e * minRows) // last offset we can start a minRows table
        guard limit > 0 else { return [] }

        // chunking with overlap: reserve extra so we don't miss tables crossing chunk edges
        let overlap = maxColsOverlap(minRows: minRows, maxCols: maxCols, elementSize: e)
        var chunkSize = limit / processorCount
        if chunkSize < 1 { chunkSize = 1 }

        var results = [DetectedMap]()
        let resultsLock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)
        let sharedCounter = AtomicCounter()

        for i in 0..<processorCount {
            let start = i * chunkSize
            // add overlap except for first chunk; clamp end to limit
            var end = (i == processorCount - 1) ? limit : min(limit, start + chunkSize + overlap)
            // ensure end > start
            if end <= start { end = start + 1 }
            group.enter()
            queue.async {
                var localResults = [DetectedMap]()
                var offset = start
                while offset < end {
                    let totalScanned = sharedCounter.increment()
                    if totalScanned % 10000 == 0 {
                        print("Overall scanning progress: \(totalScanned) / \(limit)")
                    }
                    // Try all possible row/col combos at this offset
                    for cols in 2...maxCols {
                        let tableBytes = cols * minRows * e
                        // if the minimal table for this cols exceeds the image bounds, break
                        if offset + tableBytes > self.image.size { break }
                        // Try to read a table of (minRows x cols) uint16s
                        guard let arr = self.image.readUInt16Array(at: offset, count: cols * minRows) else { continue }
                        // Simple heuristic: check if rows are correlated
                        var correlated = true
                        for r in 0..<(minRows - 1) {
                            let rowA = Array(arr[r * cols..<(r + 1) * cols]).map(Double.init)
                            let rowB = Array(arr[(r + 1) * cols..<(r + 2) * cols]).map(Double.init)
                            let corr = self.pearson(rowA, rowB)
                            if abs(corr) < 0.85 { correlated = false; break }
                        }
                        if correlated {
                            let (ax, ay) = self.findNearbyAxes(offset: offset, rows: minRows, cols: cols)
                            let typ = self.classify(values: arr, axisX: ax, axisY: ay, ghidra: self.ghidraExports, offset: offset)
                            let map = DetectedMap(
                                name: "AutoDetect",
                                offset: offset,
                                rows: minRows,
                                cols: cols,
                                elementSize: e,
                                values: arr,
                                axisX: ax,
                                axisY: ay,
                                score: 1.0,
                                type: typ
                            )
                            localResults.append(map)
                        }
                    }
                    offset += 1
                }
                resultsLock.lock()
                results.append(contentsOf: localResults)
                resultsLock.unlock()
                group.leave()
            }
        }

        group.wait()

        // Deduplicate similar results by (offset,rows,cols)
        let unique = Dictionary(grouping: results, by: { MapKey(offset: $0.offset, rows: $0.rows, cols: $0.cols) })
            .compactMap { (_, maps) in maps.first }
        return unique
    }

    /// Helper to compute a safe overlap size so chunk edges don't lose possible tables.
    private func maxColsOverlap(minRows: Int, maxCols: Int, elementSize: Int) -> Int {
        // Max table bytes for a plausible table at the largest columns - keep small but sufficient.
        // We'll use maxCols * minRows * elementSize as overlap bytes and convert to offsets.
        let bytes = maxCols * minRows * elementSize
        // convert to offset count (bytes -> starting offsets). Each offset advances by 1 byte.
        return min(bytes, 4096) // cap overlap to avoid huge repeats
    }

    private func findNearbyAxes(offset: Int, rows: Int, cols: Int) -> ([Double]?, [Double]?) {
        func tryVec(at off: Int, length: Int) -> [Double]? {
            guard off >= 0, off + length * 2 <= image.size else { return nil }
            guard let arr = image.readUInt16Array(at: off, count: length) else { return nil }
            let d = arr.map { Double($0) }
            let increasing = zip(d, d.dropFirst()).filter { $0.1 >= $0.0 }.count
            let decreasing = zip(d, d.dropFirst()).filter { $0.1 <= $0.0 }.count
            if increasing >= length - 1 || decreasing >= length - 1 {
                return d
            }
            return nil
        }

        let after = offset + rows * cols * 2
        let ax = tryVec(at: after, length: cols) ?? tryVec(at: after + cols * 2, length: cols)
        let before = max(0, offset - rows * 2)
        let ay = tryVec(at: before - max(0, rows * 2), length: rows) ?? tryVec(at: before, length: rows)
        return (ax, ay)
    }

    private func classify(values: [UInt16], axisX: [Double]?, axisY: [Double]?, ghidra: GhidraExports?, offset: Int) -> MapType {
        // Very simple rule-based classifier. Replace with ML later.
        let maxV = values.max() ?? 0
        let meanV = values.map(Double.init).reduce(0, +) / Double(values.count)
        if maxV > 15000 { return .ignition } // large numbers usually ignition timing scaled
        if meanV < 50 && maxV < 3000 { return .fuel }
        if axisX != nil && (axisX!.first ?? 0) > 1000 { return .maf }

        if let gh = ghidra {
            // Check if offset is inside any function's dataRefs
            for f in gh.functions {
                if f.dataRefs.contains(UInt32(offset)) {
                    return .unknown
                }
                if Int(f.startAddress) <= offset && offset <= Int(f.endAddress) {
                    return .unknown
                }
            }
            // Check if offset matches any known label address
            if gh.labels.values.contains(UInt32(offset)) {
                return .unknown
            }
        }
        return .unknown
    }

    // Pearson correlation using Accelerate
    private func pearson(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, a.count > 1 else { return 0.0 }
        var meanA = 0.0, meanB = 0.0
        vDSP_meanvD(a, 1, &meanA, vDSP_Length(a.count))
        vDSP_meanvD(b, 1, &meanB, vDSP_Length(b.count))

        var diffA = [Double](repeating: 0.0, count: a.count)
        var diffB = [Double](repeating: 0.0, count: b.count)

        // diff = arr - mean
        var negOne = -1.0
        var mA = meanA
        var mB = meanB
        vDSP_vsmsaD(a, 1, &negOne, &mA, &diffA, 1, vDSP_Length(a.count))
        vDSP_vsmsaD(b, 1, &negOne, &mB, &diffB, 1, vDSP_Length(b.count))

        var numerator = 0.0
        vDSP_dotprD(diffA, 1, diffB, 1, &numerator, vDSP_Length(a.count))

        var sumSqA = 0.0, sumSqB = 0.0
        vDSP_svesqD(diffA, 1, &sumSqA, vDSP_Length(a.count))
        vDSP_svesqD(diffB, 1, &sumSqB, vDSP_Length(b.count))

        let denominator = sqrt(sumSqA * sumSqB)
        return denominator == 0 ? 0 : numerator / denominator
    }
}
