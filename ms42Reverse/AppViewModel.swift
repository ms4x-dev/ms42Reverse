//
//  AppViewModel.swift
//  ms42Reverse
//
//  Created by Richard on 9/8/2025.
//

import Foundation
import SwiftUI
import UniformTypeIdentifiers

final class AppViewModel: ObservableObject {
    @Published private(set) var binary: BinaryImage?
    @Published var maps: [DetectedMap] = []
    @Published var selectedMapID: UUID?

    // simple storage for imported function refs if you provide Ghidra JSON
    @Published var ghidraExports: GhidraExports?

    var selectedMap: DetectedMap? {
        maps.first(where: { $0.id == selectedMapID })
    }

    // MARK: UI actions
    func openBinary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.data, UTType.item]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] res in
            guard res == .OK, let url = panel.url else { return }
            do {
                let bin = try BinaryImage(fileURL: url)
                DispatchQueue.main.async {
                    self?.binary = bin
                    self?.maps = []
                }
            } catch {
                self?.alertError(error)
            }
        }
    }
    
    func importMapsJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] res in
            guard res == .OK, let url = panel.url, let self = self else { return }
            do {
                let data = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                let loadedMaps = try decoder.decode([DetectedMap].self, from: data)
                DispatchQueue.main.async {
                    self.maps = loadedMaps
                    self.selectedMapID = self.maps.first?.id
                }
            } catch {
                self.alertError(error)
            }
        }
    }
    
    func importGhidraJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType.json]
        panel.begin { [weak self] res in
            guard res == .OK, let url = panel.url else { return }
            do {
                let exports = try GhidraExports.load(from: url)
                DispatchQueue.main.async {
                    self?.ghidraExports = exports
                }
            } catch {
                self?.alertError(error)
            }
        }
    }

    func openBinFileDialog() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "bin")!]
        panel.allowsMultipleSelection = false
        panel.begin { [weak self] res in
            guard res == .OK, let url = panel.url else { return }
            do {
                let bin = try BinaryImage(fileURL: url)
                DispatchQueue.main.async {
                    self?.binary = bin
                    self?.maps = []
                }
            } catch {
                self?.alertError(error)
            }
        }
    }

    func scanForMaps() {
        guard let bin = binary else { return }
        let detector = MapDetector(image: bin, ghidraExports: ghidraExports)
        Task {
            let found = detector.findCandidatesConcurrent(minRows: 3, maxCols: 128)
            DispatchQueue.main.async {
                self.maps = found.sorted(by: { $0.score > $1.score })
                self.selectedMapID = self.maps.first?.id
            }
        }
    }

    func rename(map: DetectedMap, to newName: String) {
        DispatchQueue.main.async {
            if let idx = self.maps.firstIndex(where: { $0.id == map.id }) {
                self.maps[idx].name = newName
            }
        }
    }

    func markAccepted(map: DetectedMap) {
        DispatchQueue.main.async {
            if let idx = self.maps.firstIndex(where: { $0.id == map.id }) {
                self.maps[idx].accepted.toggle()
            }
        }
    }

    func exportXdf() {
        let accepted = maps.filter { $0.accepted }
        guard !accepted.isEmpty else {
            // export all if none accepted
            export(maps: maps)
            return
        }
        export(maps: accepted)
    }

    func exportMapsAsJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "detected_maps.json"
        panel.begin { [weak self] res in
            guard res == .OK, let url = panel.url, let self = self else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(self.maps)
                try data.write(to: url)
            } catch {
                self.alertError(error)
            }
        }
    }

    private func export(maps: [DetectedMap]) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.xml]
        panel.nameFieldStringValue = "export.xdf"
        panel.begin { res in
            guard res == .OK, let url = panel.url else { return }
            let xml = XDFGenerator().makeXDF(maps: maps)
            do {
                try xml.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.alertError(error)
            }
        }
    }

    private func alertError(_ err: Error) {
        let alert = NSAlert(error: err)
        alert.runModal()
    }
}
