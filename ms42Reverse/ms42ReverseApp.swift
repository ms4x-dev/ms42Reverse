//
//  ms42ReverseApp.swift
//  ms42Reverse
//
//  Created by Richard on 9/8/2025.
//

import SwiftUI

@main
struct MS42ReverseApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: AppViewModel())
                .frame(minWidth: 1000, minHeight: 700)
        }
    }
}
