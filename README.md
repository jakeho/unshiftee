# Unshiftee

Unshiftee is a tiny native macOS menu-bar app for one deliberately narrow job:

- Remove the visible `Shiftee Desktop` login item on a configurable schedule.
- Terminate the running Shiftee app with `Control–Option–Command–S`.
- Let you check or terminate Shiftee immediately from the menu-bar icon.

The app icon is a tired-but-determined software engineer returning to the laptop while an alarm clock tries to close it. The original generated artwork is preserved at `Resources/AppIcon.png`; the application bundle uses the derived multi-resolution `Resources/AppIcon.icns`.

It has no third-party dependencies and does not use Accessibility or Input Monitoring permissions. macOS will ask for Automation permission because removing another app's login item goes through System Events.

## Build and run

Requirements: macOS 13 or newer and the Xcode command-line tools.

```shell
make app
open dist/Unshiftee.app
```

To install it for your user:

```shell
make install
open "$HOME/Applications/Unshiftee.app"
```

Open the eye-with-a-slash icon in the menu bar and enable **Launch at Login** if you want Unshiftee to start automatically. The setting is opt-in.

The **Check Interval** menu offers 5, 15, 30, or 60 minutes. The default is 5 minutes, and your selection persists between launches. Use **Check Login Item Now** whenever you want an immediate cleanup.

Quit from the menu or press `Command–Q` while Unshiftee's menu is active.

## How it works

Shiftee Desktop currently restores its own `openAtLogin` setting when it launches. macOS does not provide a normal per-app deny list for that API, so Unshiftee is a small cleanup monitor rather than a permanent policy block.

The global shortcut is registered with macOS through the Carbon hot-key API. It should work while another app is frontmost, but a secure system input mode or a sufficiently aggressive screen blocker can still prevent delivery. The menu action remains available as a fallback.

## Privacy

Unshiftee does not use the network, collect data, or read keystrokes. It registers only the single documented shortcut and invokes this equivalent AppleScript operation:

```applescript
tell application "System Events"
    if exists login item "Shiftee Desktop" then
        delete login item "Shiftee Desktop"
    end if
end tell
```
