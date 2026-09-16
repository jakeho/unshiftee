import Foundation

enum LoginItemCheckResult {
  case absent
  case removed
  case failed(String)
}

final class LoginItemMonitor {
  typealias ResultHandler = (LoginItemCheckResult) -> Void

  private let queue = DispatchQueue(
    label: "io.jakeho.unshiftee.login-item-monitor",
    qos: .utility
  )
  private var interval: DispatchTimeInterval
  private var resultHandler: ResultHandler?
  private var timer: DispatchSourceTimer?
  private var isChecking = false

  init(interval: DispatchTimeInterval = .seconds(300), resultHandler: ResultHandler? = nil) {
    self.interval = interval
    self.resultHandler = resultHandler
  }

  func setResultHandler(_ resultHandler: @escaping ResultHandler) {
    queue.async { [weak self] in
      self?.resultHandler = resultHandler
    }
  }

  func start() {
    queue.async { [weak self] in
      guard let self, self.timer == nil else { return }
      self.scheduleTimer(deadline: .now())
    }
  }

  func setInterval(_ interval: DispatchTimeInterval) {
    queue.async { [weak self] in
      guard let self else { return }
      self.interval = interval

      guard self.timer != nil else { return }
      self.timer?.cancel()
      self.timer = nil
      self.scheduleTimer(deadline: .now() + interval)
    }
  }

  func stop() {
    queue.async { [weak self] in
      self?.timer?.cancel()
      self?.timer = nil
    }
  }

  func checkNow() {
    queue.async { [weak self] in
      self?.performCheck()
    }
  }

  private func scheduleTimer(deadline: DispatchTime) {
    let timer = DispatchSource.makeTimerSource(queue: queue)
    timer.schedule(deadline: deadline, repeating: interval, leeway: .seconds(5))
    timer.setEventHandler { [weak self] in
      self?.performCheck()
    }
    self.timer = timer
    timer.resume()
  }

  private func performCheck() {
    guard !isChecking else { return }
    isChecking = true
    defer { isChecking = false }

    let script = """
      tell application "System Events"
          if exists login item "Shiftee Desktop" then
              delete login item "Shiftee Desktop"
              return "removed"
          end if
          return "absent"
      end tell
      """

    let process = Process()
    let standardOutput = Pipe()
    let standardError = Pipe()

    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    process.standardOutput = standardOutput
    process.standardError = standardError

    do {
      try process.run()
      process.waitUntilExit()
    } catch {
      resultHandler?(.failed(error.localizedDescription))
      return
    }

    if process.terminationStatus == 0 {
      let output = String(
        data: standardOutput.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      )?.trimmingCharacters(in: .whitespacesAndNewlines)

      resultHandler?(output == "removed" ? .removed : .absent)
      return
    }

    let errorOutput = String(
      data: standardError.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    )?.trimmingCharacters(in: .whitespacesAndNewlines)

    resultHandler?(
      .failed(
        errorOutput?.isEmpty == false
          ? errorOutput! : "osascript exited with status \(process.terminationStatus)"))
  }
}
