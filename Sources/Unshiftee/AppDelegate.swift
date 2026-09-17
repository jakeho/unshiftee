import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
  private enum Disclaimer {
    static let acceptanceKey = "acceptedDisclaimerVersion"
    static let currentVersion = 1
    static let title = "Use Unshiftee at Your Own Risk"
    static let summary = """
      Unshiftee removes the Shiftee Desktop login item and can force-terminate its process.

      You must follow applicable law, workplace rules, overtime approval and reporting requirements, security policies, and employment agreements. Use Unshiftee only on devices and accounts you have authority to control.

      You choose whether to use Unshiftee and bear responsibility for that choice and its consequences. The software comes “as is,” without warranties. To the maximum extent permitted by law, the author and contributors disclaim liability for claims, loss, damage, employment action, lost data, or other consequences connected with its use.

      This notice does not provide legal advice.
      """
  }

  private enum CheckInterval: Int, CaseIterable {
    case off = 0
    case fiveMinutes = 300
    case fifteenMinutes = 900
    case thirtyMinutes = 1_800
    case oneHour = 3_600

    static let defaultsKey = "checkIntervalSeconds"

    static var saved: CheckInterval {
      let defaults = UserDefaults.standard
      guard defaults.object(forKey: defaultsKey) != nil else { return .off }

      let seconds = defaults.integer(forKey: defaultsKey)
      return CheckInterval(rawValue: seconds) ?? .off
    }

    var title: String {
      switch self {
      case .off:
        return "Off"
      case .fiveMinutes:
        return "Every 5 Minutes"
      case .fifteenMinutes:
        return "Every 15 Minutes"
      case .thirtyMinutes:
        return "Every 30 Minutes"
      case .oneHour:
        return "Every Hour"
      }
    }

    var seconds: Int? {
      self == .off ? nil : rawValue
    }
  }

  private var checkInterval = CheckInterval.saved
  private lazy var monitor = LoginItemMonitor(
    interval: .seconds(checkInterval.seconds ?? CheckInterval.fiveMinutes.rawValue)
  )
  private let hotKeyManager = HotKeyManager()
  private let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .none
    formatter.timeStyle = .medium
    return formatter
  }()

  private var statusItem: NSStatusItem?
  private var statusMenuItem: NSMenuItem?
  private var launchAtLoginMenuItem: NSMenuItem?
  private var checkIntervalMenuItems: [CheckInterval: NSMenuItem] = [:]

  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    configureMainMenu()
    configureStatusItem()

    guard requireDisclaimerAcceptance() else {
      NSApp.terminate(nil)
      return
    }

    monitor.setResultHandler { [weak self] result in
      DispatchQueue.main.async {
        self?.handleMonitorResult(result)
      }
    }

    do {
      try hotKeyManager.register { [weak self] in
        self?.terminateShiftee()
      }
    } catch {
      setStatus("Hot key unavailable: \(error.localizedDescription)")
    }

    if checkInterval == .off {
      setStatus("Automatic checks are off")
    } else {
      monitor.start()
    }
  }

  func applicationWillTerminate(_ notification: Notification) {
    monitor.stop()
  }

  func menuWillOpen(_ menu: NSMenu) {
    refreshLaunchAtLoginItem()
  }

  private func configureMainMenu() {
    let mainMenu = NSMenu()
    let applicationMenuItem = NSMenuItem()
    let applicationMenu = NSMenu()

    let aboutItem = NSMenuItem(
      title: "About Unshiftee",
      action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
      keyEquivalent: ""
    )
    aboutItem.target = NSApp
    applicationMenu.addItem(aboutItem)
    applicationMenu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit Unshiftee",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = NSApp
    applicationMenu.addItem(quitItem)

    applicationMenuItem.submenu = applicationMenu
    mainMenu.addItem(applicationMenuItem)
    NSApp.mainMenu = mainMenu
  }

  private func configureStatusItem() {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if let button = statusItem.button {
      button.image = NSImage(
        systemSymbolName: "eye.slash",
        accessibilityDescription: "Unshiftee"
      )
      button.toolTip = "Unshiftee"
    }

    let menu = NSMenu()
    menu.delegate = self

    let headingItem = NSMenuItem(title: "Unshiftee", action: nil, keyEquivalent: "")
    headingItem.isEnabled = false
    menu.addItem(headingItem)

    let statusMenuItem = NSMenuItem(title: "Starting…", action: nil, keyEquivalent: "")
    statusMenuItem.isEnabled = false
    menu.addItem(statusMenuItem)
    menu.addItem(.separator())

    let checkItem = NSMenuItem(
      title: "Check Login Item Now",
      action: #selector(checkLoginItemNow),
      keyEquivalent: ""
    )
    checkItem.target = self
    menu.addItem(checkItem)

    let automaticChecksItem = NSMenuItem(
      title: "Automatic Checks",
      action: nil,
      keyEquivalent: ""
    )
    let automaticChecksMenu = NSMenu()
    for interval in CheckInterval.allCases {
      let item = NSMenuItem(
        title: interval.title,
        action: #selector(setCheckInterval(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.tag = interval.rawValue
      automaticChecksMenu.addItem(item)
      checkIntervalMenuItems[interval] = item
    }
    automaticChecksItem.submenu = automaticChecksMenu
    menu.addItem(automaticChecksItem)

    let terminateItem = NSMenuItem(
      title: "Terminate Shiftee Now",
      action: #selector(terminateShiftee),
      keyEquivalent: ""
    )
    terminateItem.target = self
    menu.addItem(terminateItem)

    let shortcutItem = NSMenuItem(
      title: "Shortcut: ⌃⌥⌘S",
      action: nil,
      keyEquivalent: ""
    )
    shortcutItem.isEnabled = false
    menu.addItem(shortcutItem)
    menu.addItem(.separator())

    let launchAtLoginItem = NSMenuItem(
      title: "Launch at Login",
      action: #selector(toggleLaunchAtLogin),
      keyEquivalent: ""
    )
    launchAtLoginItem.target = self
    menu.addItem(launchAtLoginItem)

    let aboutItem = NSMenuItem(
      title: "About Unshiftee",
      action: #selector(showAbout),
      keyEquivalent: ""
    )
    aboutItem.target = self
    menu.addItem(aboutItem)

    let disclaimerItem = NSMenuItem(
      title: "Disclaimer…",
      action: #selector(showDisclaimer),
      keyEquivalent: ""
    )
    disclaimerItem.target = self
    menu.addItem(disclaimerItem)
    menu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: "Quit Unshiftee",
      action: #selector(NSApplication.terminate(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = NSApp
    menu.addItem(quitItem)

    statusItem.menu = menu
    self.statusItem = statusItem
    self.statusMenuItem = statusMenuItem
    self.launchAtLoginMenuItem = launchAtLoginItem
    refreshCheckIntervalItems()
    refreshLaunchAtLoginItem()
  }

  @objc private func checkLoginItemNow() {
    setStatus("Checking…")
    monitor.checkNow()
  }

  @objc private func setCheckInterval(_ sender: NSMenuItem) {
    guard let interval = CheckInterval(rawValue: sender.tag) else { return }

    let automaticChecksWereOff = checkInterval == .off
    checkInterval = interval
    UserDefaults.standard.set(interval.rawValue, forKey: CheckInterval.defaultsKey)

    if let seconds = interval.seconds {
      monitor.setInterval(.seconds(seconds))
      if automaticChecksWereOff {
        monitor.start()
      }
      setStatus("Checking \(interval.title.lowercased())")
    } else {
      monitor.stop()
      setStatus("Automatic checks are off")
    }

    refreshCheckIntervalItems()
  }

  @objc private func terminateShiftee() {
    let count = ShifteeController.forceTerminate()
    if count == 0 {
      setStatus("Shiftee is not running")
    } else {
      setStatus("Terminated Shiftee")
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(500)) { [weak self] in
      self?.monitor.checkNow()
    }
  }

  @objc private func toggleLaunchAtLogin() {
    let service = SMAppService.mainApp

    do {
      switch service.status {
      case .enabled:
        try service.unregister()
      case .requiresApproval:
        SMAppService.openSystemSettingsLoginItems()
      case .notFound, .notRegistered:
        try service.register()
        if service.status == .requiresApproval {
          SMAppService.openSystemSettingsLoginItems()
        }
      @unknown default:
        try service.register()
      }
      refreshLaunchAtLoginItem()
    } catch {
      showError(
        title: "Could Not Update Launch at Login",
        message: error.localizedDescription
      )
    }
  }

  @objc private func showAbout() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.orderFrontStandardAboutPanel(nil)
  }

  @objc private func showDisclaimer() {
    let alert = makeDisclaimerAlert()
    alert.addButton(withTitle: "Close")
    alert.addButton(withTitle: "Open Full Disclaimer")

    if alert.runModal() == .alertSecondButtonReturn {
      openFullDisclaimer()
    }
  }

  private func requireDisclaimerAcceptance() -> Bool {
    let acceptedVersion = UserDefaults.standard.integer(forKey: Disclaimer.acceptanceKey)
    guard acceptedVersion < Disclaimer.currentVersion else { return true }

    while true {
      let alert = makeDisclaimerAlert()
      alert.addButton(withTitle: "I Understand")
      alert.addButton(withTitle: "Quit")
      alert.addButton(withTitle: "Read Full Disclaimer")

      switch alert.runModal() {
      case .alertFirstButtonReturn:
        UserDefaults.standard.set(
          Disclaimer.currentVersion,
          forKey: Disclaimer.acceptanceKey
        )
        return true
      case .alertThirdButtonReturn:
        openFullDisclaimer()
      default:
        return false
      }
    }
  }

  private func makeDisclaimerAlert() -> NSAlert {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = Disclaimer.title
    alert.informativeText = Disclaimer.summary
    return alert
  }

  private func openFullDisclaimer() {
    guard let url = Bundle.main.url(forResource: "DISCLAIMER", withExtension: "md") else {
      showError(
        title: "Disclaimer Not Found",
        message: "The application bundle does not contain DISCLAIMER.md."
      )
      return
    }

    NSWorkspace.shared.open(url)
  }

  private func refreshLaunchAtLoginItem() {
    guard let launchAtLoginMenuItem else { return }

    switch SMAppService.mainApp.status {
    case .enabled:
      launchAtLoginMenuItem.title = "Launch at Login"
      launchAtLoginMenuItem.state = .on
      launchAtLoginMenuItem.isEnabled = true
    case .requiresApproval:
      launchAtLoginMenuItem.title = "Launch at Login (Approval Required)"
      launchAtLoginMenuItem.state = .mixed
      launchAtLoginMenuItem.isEnabled = true
    case .notFound:
      launchAtLoginMenuItem.title = "Launch at Login (App Not Found)"
      launchAtLoginMenuItem.state = .off
      launchAtLoginMenuItem.isEnabled = false
    case .notRegistered:
      launchAtLoginMenuItem.title = "Launch at Login"
      launchAtLoginMenuItem.state = .off
      launchAtLoginMenuItem.isEnabled = true
    @unknown default:
      launchAtLoginMenuItem.title = "Launch at Login"
      launchAtLoginMenuItem.state = .off
      launchAtLoginMenuItem.isEnabled = true
    }
  }

  private func refreshCheckIntervalItems() {
    for (interval, item) in checkIntervalMenuItems {
      item.state = interval == checkInterval ? .on : .off
    }
  }

  private func handleMonitorResult(_ result: LoginItemCheckResult) {
    switch result {
    case .absent:
      setStatus("Shiftee login item is absent")
    case .removed:
      setStatus("Removed Shiftee login item")
    case .failed(let message):
      let firstLine = message.split(separator: "\n").first.map(String.init) ?? message
      setStatus("Check failed: \(firstLine)")
    }
  }

  private func setStatus(_ message: String) {
    let timestamp = timeFormatter.string(from: Date())
    statusMenuItem?.title = "\(message) · \(timestamp)"
  }

  private func showError(title: String, message: String) {
    NSApp.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.alertStyle = .warning
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: "OK")
    alert.runModal()
  }
}
