//
//  ContentView.swift
//  LU7 Clipboard Manager
//
//  Created by Andrew Peacock on 28/06/2025.
//

import SwiftUI
import AppKit
import ServiceManagement


enum ClipboardContent: Codable, Hashable {
    case text(String)
    case image(Data)
    
    var displayText: String {
        switch self {
        case .text(let str): return str
        case .image(_): return "[Image]"
        }
    }
    
    var nsImage: NSImage? {
        switch self {
        case .text(_): return nil
        case .image(let data): return NSImage(data: data)
        }
    }
}

extension ClipboardContent {
    enum CodingKeys: String, CodingKey { case type, value }
    enum ContentType: String, Codable { case text, image }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ContentType.self, forKey: .type)
        switch type {
        case .text:
            let value = try container.decode(String.self, forKey: .value)
            self = .text(value)
        case .image:
            let value = try container.decode(Data.self, forKey: .value)
            self = .image(value)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let str):
            try container.encode(ContentType.text, forKey: .type)
            try container.encode(str, forKey: .value)
        case .image(let data):
            try container.encode(ContentType.image, forKey: .type)
            try container.encode(data, forKey: .value)
        }
    }
}

struct ClipboardEntry: Codable, Hashable {
    let content: ClipboardContent
    let date: Date
    var pinned: Bool = false
}

class ClipboardManager: ObservableObject {
    @Published var history: [ClipboardEntry] = []
    @Published var filterText: String = ""
    @Published var justCopied = false
    @Published var maxHistoryLength: Int = 50
    @Published var showSettingsSheet = false
    @Published var showClearAllConfirmation = false
    @Published var autoDeleteDays: Int = 0
    @Published var autoDeleteCount: Int = 0

    private let pasteboard = NSPasteboard.general
    private var changeCount: Int
    private var timer: Timer?

    private let historyKey = "clipboardHistory"
    private let maxLengthKey = "maxHistoryLength"
    private let autoDeleteDaysKey = "autoDeleteDays"
    private let autoDeleteCountKey = "autoDeleteCount"

    private var ignoreNextChange = false

    init() {
        self.changeCount = pasteboard.changeCount
        loadHistory()
        loadMaxHistoryLength()
        loadAutoDeleteDays()
        loadAutoDeleteCount()
        pruneExpiredEntries()
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            self.checkClipboard()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    func pruneExpiredEntries() {
        if autoDeleteDays > 0 {
            let cutoff = Calendar.current.date(byAdding: .day, value: -autoDeleteDays, to: Date()) ?? Date()
            history.removeAll { entry in
                entry.pinned == false && entry.date < cutoff
            }
        }
        if autoDeleteCount > 0 {
            var nonPinnedIndices: [Int] = []
            for (idx, entry) in history.enumerated() {
                if entry.pinned == false { nonPinnedIndices.append(idx) }
            }
            let excess = max(0, nonPinnedIndices.count - autoDeleteCount)
            if excess > 0 {
                var removed = 0
                var i = history.count - 1
                while removed < excess && i >= 0 {
                    if history[i].pinned == false {
                        history.remove(at: i)
                        removed += 1
                    }
                    if i == 0 { break }
                    i -= 1
                }
            }
        }
        saveHistory()
    }

    private func checkClipboard() {
        if pasteboard.changeCount != changeCount {
            changeCount = pasteboard.changeCount

            if ignoreNextChange {
                ignoreNextChange = false
                return
            }

            if let items = pasteboard.pasteboardItems, items.first != nil {
                if let str = pasteboard.string(forType: .string) {
                    addToHistory(ClipboardEntry(content: .text(str), date: Date()))
                } else if let image = NSImage(pasteboard: pasteboard) {
                    if let tiff = image.tiffRepresentation,
                       let bitmap = NSBitmapImageRep(data: tiff),
                       let pngData = bitmap.representation(using: .png, properties: [:]) {
                        addToHistory(ClipboardEntry(content: .image(pngData), date: Date()))
                    }
                }
            }
        }
    }

    private func addToHistory(_ newEntry: ClipboardEntry) {
        if let first = history.first, first.pinned == false, first.content == newEntry.content {
            return
        }
        if let idx = history.firstIndex(where: { $0.content == newEntry.content && $0.pinned == false }) {
            var moved = history.remove(at: idx)
            moved = ClipboardEntry(content: moved.content, date: Date(), pinned: false)
            let insertIndex = history.prefix { $0.pinned }.count
            history.insert(moved, at: insertIndex)
        } else {
            let insertIndex = history.prefix { $0.pinned }.count
            history.insert(newEntry, at: insertIndex)
        }
        if history.count > maxHistoryLength {
            var i = history.count - 1
            while history.count > maxHistoryLength && i >= 0 {
                if history[i].pinned == false {
                    history.remove(at: i)
                }
                if i == 0 { break }
                i -= 1
            }
        }
        saveHistory()
        pruneExpiredEntries()
    }

    func copyToClipboard(_ entry: ClipboardEntry) {
        ignoreNextChange = true

        pasteboard.clearContents()
        switch entry.content {
        case .text(let str):
            pasteboard.setString(str, forType: .string)
        case .image(let data):
            if let image = NSImage(data: data) {
                pasteboard.writeObjects([image])
            }
        }

        justCopied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            withAnimation {
                self.justCopied = false
            }
        }
    }

