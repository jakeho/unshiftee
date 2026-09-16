import Carbon
import Foundation

final class HotKeyManager {
  enum RegistrationError: LocalizedError {
    case installHandler(OSStatus)
    case registerHotKey(OSStatus)

    var errorDescription: String? {
      switch self {
      case .installHandler(let status):
        return "Could not install the hot-key handler (OSStatus \(status))."
      case .registerHotKey(let status):
        return "Could not register the global hot key (OSStatus \(status))."
      }
    }
  }

  static let displayName = "Control–Option–Command–S"

  private static let signature: OSType = 0x554E_5346  // "UNSF"
  private static let identifier: UInt32 = 1

  private var hotKeyReference: EventHotKeyRef?
  private var eventHandlerReference: EventHandlerRef?
  private var action: (() -> Void)?

  deinit {
    if let hotKeyReference {
      UnregisterEventHotKey(hotKeyReference)
    }
    if let eventHandlerReference {
      RemoveEventHandler(eventHandlerReference)
    }
  }

  func register(action: @escaping () -> Void) throws {
    self.action = action

    var eventType = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard),
      eventKind: OSType(kEventHotKeyPressed)
    )

    let context = Unmanaged.passUnretained(self).toOpaque()
    let handlerStatus = InstallEventHandler(
      GetApplicationEventTarget(),
      { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }

        var hotKeyID = EventHotKeyID()
        let parameterStatus = GetEventParameter(
          event,
          EventParamName(kEventParamDirectObject),
          EventParamType(typeEventHotKeyID),
          nil,
          MemoryLayout<EventHotKeyID>.size,
          nil,
          &hotKeyID
        )

        guard parameterStatus == noErr,
          hotKeyID.signature == HotKeyManager.signature,
          hotKeyID.id == HotKeyManager.identifier
        else {
          return OSStatus(eventNotHandledErr)
        }

        let manager = Unmanaged<HotKeyManager>
          .fromOpaque(context)
          .takeUnretainedValue()

        DispatchQueue.main.async {
          manager.action?()
        }
        return noErr
      },
      1,
      &eventType,
      context,
      &eventHandlerReference
    )

    guard handlerStatus == noErr else {
      throw RegistrationError.installHandler(handlerStatus)
    }

    let hotKeyID = EventHotKeyID(
      signature: Self.signature,
      id: Self.identifier
    )
    let modifiers = UInt32(controlKey | optionKey | cmdKey)
    let registrationStatus = RegisterEventHotKey(
      UInt32(kVK_ANSI_S),
      modifiers,
      hotKeyID,
      GetApplicationEventTarget(),
      0,
      &hotKeyReference
    )

    guard registrationStatus == noErr else {
      throw RegistrationError.registerHotKey(registrationStatus)
    }
  }
}
