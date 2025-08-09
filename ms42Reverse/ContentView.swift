//
//  ContentView.swift
//  ms42Reverse
//
//  Created by Richard on 9/8/2025.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading) {
                HStack {
                    Button("Open Binary…") { viewModel.openBinary() }
                    Button("Import Ghidra JSON…") { viewModel.importGhidraJSON() }
                    Button("Scan for Maps") { viewModel.scanForMaps() }
                    Spacer()
                    Button("Export XDF") { viewModel.exportXdf() }.disabled(viewModel.maps.isEmpty)
                }
                .padding(.vertical, 6)

                List(selection: $viewModel.selectedMapID) {
                    ForEach(viewModel.maps) { m in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(m.name).bold()
                                Text(String(format: "Offset 0x%X • %dx%d • score %.2f", m.offset, m.rows, m.cols, m.score))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(m.type.rawValue).font(.caption)
                        }
                        .tag(m.id)
                    }
                }
            }
            .padding()
        } detail: {
            if let map = viewModel.selectedMap {
                MapDetailView(map: map, onRename: { new in viewModel.rename(map: map, to: new) }, onAccept: { viewModel.markAccepted(map: map) })
                    .padding()
            } else {
                Text("Select a detected map to preview").foregroundColor(.secondary)
            }
        }
    }
}
