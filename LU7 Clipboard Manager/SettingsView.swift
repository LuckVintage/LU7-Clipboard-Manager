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
            
            GroupBox("Auto Delete by Age:") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding(
                        get: { clipboard.autoDeleteDays > 0 },
                        set: { isOn in
                            if !isOn { clipboard.autoDeleteDays = 0 } else if clipboard.autoDeleteDays == 0 { clipboard.autoDeleteDays = 7 }
                            clipboard.saveHistory()
                            clipboard.pruneExpiredEntries()
                        }
                    )) {
                        Text("Enable auto delete by age")
                    }
                    HStack {
                        Text("Keep items for:")
                        Stepper(value: Binding(
                            get: { max(clipboard.autoDeleteDays, 0) },
                            set: { newVal in
                                clipboard.autoDeleteDays = max(newVal, 0)
                                clipboard.saveHistory()
                                clipboard.pruneExpiredEntries()
                            }
                        ), in: 0...365) {
                            Text(clipboard.autoDeleteDays == 0 ? "Disabled" : "\(clipboard.autoDeleteDays) day(s)")
                        }
                        .disabled(clipboard.autoDeleteDays == 0)
                    }
                    Text("Pinned items are never auto-deleted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            GroupBox("Auto Delete by Count:") {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: Binding<Bool>(
                        get: {
                            let manager = clipboard
                            return manager.autoDeleteCount > 0
                        },
                        set: { isOn in
                            let manager = clipboard
                            if !isOn {
                                manager.autoDeleteCount = 0
                            } else if manager.autoDeleteCount == 0 {
                                manager.autoDeleteCount = 100
                            }
                            manager.saveHistory()
                            manager.pruneExpiredEntries()
                        }
                    )) {
                        Text("Enable auto delete by count")
                    }
                    HStack {
                        Text("Keep max items:")
                        Stepper(value: Binding<Int>(
                            get: {
                                let manager = clipboard
                                return max(manager.autoDeleteCount, 0)
                            },
                            set: { newVal in
                                let manager = clipboard
                                manager.autoDeleteCount = max(newVal, 0)
                                manager.saveHistory()
                                manager.pruneExpiredEntries()
                            }
                        ), in: 0...1000) {
                            let manager = clipboard
                            Text(manager.autoDeleteCount == 0 ? "Disabled" : "\(manager.autoDeleteCount) item(s)")
                        }
                        .disabled({ let manager = clipboard; return manager.autoDeleteCount == 0 }())
                    }
                    Text("Pinned items are never auto-deleted.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
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

