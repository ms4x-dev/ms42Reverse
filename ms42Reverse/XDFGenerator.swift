//
//  XDFGenerator.swift
//  ms42Reverse
//
//  Created by Richard on 9/8/2025.
//

import Foundation

final class XDFGenerator {
    func makeXDF(maps: [DetectedMap]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<XDF>\n"
        xml += "<Header>\n  <Tool>ms42-reverse</Tool>\n  <Generated>\(ISO8601DateFormatter().string(from: Date()))</Generated>\n</Header>\n"
        xml += "<Maps>\n"
        for m in maps {
            xml += "  <Map name=\"\(escape(m.name))\" offset=\"0x\(String(m.offset, radix: 16))\" rows=\"\(m.rows)\" cols=\"\(m.cols)\" elementSize=\"\(m.elementSize)\">\n"
            if let ax = m.axisX {
                xml += "    <XAxis>\n"
                for v in ax { xml += "      <V>\(v)</V>\n" }
                xml += "    </XAxis>\n"
            }
            if let ay = m.axisY {
                xml += "    <YAxis>\n"
                for v in ay { xml += "      <V>\(v)</V>\n" }
                xml += "    </YAxis>\n"
            }
            xml += "    <Values>\n"
            for r in 0..<m.rows {
                xml += "      <Row>\n"
                for c in 0..<m.cols {
                    let v = m.values[r*m.cols + c]
                    xml += "        <V>\(v)</V>\n"
                }
                xml += "      </Row>\n"
            }
            xml += "    </Values>\n"
            xml += "  </Map>\n"
        }
        xml += "</Maps>\n</XDF>\n"
        return xml
    }

    private func escape(_ s: String) -> String {
        var s = s
        s = s.replacingOccurrences(of: "&", with: "&amp;")
        s = s.replacingOccurrences(of: "<", with: "&lt;")
        s = s.replacingOccurrences(of: ">", with: "&gt;")
        s = s.replacingOccurrences(of: "\"", with: "&quot;")
        return s
    }
}
