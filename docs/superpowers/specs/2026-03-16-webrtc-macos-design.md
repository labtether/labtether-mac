# Enable WebRTC Remote Desktop on macOS — Design Spec

**Date:** 2026-03-16
**Scope:** Flip WebRTC runtime flag, enable settings UI, add Screen Recording permission handling
**Approach:** Approach A — enable and test. Minimal Swift changes to ungate WebRTC on macOS.

---

## 1. Flip the Runtime Flag

In `Sources/LabTetherAgent/Settings/AgentSettings.swift`, change:

```swift
static let webRTCRuntimeSupported = false
```

to:

```swift
static let webRTCRuntimeSupported = true
```

This makes `effectiveWebRTCEnabled` return the user's `webrtcEnabled` setting (default `true`), and `AgentEnvironmentBuilder` passes `LABTETHER_WEBRTC_ENABLED=true` to the Go agent binary.

**No other changes needed for the flag** — all downstream code already uses `effectiveWebRTCEnabled` correctly.

---

## 2. Enable Settings UI

In `Sources/LabTetherAgent/Views/Settings/SettingsAdvancedTab.swift`, the WebRTC/Remote Desktop section is currently:
- All controls `.disabled(true)` and `.opacity(0.6)`
- Displays a disclaimer: "WebRTC desktop capture is currently available on Linux agents only..."

**Changes:**
- Remove the `.disabled(true)` and `.opacity(0.6)` modifiers from the WebRTC controls
- Remove the "Linux agents only" disclaimer text
- Add a Screen Recording permission status row (see section 3)

---

## 3. Screen Recording Permission

macOS requires the "Screen Recording" TCC permission for any app that captures the screen. The user must grant this manually in System Settings → Privacy & Security → Screen Recording.

### ScreenRecordingPermission utility

A stateless enum (requires `import CoreGraphics` or `import AppKit`):

```swift
import CoreGraphics
import AppKit

enum ScreenRecordingPermission {
    /// Check if Screen Recording permission is currently granted.
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Request Screen Recording permission. Opens System Settings prompt on first call.
    /// Returns true if already granted.
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    /// Open System Settings to the Screen Recording pane.
    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
```

`CGPreflightScreenCaptureAccess()` and `CGRequestScreenCaptureAccess()` are available since macOS 10.15 (we target 13+).

### Settings UI integration

In the WebRTC section of `SettingsAdvancedTab.swift`, add a permission status row below the existing WebRTC controls:

- If granted: green dot + "Screen Recording: Granted"
- If not granted: yellow warning dot + "Screen Recording: Not Granted" + "Open Settings" button that calls `ScreenRecordingPermission.openSettings()`

This row only appears when `webrtcEnabled` is `true` (no point showing permission status if WebRTC is disabled).

### Menu bar integration

In `Sources/LabTetherAgent/Views/MenuBar/MenuBarScreenSharingSection.swift`, add `@ObservedObject var settings: AgentSettings` as a new parameter (the view currently only receives `ScreenSharingMonitor`). Update the call site in `MenuBarView.swift` (line 47) to pass `settings: settings`.

If WebRTC is enabled (`settings.effectiveWebRTCEnabled`) and Screen Recording permission is not granted, show a warning row: "Screen Recording permission required for remote desktop" with an "Open Settings" action.

---

## New Files

| File | Purpose |
|------|---------|
| `Services/ScreenRecordingPermission.swift` | Permission check, request, and open settings |

## Modified Files

| File | Change |
|------|--------|
| `Settings/AgentSettings.swift` | Flip `webRTCRuntimeSupported` to `true` |
| `Views/Settings/SettingsAdvancedTab.swift` | Remove disabled/opacity, remove disclaimer, add permission status |
| `Views/MenuBar/MenuBarScreenSharingSection.swift` | Add `settings` parameter, add permission warning |
| `Views/MenuBar/MenuBarView.swift` | Pass `settings` to `MenuBarScreenSharingSection` |

## Testing

- `ScreenRecordingPermission`: No automated test (requires TCC state which can't be mocked). Manual verification.
- Build verification: `swift build` succeeds with the flag flipped
- Settings UI: WebRTC controls are interactive, permission status shows correctly
- Manual test: Enable WebRTC, start agent, check if Go binary logs desktop capture activity

## What Comes Next (if Go agent doesn't capture on macOS)

If testing reveals the Go agent lacks macOS screen capture, we pivot to either:
- **Approach B**: VNC relay through the hub (leverage macOS built-in Screen Sharing)
- **Approach C**: ScreenCaptureKit helper process feeding frames to Go agent via IPC

This spec intentionally does not design those fallbacks — we test first.
