import AppKit
import Combine
import Foundation
import SwiftUI

extension Notification.Name {
    static let netglassOpenMainWindow = Notification.Name("netglass.openMainWindow")
    static let netglassUpdateFrequency = Notification.Name("netglass.updateFrequency")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState: AppState
    let appVM = AppViewModel()
    let monitoring = MonitoringViewModel()
    let capture = PacketCaptureViewModel()
    let operation = OperationViewModel()
    let rateTracker = AppRateTracker()
    private var statusItem: NSStatusItem!
    private var popover: NSPopover?
    private var mainWindowRef: NSWindow?

    private enum Keys {
        static let windowFrame = "netglass.windowFrame"
    }
    private var throughputObservation: AnyCancellable?
    private var flowsObservation: AnyCancellable?

    override init() {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.appState = AppState(databaseDirectory: base)
        super.init()
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // regular app: Dock icon + window. Set before launch completes —
        // LaunchServices re-applies its attributes after didFinishLaunching.
        NSApp.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        appState.liveModel.start()              // sampling runs for app lifetime
        throughputObservation = appState.liveModel.$throughput
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.refreshMeter($0) }
        flowsObservation = appState.liveModel.$flows
            .receive(on: RunLoop.main)
            .sink { [weak self] flows in
                guard let self else { return }
                self.rateTracker.update(apps: RealAgg.apps(from: flows))
            }
        refreshMeter(appState.liveModel.throughput)   // draw immediately, not after first tick
        NotificationCenter.default.addObserver(
            forName: .netglassOpenMainWindow, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showMainWindow() }
        }
        NotificationCenter.default.addObserver(
            forName: .netglassUpdateFrequency, object: nil, queue: .main) { [weak self] note in
            let interval = (note.object as? NSNumber)?.doubleValue
            MainActor.assumeIsolated {
                if let interval {
                    self?.appState.liveModel.interval = interval
                }
            }
        }
        // launching the app opens the full window (menu bar meter alongside)
        showMainWindow()
    }

    /// Dock icon click: always opens the full app window (menu bar click is
    /// the popover path).
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        showMainWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // keep monitoring from the menu bar when the window closes
    }

    // MARK: - Status item (meter rendering is unchanged — existing design)

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover(_:))
        item.button?.imagePosition = .imageOnly
        statusItem = item
    }

    private func refreshMeter(_ throughput: Throughput) {
        guard let button = statusItem?.button else { return }
        // 2pt shorter than the bar: the meter (7pt bars + 8pt numbers) fits
        // comfortably without clipping the top row.
        let height = NSStatusBar.system.thickness - 2
        button.image = StatusMeter.image(
            down: throughput.bytesPerSecondDown,
            up: throughput.bytesPerSecondUp,
            height: height)
        button.setAccessibilityLabel(
            "Network: down \(ByteRate.string(throughput.bytesPerSecondDown)) per second, "
                + "up \(ByteRate.string(throughput.bytesPerSecondUp)) per second")
    }

    // MARK: - Popover (content redesigned; the menu bar item itself is not)

    @objc private func togglePopover(_ sender: Any?) {
        if popover?.isShown == true {
            popover?.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        if popover == nil {
            let controller = NSHostingController(rootView: MenuBarPopoverView()
                .environmentObject(appState)
                .environmentObject(appState.liveModel)
                .environmentObject(appVM)
                .environmentObject(monitoring)
                .environmentObject(capture)
                .environmentObject(rateTracker))
            let newPopover = NSPopover()
            newPopover.behavior = .transient
            newPopover.contentViewController = controller
            popover = newPopover
        }
        guard let button = statusItem.button, let popover else { return }
        // Activate first, then show on the next runloop turn: showing a
        // transient popover while the app is still inactive can drop it.
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async {
            // menu bar click shows ONLY the popover — hide the main window
            // so it never comes forward with it
            if let window = self.mainWindowRef, window.isVisible {
                window.orderOut(nil)
            }
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeFirstResponder(nil)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Main window

    private func showMainWindow() {
        guard let window = mainWindow() else { return }
        window.makeKeyAndOrderFront(nil)
        // don't let the toolbar search field grab focus on open
        window.makeFirstResponder(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func mainWindow() -> NSWindow? {
        if let mainWindowRef { return mainWindowRef }
        let root = NSHostingController(rootView: RootView()
            .environmentObject(appState)
            .environmentObject(appState.liveModel)
            .environmentObject(appVM)
            .environmentObject(monitoring)
            .environmentObject(capture)
            .environmentObject(operation)
            .environmentObject(rateTracker))
        let window = NSWindow(contentViewController: root)
        window.title = "Netglass"
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.contentMinSize = NSSize(width: 1100, height: 560)
        window.isReleasedWhenClosed = false
        // validated manual frame persistence (autosave restored a broken
        // 33pt-high frame once — never trust it blindly)
        if let saved = UserDefaults.standard.string(forKey: Keys.windowFrame) {
            let rect = NSRectFromString(saved)
            if rect.width >= 900, rect.height >= 540,
               NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
                window.setFrame(rect, display: false)
            } else {
                window.setContentSize(NSSize(width: 1180, height: 720))
                window.center()
            }
        } else {
            window.setContentSize(NSSize(width: 1180, height: 720))
            window.center()
        }
        let center = NotificationCenter.default
        center.addObserver(forName: NSWindow.didMoveNotification, object: window,
                           queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                if let window {
                    UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Keys.windowFrame)
                }
            }
        }
        center.addObserver(forName: NSWindow.didResizeNotification, object: window,
                           queue: .main) { note in
            let window = note.object as? NSWindow
            MainActor.assumeIsolated {
                if let window {
                    UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: Keys.windowFrame)
                }
            }
        }
        mainWindowRef = window
        return window
    }
}
