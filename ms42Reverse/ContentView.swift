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
            VStack(alignment: .leading, spacing: 8) {
                Button("Open Binary…") { viewModel.openBinary() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Import Ghidra JSON…") { viewModel.importGhidraJSON() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Import Maps JSON…") { viewModel.importMapsJSON() }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
                Button("Scan for Maps") { viewModel.scanForMaps() }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Export Maps JSON") { viewModel.exportMapsAsJSON() }
                    .disabled(viewModel.maps.isEmpty)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Export XDF") { viewModel.exportXdf() }
                    .disabled(viewModel.maps.isEmpty)
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Divider()

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