    func saveHistory() {
        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(history)
            UserDefaults.standard.set(data, forKey: historyKey)
            UserDefaults.standard.set(maxHistoryLength, forKey: maxLengthKey)
            UserDefaults.standard.set(autoDeleteDays, forKey: autoDeleteDaysKey)
            UserDefaults.standard.set(autoDeleteCount, forKey: autoDeleteCountKey)
        } catch {
            print("Failed to save clipboard history: \(error)")
        }
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey) else { return }
        do {
            let decoder = JSONDecoder()
            let loaded = try decoder.decode([ClipboardEntry].self, from: data)
            self.history = loaded
        } catch {
            print("Failed to load clipboard history: \(error)")
        }
    }

    private func loadMaxHistoryLength() {
        let stored = UserDefaults.standard.integer(forKey: maxLengthKey)
        if stored >= 10 {
            maxHistoryLength = stored
        }
    }

    private func loadAutoDeleteDays() {
        let stored = UserDefaults.standard.integer(forKey: autoDeleteDaysKey)
        if stored >= 0 {
            autoDeleteDays = stored
        }
    }
    
    private func loadAutoDeleteCount() {
        let stored = UserDefaults.standard.integer(forKey: autoDeleteCountKey)
        if stored >= 0 {
            autoDeleteCount = stored
        }
    }

    var filteredHistory: [ClipboardEntry] {
        let base = history
        let filtered: [ClipboardEntry]
        if filterText.isEmpty {
            filtered = base
        } else {
            filtered = base.filter {
                switch $0.content {
                case .text(let str):
                    return str.localizedCaseInsensitiveContains(filterText)
                case .image(_):
                    return "[Image]".localizedCaseInsensitiveContains(filterText)
                }
            }
        }
        return filtered.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned && !rhs.pinned }
            return lhs.date > rhs.date
        }
    }

    func togglePin(_ entry: ClipboardEntry) {
        if let idx = history.firstIndex(of: entry) {
            history[idx].pinned.toggle()
            saveHistory()
        }
    }

    func deleteEntry(_ entry: ClipboardEntry) {
        if let idx = history.firstIndex(of: entry) {
            history.remove(at: idx)
            saveHistory()
        }
    }

    func clearAll() {
        history.removeAll()
        saveHistory()
    }
}

