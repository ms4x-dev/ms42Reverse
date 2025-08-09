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
    func findCandidatesConcurrent(minRows: Int = 3, maxCols: Int = 128) -> [DetectedMap] {
        let processorCount = ProcessInfo.processInfo.activeProcessorCount
        let e = 2
        let limit = image.size - e * minRows
        let chunkSize = limit / processorCount
        var results = [DetectedMap]()
        let resultsLock = NSLock()
        let group = DispatchGroup()
        let queue = DispatchQueue.global(qos: .userInitiated)

        let sharedCounter = AtomicCounter()

        for i in 0..<processorCount {
            let start = i * chunkSize
            let end = (i == processorCount - 1) ? limit : (start + chunkSize)
            group.enter()
            queue.async {
                var localResults = [DetectedMap]()
                var offset = start
                while offset < end {
                    let totalScanned = sharedCounter.increment()
                    if totalScanned % 10000 == 0 {
                        print("Overall scanning progress: \(totalScanned) / \(limit)")
                    }
                    // Example detection logic:
                    // Try all possible row/col combos at this offset
                    for cols in 2...maxCols {
                        let tableBytes = cols * minRows * 2
                        if offset + tableBytes > end { break }
                        // Try to read a table of (minRows x cols) uint16s
                        guard let arr = self.image.readUInt16Array(at: offset, count: cols * minRows) else { continue }
                        // Simple heuristic: check if rows are correlated
                        var correlated = true
                        for r in 0..<(minRows-1) {
                            let rowA = Array(arr[r*cols..<(r+1)*cols]).map(Double.init)
                            let rowB = Array(arr[(r+1)*cols..<(r+2)*cols]).map(Double.init)
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
                                elementSize: 2,
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
        // Improved Ghidra crossref/label logic
        if let gh = ghidra {
            // Check if offset is inside any function's dataRefs (if present)
            for f in gh.functions {
                if let dataRefs = f.dataRefs, dataRefs.contains(UInt32(offset)) {
                    return .unknown
                }
                if Int(f.startAddress) <= offset && offset <= Int(f.endAddress) {
                    return .unknown
                }
            }
            // Check if offset matches any known label address for better naming
            if let labels = gh.labels {
                if labels.values.contains(UInt32(offset)) {
                    return .unknown
                }
            }
        }
        return .unknown
    }

    // Pearson correlation
    private func pearson(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, a.count > 1 else { return 0.0 }
        var meanA = 0.0, meanB = 0.0
        vDSP_meanvD(a, 1, &meanA, vDSP_Length(a.count))
        vDSP_meanvD(b, 1, &meanB, vDSP_Length(b.count))

        var diffA = [Double](repeating: 0.0, count: a.count)
        var diffB = [Double](repeating: 0.0, count: b.count)

        vDSP_vsmsaD(a, 1, [-1.0], [meanA], &diffA, 1, vDSP_Length(a.count))
        vDSP_vsmsaD(b, 1, [-1.0], [meanB], &diffB, 1, vDSP_Length(b.count))

        var numerator = 0.0
        vDSP_dotprD(diffA, 1, diffB, 1, &numerator, vDSP_Length(a.count))

        var sumSqA = 0.0, sumSqB = 0.0
        vDSP_svesqD(diffA, 1, &sumSqA, vDSP_Length(a.count))
        vDSP_svesqD(diffB, 1, &sumSqB, vDSP_Length(b.count))

        let denominator = sqrt(sumSqA * sumSqB)
        return denominator == 0 ? 0 : numerator / denominator
    }
}
