import AppKit

enum ShifteeController {
  static let bundleIdentifier = "io.shiftee.desktop"

  @discardableResult
  static func forceTerminate() -> Int {
    let applications = NSRunningApplication.runningApplications(
      withBundleIdentifier: bundleIdentifier
    )

    for application in applications {
      application.forceTerminate()
    }

    return applications.count
  }
}
