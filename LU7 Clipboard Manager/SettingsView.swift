//
//  SettingsView.swift
//  LU7 Clipboard Manager
//
//  Created by Andrew Peacock on 29/06/2025.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var clipboard: ClipboardManager
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(.title2)
                .bold()
            
            Stepper(value: $clipboard.maxHistoryLength, in: 10...200, step: 10) {
                Text("Max History: \(clipboard.maxHistoryLength)")
            }
            
            Button(role: .destructive) {
                clipboard.history.removeAll()
                clipboard.saveHistory()
                dismiss()
            } label: {
                Label("Clear Clipboard History", systemImage: "trash")
            }
            
            Button("Close") {
                dismiss()
            }
        }
        .padding()
        .frame(width: 300)
        .onDisappear {
            clipboard.saveHistory()
        }
    }
}
