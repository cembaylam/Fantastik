import SwiftUI
import AppKit

/// `Fantastik --snapshot <dir>` renders key screens offscreen (demo data) for visual review.
@MainActor
enum Snapshot {
    static func run(dir: String) async {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let app = AppState.shared
        app.store.enableDemo()
        app.now = Date().settingTime(hour: 10, minute: 30)
        app.selectedDate = app.now

        func shell<V: View>(_ mode: ViewMode, @ViewBuilder _ content: () -> V) -> some View {
            HStack(spacing: 0) {
                SidebarView().frame(width: 300).background(.regularMaterial)
                Divider()
                content().frame(maxWidth: .infinity)
            }
            .environment(app).tint(Theme.accent)
        }

        app.viewMode = .week
        await render(shell(.week) { TimelineCalendarView(days: (0..<7).map { app.selectedDate.startOfWeek.adding(days: $0) }) },
                     size: CGSize(width: 1280, height: 820), name: "week", dir: dir)
        await render(shell(.day) { TimelineCalendarView(days: [app.selectedDate.startOfDay]) }, size: CGSize(width: 1280, height: 820), name: "day", dir: dir)
        await render(shell(.month) { MonthView() }, size: CGSize(width: 1280, height: 820), name: "month", dir: dir)
        await render(shell(.year) { YearView() }, size: CGSize(width: 1280, height: 820), name: "year", dir: dir)
        await render(shell(.list) { ListCalendarView() }, size: CGSize(width: 1280, height: 820), name: "list", dir: dir)
        await render(MenuBarView().environment(app), size: CGSize(width: 350, height: 640), name: "menubar", dir: dir)
        if let e = app.events(on: Date()).first(where: { $0.meeting != nil }) {
            await render(EventDetailView(item: e).environment(app).background(.background), size: CGSize(width: 340, height: 560), name: "detail", dir: dir)
        }
        var d = app.defaultDraft(); d.title = "Design sync"
        await render(EventEditorView(request: EditorRequest(existing: nil, draft: d)).environment(app).background(.background),
                     size: CGSize(width: 480, height: 640), name: "editor", dir: dir)
        await render(QuickEntryPanelView(close: {}, initialText: "Lunch with Sam tomorrow at noon at Café Lomi /Personal alert 15 minutes before")
                        .environment(app).frame(width: 660, height: 300, alignment: .top),
                     size: CGSize(width: 660, height: 300), name: "quick", dir: dir)
        exit(0)
    }

    private static func render<V: View>(_ view: V, size: CGSize, name: String, dir: String) async {
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(Color(nsColor: .windowBackgroundColor)))
        let win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled], backing: .buffered, defer: false)
        win.contentView = host
        host.frame = NSRect(origin: .zero, size: size)
        win.layoutIfNeeded()
        try? await Task.sleep(for: .milliseconds(900))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        if let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(name).png"))
        }
    }
}
