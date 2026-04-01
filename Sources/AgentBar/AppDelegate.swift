import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private let sessionManager = SessionManager.shared
    private let socketServer = SocketServer.shared
    private let hookInstaller = HookInstaller()
    private let soundManager = SoundManager.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide dock icon — we're a menu bar / notch app
        NSApp.setActivationPolicy(.accessory)

        setupStatusBarItem()
        setupNotchPanel()
        startServices()
    }

    // MARK: - Status Bar

    private func setupStatusBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "cpu", accessibilityDescription: "AgentBar")
            button.action = #selector(togglePanel)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Panel", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Reinstall Hooks", action: #selector(reinstallHooks), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit AgentBar", action: #selector(quitApp), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    // MARK: - Notch Panel

    private func setupNotchPanel() {
        guard let screen = NSScreen.main else { return }

        let notchWidth: CGFloat = 300
        let panelWidth: CGFloat = 380
        let panelHeight: CGFloat = 480

        // Position panel centered on the notch area
        let screenFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let menuBarHeight = screenFrame.height - visibleFrame.height - visibleFrame.origin.y

        let panelX = screenFrame.midX - panelWidth / 2
        let panelY = screenFrame.maxY - panelHeight - 4 // Slight offset below menu bar top

        let contentView = NotchPanelView()
            .environmentObject(sessionManager)

        let hostingView = NSHostingView(rootView: contentView)

        let panel = NSPanel(
            contentRect: NSRect(x: panelX, y: panelY, width: panelWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.contentView = hostingView
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true

        // Allow the panel to accept key events for text input
        panel.becomesKeyOnlyIfNeeded = true

        panel.orderFront(nil)
        self.panel = panel
    }

    // MARK: - Services

    private func startServices() {
        socketServer.start()
        hookInstaller.installAll()

        // Listen for events that need sound
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAgentEvent(_:)),
            name: .agentEventReceived,
            object: nil
        )
    }

    // MARK: - Actions

    @objc private func togglePanel() {
        guard let panel = panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.orderFront(nil)
        }
    }

    @objc private func reinstallHooks() {
        hookInstaller.installAll()
    }

    @objc private func quitApp() {
        socketServer.stop()
        NSApp.terminate(nil)
    }

    @objc private func handleAgentEvent(_ notification: Notification) {
        guard let eventRaw = notification.userInfo?["event"] as? String,
              let event = AgentMessage.EventType(rawValue: eventRaw) else { return }
        switch event {
        case .askUser:
            soundManager.play(.question)
        case .permissionRequest:
            soundManager.play(.permission)
        case .sessionEnd:
            soundManager.play(.taskComplete)
        case .notification:
            soundManager.play(.notification)
        default:
            break
        }
    }
}
