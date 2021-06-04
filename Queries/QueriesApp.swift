//
//  QueriesApp.swift
//  (cloudkit-samples) queries
//

import SwiftUI

@main
struct QueriesApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(ViewModel())
        }
    }
}
