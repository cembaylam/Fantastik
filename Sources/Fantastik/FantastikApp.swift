import SwiftUI
import Carbon.HIToolbox

@main
struct FantastikApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppState.shared
    @AppStorage("showMenuBarIcon") private var showMenuBar = true

    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--render-icon"), args.count > i + 1 {
            IconRenderer.writeIconset(to: args[i + 1])
            exit(0)
        }
    }

    var body: some Scene {
        Window("Fantastik", id: "main") {
            MainView().environment(app)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands(app: app) }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarView().environment(app)
        } label: {
            MenuBarLabel().environment(app)
        }
        .menuBarExtraStyle(.window)

        Settings { SettingsView().environment(app) }
    }
}

struct AppCommands: Commands {
    let app: AppState

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Event") { app.quickEntryFocusTick += 1 }.keyboardShortcut("n")
            Button("New Event with Details…") { app.newEvent() }.keyboardShortcut("n", modifiers: [.command, .shift])
            Menu("New from Template") { TemplatesMenu().environment(app) }
            Button("Find Openings…") { app.showOpenings = true }.keyboardShortcut("o", modifiers: [.command, .option])
        }
        CommandMenu("Go") {
            Button("Today") { app.goToday() }.keyboardShortcut("t")
            Button("Previous") { app.step(-1) }.keyboardShortcut("[")
            Button("Next") { app.step(1) }.keyboardShortcut("]")
            Divider()
            ForEach(ViewMode.allCases) { m in
                Button(m.label) { app.viewMode = m }.keyboardShortcut(m.shortcut)
            }
            Divider()
            Button("Refresh") { app.store.reload() }.keyboardShortcut("r")
        }
        CommandGroup(after: .pasteboard) {
            Button("Edit Selected Event") { if let s = app.selected { app.edit(s) } }.keyboardShortcut("e")
            Button("Delete Selected Event") { if let s = app.selected { app.delete(s) } }.keyboardShortcut(.delete, modifiers: .command)
        }
    }
}

// MARK: - App delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var lastIconDay = -1
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        refreshDockIcon()
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--snapshot"), args.count > i + 1 {
            let dir = args[i + 1]
            Task { @MainActor in await Snapshot.run(dir: dir) }
            return
        }
        if CommandLine.arguments.contains("--demo") { MainActor.assumeIsolated { CalendarStore.shared.enableDemo() } }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.refreshDockIcon() }
        GlobalHotKey.register(keyCode: kVK_Space, modifiers: controlKey | optionKey) {
            MainActor.assumeIsolated { QuickEntryController.shared.toggle() }
        }
        MainActor.assumeIsolated { WeatherService.shared.start() }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .openMainWindow, object: nil) }
        return true
    }

    private func refreshDockIcon() {
        let day = Calendar.current.component(.day, from: Date())
        guard day != lastIconDay else { return }
        lastIconDay = day
        NSApp.applicationIconImage = IconRenderer.appIcon(size: 512, date: Date())
    }
}

// MARK: - Global hotkey (Carbon)

enum GlobalHotKey {
    nonisolated(unsafe) static var action: (() -> Void)?

    static func register(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        Self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            GlobalHotKey.action?()
            return noErr
        }, 1, &spec, nil, nil)
        var ref: EventHotKeyRef?
        RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), EventHotKeyID(signature: OSType(0x4641_4E54), id: 1),
                            GetApplicationEventTarget(), 0, &ref)
    }
}

// MARK: - Floating quick-entry panel

private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class QuickEntryController {
    static let shared = QuickEntryController()
    private var panel: KeyPanel?
    private var observer: NSObjectProtocol?

    func toggle() { panel?.isVisible == true ? hide() : show() }

    func hide() { panel?.orderOut(nil) }

    func show() {
        let p = panel ?? makePanel()
        panel = p
        let host = NSHostingView(rootView:
            QuickEntryPanelView(close: { [weak self] in self?.hide() })
                .environment(AppState.shared)
                .frame(width: 660, height: 380, alignment: .top)
                .tint(Theme.accent))
        p.contentView = host
        p.setContentSize(NSSize(width: 660, height: 380))
        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - 330, y: f.minY + f.height * 0.72 - 380 + 60))
        }
        NSApp.activate(ignoringOtherApps: true)
        p.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> KeyPanel {
        let p = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 660, height: 380),
                         styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.isReleasedWhenClosed = false
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        observer = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hide() }
        }
        return p
    }
}
