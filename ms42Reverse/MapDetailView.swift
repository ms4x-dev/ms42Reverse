//
//  MapDetailView.swift
//  ms42Reverse
//
//  Created by Richard on 9/8/2025.
//

import SwiftUI

struct MapDetailView: View {
    @State var map: DetectedMap
    var onRename: (String) -> Void
    var onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("Map name", text: Binding(get: { map.name }, set: { map.name = $0 }))
                    .textFieldStyle(.roundedBorder)
                Button("Rename") { onRename(map.name) }
                Spacer()
                Button(map.accepted ? "Unaccept" : "Accept") { onAccept() }
            }

            HStack {
                MapPreview(rows: map.rows, cols: map.cols, values: map.values.map { Double($0) })
                    .frame(width: 560, height: 360)
                    .border(Color.secondary)
                VStack(alignment: .leading) {
                    Text("Offset: 0x\(String(map.offset, radix:16))")
                    Text("Size: \(map.rows) x \(map.cols) (\(map.elementSize)-byte elements)")
                    Text("Score: \(String(format: "%.2f", map.score))")
                    Text("Type: \(map.type.rawValue)")
                    if let ax = map.axisX {
                        Text("X axis: \(axisSummary(ax))")
                    } else {
                        Text("X axis: not found")
                    }
                    if let ay = map.axisY {
                        Text("Y axis: \(axisSummary(ay))")
                    } else {
                        Text("Y axis: not found")
                    }
                    Spacer()
                }.padding()
            }

            Text("Raw (first 64 values):").font(.caption)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(0..<min(map.values.count, 64), id: \.self) { i in
                        Text(String(map.values[i]))
                            .font(.system(.caption, design: .monospaced))
                            .padding(4)
                            .background(Color(.windowBackgroundColor))
                            .cornerRadius(4)
                    }
                }
            }
            Spacer()
        }
        .onAppear { /* keep local copy up to date if needed */ }
    }

    private func axisSummary(_ axis: [Double]) -> String {
        let minv = axis.min() ?? 0
        let maxv = axis.max() ?? 0
        return String(format: "len %d • %.2f..%.2f", axis.count, minv, maxv)
    }
}
