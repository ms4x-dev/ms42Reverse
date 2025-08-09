//
//  MapPreview.swift
//  ms42Reverse
//
//  Created by Richard on 9/8/2025.
//

import SwiftUI

struct MapPreview: View {
    let rows: Int
    let cols: Int
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let cw = geo.size.width / CGFloat(cols)
            let ch = geo.size.height / CGFloat(rows)
            VStack(spacing: 0) {
                ForEach(0..<rows, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<cols, id: \.self) { c in
                            let v = values[r*cols + c]
                            Rectangle()
                                .fill(color(for: v))
                                .frame(width: cw, height: ch)
                        }
                    }
                }
            }
        }
    }

    private func color(for value: Double) -> Color {
        // simple normalization: map values to hue 0.6->0
        let maxVal = values.max() ?? 1
        let minVal = values.min() ?? 0
        let norm = maxVal - minVal == 0 ? 0.0 : (value - minVal) / (maxVal - minVal)
        return Color(hue: 0.65 - 0.65 * min(max(norm, 0), 1), saturation: 0.8, brightness: 0.9)
    }
}