struct ContentView: View {
    @EnvironmentObject var clipboard: ClipboardManager
    @State private var refreshToggle = false

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd/MM/yy, HH:mm:ss"
        return formatter.string(from: date)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("Search clipboard history...", text: $clipboard.filterText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button {
                        clipboard.showSettingsSheet = true
                    } label: {
                        Image(systemName: "gear")
                            .imageScale(.large)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Settings")

                    Button {
                        clipboard.showClearAllConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .imageScale(.large)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Clear All")
                    .disabled(clipboard.history.isEmpty)
                }
                .padding(.horizontal)

                ScrollViewReader { proxy in
                    List(clipboard.filteredHistory, id: \.self) { entry in
                        HStack(spacing: 10) {
                            if let image = entry.content.nsImage {
                                Image(nsImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 50, height: 50)
                                    .cornerRadius(4)
                            }

                            VStack(alignment: .leading) {
                                Text(entry.content.displayText)
                                    .lineLimit(2)

                                Text(formattedDate(entry.date))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            HStack(spacing: 6) {
                                Button {
                                    clipboard.togglePin(entry)
                                } label: {
                                    Image(systemName: entry.pinned ? "pin.fill" : "pin")
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help(entry.pinned ? "Unpin" : "Pin")

                                Button(role: .destructive) {
                                    clipboard.deleteEntry(entry)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(PlainButtonStyle())
                                .help("Delete")
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            clipboard.copyToClipboard(entry)
                        }
                        .padding(.vertical, 4)
                        .id(entry)
                    }
                    
                    .id(refreshToggle)
                    .onChange(of: clipboard.filteredHistory) { _, newValue in
                        refreshToggle.toggle()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            if let first = newValue.first {
                                proxy.scrollTo(first, anchor: .top)
                            }
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                            if let first = clipboard.filteredHistory.first {
                                proxy.scrollTo(first, anchor: .top)
                            }
                        }
                    }
                }
                .frame(minWidth: 400, minHeight: 550)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(lineWidth: 0)
                )
            }
            .padding()

            if clipboard.justCopied {
                VStack {
                    Spacer()
                    Text("Copied!")
                        .font(.headline)
                        .padding(12)
                        .background(.thinMaterial)
                        .cornerRadius(10)
                        .shadow(radius: 10)
                        .transition(.opacity.combined(with: .scale))
                        .padding(.bottom, 20)
                }
                .animation(.easeInOut, value: clipboard.justCopied)
            }
        }
        .sheet(isPresented: $clipboard.showSettingsSheet) {
            SettingsView()
                .environmentObject(clipboard)
        }
        .alert("Clear All?", isPresented: $clipboard.showClearAllConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear All", role: .destructive) {
                clipboard.clearAll()
            }
        } message: {
            Text("This will remove all clipboard history entries.")
        }
    }
}


class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover = NSPopover()
    var clipboardManager = ClipboardManager()
    var rightClickMenu: NSMenu!
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard Manager")
            button.action = #selector(statusItemLeftClick(_:))
            button.target = self
            
            rightClickMenu = createMenu()
            
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        
        let contentView = ContentView().environmentObject(clipboardManager)
        popover.contentViewController = NSHostingController(rootView: contentView)
        popover.contentSize = NSSize(width: 400, height: 600)
        popover.behavior = .transient
        
        clipboardManager.startMonitoring()
    }
    
    func createMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(
            NSMenuItem(title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        )
        menu.addItem(NSMenuItem.separator())
        menu.addItem(
            NSMenuItem(title: "Exit", action: #selector(terminateApp), keyEquivalent: "q")
        )
        return menu
    }
    
    @objc func statusItemLeftClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent!
        
        if event.type == .rightMouseUp {
            rightClickMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height), in: sender)
        } else {
            togglePopover(sender)
        }
    }
    
    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.becomeKey()
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    @objc func openSettings() {
        if !popover.isShown, let button = statusItem.button {
            togglePopover(button)
        }
        clipboardManager.showSettingsSheet = true
    }
    
    @objc func terminateApp() {
        NSApp.terminate(nil)
    }
}


@main
struct ClipboardManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

