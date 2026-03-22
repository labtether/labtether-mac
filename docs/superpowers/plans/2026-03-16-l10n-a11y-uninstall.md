# Localization, Accessibility & Uninstall Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add i18n infrastructure with English/Spanish strings, VoiceOver accessibility labels on all custom components, and a clean uninstall/reset feature.

**Architecture:** Three independent features. Uninstall is a new `UninstallManager` service + menu bar button. Accessibility adds modifiers to existing components. Localization creates `L10n` enum + `.strings` files and updates all view files to use them. Implementation order: Uninstall → Accessibility → Localization (localization last because it touches the same files accessibility modifies).

**Tech Stack:** Swift 5.9+, SwiftUI, macOS 13+, Foundation (NSLocalizedString), XCTest

**Spec:** `docs/superpowers/specs/2026-03-16-l10n-a11y-uninstall-design.md`

---

## Chunk 1: Uninstall & Accessibility

### Task 1: Create UninstallManager and wire into menu bar

**Files:**
- Create: `Sources/LabTetherAgent/Services/UninstallManager.swift`
- Modify: `Sources/LabTetherAgent/Views/MenuBar/MenuBarFooterSection.swift`

- [ ] **Step 1: Create UninstallManager**

Create `Sources/LabTetherAgent/Services/UninstallManager.swift`:

```swift
import AppKit

/// Performs a clean uninstall: stops agent, removes config, credentials, and history, then quits.
enum UninstallManager {
    @MainActor
    static func performUninstall(
        agentProcess: AgentProcess,
        settings: AgentSettings
    ) {
        // Capture path before cleanup (accessing appSupportDirectory creates it as side effect)
        let appSupportURL = settings.appSupportDirectory
        // 1. Stop agent
        agentProcess.forceKill()
        // 2. Remove login item
        _ = LoginItemManager.setEnabled(false)
        // 3. Delete Keychain entries
        _ = KeychainSecretStore.deleteStatus(account: "apiToken")
        _ = KeychainSecretStore.deleteStatus(account: "enrollmentToken")
        _ = KeychainSecretStore.deleteStatus(account: "webrtcTurnPass")
        // 4. Remove Application Support directory (best-effort)
        try? FileManager.default.removeItem(at: appSupportURL)
        // 5. Clear UserDefaults
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleID)
        }
        // 6. Quit
        NSApp.terminate(nil)
    }
}
```

- [ ] **Step 2: Add uninstall button to MenuBarFooterSection**

In `Sources/LabTetherAgent/Views/MenuBar/MenuBarFooterSection.swift`, add a `@State private var showUninstallConfirmation = false` property.

Add a "Reset & Uninstall" button in the utility links row (the `HStack` that already contains "About" and "Setup Wizard"). Add it after "Setup Wizard":

```swift
Button("Reset & Uninstall...") {
    showUninstallConfirmation = true
}
.buttonStyle(.plain)
.font(LT.inter(11))
.foregroundColor(LT.bad)
```

Add a `.alert` modifier to the view:

```swift
.alert("Uninstall LabTether Agent?", isPresented: $showUninstallConfirmation) {
    Button("Uninstall & Quit", role: .destructive) {
        UninstallManager.performUninstall(
            agentProcess: agentProcess,
            settings: settings
        )
    }
    Button("Cancel", role: .cancel) {}
} message: {
    Text("This will remove all configuration, credentials, and history. The app will quit.")
}
```

- [ ] **Step 3: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 4: Commit**

```bash
git add Sources/LabTetherAgent/Services/UninstallManager.swift \
  Sources/LabTetherAgent/Views/MenuBar/MenuBarFooterSection.swift
git commit -m "feat: add UninstallManager with clean reset and menu bar trigger"
```

---

### Task 2: Add accessibility to custom components

**Files:**
- Modify: `Sources/LabTetherAgent/Components/HealthOrb.swift`
- Modify: `Sources/LabTetherAgent/Components/ProgressRing.swift`
- Modify: `Sources/LabTetherAgent/Components/Sparkline.swift`
- Modify: `Sources/LabTetherAgent/Components/SpinnerArc.swift`
- Modify: `Sources/LabTetherAgent/Components/AnimatedCheck.swift`
- Modify: `Sources/LabTetherAgent/Components/Controls.swift`
- Modify: `Sources/LabTetherAgent/Components/MetricBar.swift`
- Modify: `Sources/LabTetherAgent/Presentation/MenuBarStatusIcon.swift`

- [ ] **Step 1: Add accessibility to HealthOrb**

Read `Sources/LabTetherAgent/Components/HealthOrb.swift`. The view takes `color`, `size`, `animated`, `breatheDuration`. It doesn't have semantic context about what the color means, so add an `accessibilityLabel` parameter:

```swift
var accessibilityDescription: String = "Connection health"
```

At the end of the body's outermost view, add:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel(accessibilityDescription)
.accessibilityAddTraits(.updatesFrequently)
```

- [ ] **Step 2: Add accessibility to ProgressRing**

Read `Sources/LabTetherAgent/Components/ProgressRing.swift`. It has `value: Double` and displays percent text. Add:

```swift
var accessibilityName: String = "Progress"
```

At the end of body:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel(accessibilityName)
.accessibilityValue("\(Int(value * 100)) percent")
.accessibilityAddTraits(.updatesFrequently)
```

- [ ] **Step 3: Add accessibility to Sparkline**

Read `Sources/LabTetherAgent/Components/Sparkline.swift`. It's decorative when paired with a progress ring. Add:

```swift
.accessibilityHidden(true)
```

to the outermost view in body.

- [ ] **Step 4: Add accessibility to SpinnerArc and AnimatedCheck**

For `SpinnerArc.swift` — add to body:
```swift
.accessibilityLabel("Loading")
.accessibilityAddTraits(.isImage)
```

For `AnimatedCheck.swift` — add to body:
```swift
.accessibilityLabel("Success")
.accessibilityAddTraits(.isImage)
```

- [ ] **Step 5: Add accessibility to LTMenuRow and MetricBar in Controls.swift**

Read `Sources/LabTetherAgent/Components/Controls.swift`.

For `LTMenuRow` (around line 68): The row already has a `label` text. Add after the outer `Button`:
```swift
.accessibilityLabel(label)
```

For `LTSectionHeader`, `LTSeparator`, and `LTCopyRow`: These already have text content that VoiceOver can read, so no changes needed.

- [ ] **Step 6: Add accessibility identifier to LTMenuBarStatusIcon**

Read `Sources/LabTetherAgent/Presentation/MenuBarStatusIcon.swift`. The view already has accessibility support — `MenuBarIconKind` has an `accessibilityLabel` property and the body already applies `.accessibilityLabel(kind.accessibilityLabel)`. Do NOT add a second `.accessibilityLabel` or a new computed property.

Only add the identifier for UI testing:

```swift
.accessibilityIdentifier("menubar-status-icon")
```

- [ ] **Step 6b: Add accessibility to LTMetricBar**

Read `Sources/LabTetherAgent/Components/MetricBar.swift`. Add an `accessibilityName: String = "Metric"` parameter and apply:

```swift
.accessibilityElement(children: .ignore)
.accessibilityLabel(accessibilityName)
.accessibilityValue("\(Int(value * 100)) percent")
.accessibilityAddTraits(.updatesFrequently)
```

Update call sites to pass descriptive labels (e.g., "CPU usage", "Memory usage", "Disk usage").

- [ ] **Step 7: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 8: Commit**

```bash
git add Sources/LabTetherAgent/Components/HealthOrb.swift \
  Sources/LabTetherAgent/Components/ProgressRing.swift \
  Sources/LabTetherAgent/Components/Sparkline.swift \
  Sources/LabTetherAgent/Components/SpinnerArc.swift \
  Sources/LabTetherAgent/Components/AnimatedCheck.swift \
  Sources/LabTetherAgent/Components/Controls.swift \
  Sources/LabTetherAgent/Components/MetricBar.swift \
  Sources/LabTetherAgent/Presentation/MenuBarStatusIcon.swift
git commit -m "feat: add VoiceOver accessibility labels to all custom components"
```

---

### Task 3: Add accessibility to view files

**Files:**
- Modify: `Sources/LabTetherAgent/Views/Settings/SettingsConnectionTab.swift`
- Modify: `Sources/LabTetherAgent/Views/Onboarding/OnboardingWelcomeStep.swift`
- Modify: `Sources/LabTetherAgent/Views/Onboarding/OnboardingAuthStep.swift`
- Modify: `Sources/LabTetherAgent/Views/Onboarding/OnboardingIdentityStep.swift`
- Modify: `Sources/LabTetherAgent/Views/About/AboutView.swift`
- Modify: `Sources/LabTetherAgent/Views/PopOut/PopOutSessionHistorySection.swift`
- Modify: `Sources/LabTetherAgent/Views/PopOut/PopOutBandwidthSection.swift`

- [ ] **Step 1: Add accessibility to SettingsConnectionTab**

Read the file. Add to the Hub URL text field:
```swift
.accessibilityIdentifier("settings-hub-url")
```

Add to the Test Connection button:
```swift
.accessibilityIdentifier("settings-test-connection")
.accessibilityHint("Tests connectivity to the hub server")
```

Add to the token eye toggle button:
```swift
.accessibilityLabel(showToken ? "Hide token" : "Show token")
```
(Check the variable name for the show/hide state — it may be `showAPIToken` or similar.)

- [ ] **Step 2: Add accessibility to onboarding views**

In `OnboardingWelcomeStep.swift`, add to the paste button:
```swift
.accessibilityLabel("Paste hub URL from clipboard")
```

In `OnboardingAuthStep.swift`, add to the eye toggle:
```swift
.accessibilityLabel(showToken ? "Hide token" : "Show token")
```

In `OnboardingIdentityStep.swift` or `OnboardingView.swift`, add to the Finish button:
```swift
.accessibilityIdentifier("onboarding-finish")
```

Add to the Next button:
```swift
.accessibilityIdentifier("onboarding-next")
```

- [ ] **Step 3: Add accessibility to AboutView**

Read the file. Add to the version text:
```swift
.accessibilityIdentifier("about-version")
```

Add to the copy fingerprint button:
```swift
.accessibilityLabel("Copy device fingerprint")
```

- [ ] **Step 4: Add accessibility to pop-out sections**

In `PopOutSessionHistorySection.swift`, add to the outer container:
```swift
.accessibilityIdentifier("popout-session-history")
```

Add to the clear history button:
```swift
.accessibilityHint("Removes all recorded session events")
```

In `PopOutBandwidthSection.swift`, add to the outer container:
```swift
.accessibilityIdentifier("popout-bandwidth")
```

- [ ] **Step 5: Build to verify**

Run: `swift build 2>&1 | tail -10`
Expected: Build succeeds

- [ ] **Step 6: Commit**

```bash
git add Sources/LabTetherAgent/Views/Settings/SettingsConnectionTab.swift \
  Sources/LabTetherAgent/Views/Onboarding/OnboardingWelcomeStep.swift \
  Sources/LabTetherAgent/Views/Onboarding/OnboardingAuthStep.swift \
  Sources/LabTetherAgent/Views/Onboarding/OnboardingIdentityStep.swift \
  Sources/LabTetherAgent/Views/About/AboutView.swift \
  Sources/LabTetherAgent/Views/PopOut/PopOutSessionHistorySection.swift \
  Sources/LabTetherAgent/Views/PopOut/PopOutBandwidthSection.swift
git commit -m "feat: add accessibility identifiers and hints to views"
```

---

## Chunk 2: Localization

### Task 4: Create L10n infrastructure and string files

**Files:**
- Create: `Sources/LabTetherAgent/Localization/L10n.swift`
- Create: `Sources/LabTetherAgent/Resources/en.lproj/Localizable.strings`
- Create: `Sources/LabTetherAgent/Resources/es.lproj/Localizable.strings`
- Modify: `Package.swift`
- Test: `Tests/LabTetherAgentTests/L10nTests.swift`

- [ ] **Step 1: Update Package.swift**

Read `Package.swift`. In the executable target's resources array, add the `.lproj` directories alongside the existing `.copy("Resources/Fonts")`:

```swift
resources: [
    .copy("Resources/Fonts"),
    .process("Resources/en.lproj"),
    .process("Resources/es.lproj"),
]
```

- [ ] **Step 2: Create English strings file**

Create `Sources/LabTetherAgent/Resources/en.lproj/Localizable.strings`:

```
/* Status */
"status.connected" = "Connected";
"status.disconnected" = "Disconnected";
"status.connecting" = "Connecting";
"status.starting" = "Starting";
"status.stopped" = "Stopped";
"status.error" = "Error";
"status.reconnecting" = "Reconnecting";
"status.enrolling" = "Enrolling";
"status.auth_failed" = "Auth Failed";
"status.unavailable" = "Status Unavailable";

/* Menu Bar Quick Actions */
"menu.open_console" = "Open Web Console";
"menu.view_device" = "View This Device";
"menu.pop_out" = "Pop Out Window";
"menu.view_logs" = "View Logs";
"menu.copy_diagnostics" = "Copy Diagnostics";
"menu.test_connection" = "Test Connection";
"menu.settings" = "Settings";

/* Menu Bar Footer */
"menu.about" = "About";
"menu.setup_wizard" = "Setup Wizard";
"menu.uninstall" = "Reset & Uninstall...";

/* Settings Tabs */
"settings.connection" = "Connection";
"settings.security" = "Security";
"settings.advanced" = "Advanced";

/* Settings Connection */
"settings.hub_url" = "HUB URL";
"settings.api_token" = "API TOKEN";
"settings.enrollment_token" = "ENROLLMENT TOKEN";
"settings.asset_id" = "ASSET ID";
"settings.group_id" = "GROUP ID";
"settings.test_connection" = "Test Connection";
"settings.full_diagnostics" = "Full Diagnostics...";
"settings.start" = "Start";
"settings.stop" = "Stop";
"settings.restart" = "Restart";
"settings.restart_required" = "Restart Required";

/* Onboarding */
"onboarding.welcome_title" = "Welcome to LabTether";
"onboarding.welcome_subtitle" = "Connect this Mac to your LabTether hub\nfor remote management.";
"onboarding.auth_title" = "Authentication";
"onboarding.auth_subtitle" = "Use an enrollment token to register this device,\nor an API token if already enrolled.";
"onboarding.identity_title" = "Identity (Optional)";
"onboarding.identity_subtitle" = "Set an asset ID and group, or leave blank\nfor automatic detection.";
"onboarding.next" = "Next";
"onboarding.back" = "Back";
"onboarding.finish" = "Finish & Start Agent";
"onboarding.skip" = "Skip";
"onboarding.paste_clipboard" = "Paste from Clipboard";

/* About */
"about.title" = "LabTether Agent";
"about.version" = "Version";
"about.agent" = "Agent:";
"about.not_running" = "Not running";
"about.website" = "Website";
"about.documentation" = "Documentation";
"about.support" = "Support";

/* Session History */
"session.title" = "SESSION HISTORY";
"session.empty" = "No sessions recorded yet";
"session.clear" = "Clear History";
"session.clear_title" = "Clear Session History?";
"session.clear_message" = "This will remove all recorded session events.";
"session.today" = "Today";
"session.yesterday" = "Yesterday";

/* Bandwidth */
"bandwidth.title" = "BANDWIDTH";
"bandwidth.this_session" = "This Session";
"bandwidth.today" = "Today";
"bandwidth.last_30_days" = "Last 30 Days";
"bandwidth.empty" = "Bandwidth data will appear after the agent runs for a while";

/* Connection Diagnostics */
"diagnostics.title" = "Connection Diagnostics";
"diagnostics.run" = "Run";
"diagnostics.rerun" = "Re-run";
"diagnostics.close" = "Close";
"diagnostics.copy_results" = "Copy Results";
"diagnostics.dns" = "DNS Resolution";
"diagnostics.tcp" = "TCP Connection";
"diagnostics.tls" = "TLS Handshake";
"diagnostics.http" = "HTTP Reachability";

/* Uninstall */
"uninstall.title" = "Uninstall LabTether Agent?";
"uninstall.message" = "This will remove all configuration, credentials, and history. The app will quit.";
"uninstall.confirm" = "Uninstall & Quit";
"uninstall.cancel" = "Cancel";
```

- [ ] **Step 3: Create Spanish strings file**

Create `Sources/LabTetherAgent/Resources/es.lproj/Localizable.strings`:

```
/* Status */
"status.connected" = "Conectado";
"status.disconnected" = "Desconectado";
"status.connecting" = "Conectando";
"status.starting" = "Iniciando";
"status.stopped" = "Detenido";
"status.error" = "Error";
"status.reconnecting" = "Reconectando";
"status.enrolling" = "Inscribiendo";
"status.auth_failed" = "Autenticación fallida";
"status.unavailable" = "Estado no disponible";

/* Menu Bar Quick Actions */
"menu.open_console" = "Abrir consola web";
"menu.view_device" = "Ver este dispositivo";
"menu.pop_out" = "Ventana emergente";
"menu.view_logs" = "Ver registros";
"menu.copy_diagnostics" = "Copiar diagnósticos";
"menu.test_connection" = "Probar conexión";
"menu.settings" = "Configuración";

/* Menu Bar Footer */
"menu.about" = "Acerca de";
"menu.setup_wizard" = "Asistente de configuración";
"menu.uninstall" = "Restablecer y desinstalar...";

/* Settings Tabs */
"settings.connection" = "Conexión";
"settings.security" = "Seguridad";
"settings.advanced" = "Avanzado";

/* Settings Connection */
"settings.hub_url" = "URL DEL HUB";
"settings.api_token" = "TOKEN DE API";
"settings.enrollment_token" = "TOKEN DE INSCRIPCIÓN";
"settings.asset_id" = "ID DE ACTIVO";
"settings.group_id" = "ID DE GRUPO";
"settings.test_connection" = "Probar conexión";
"settings.full_diagnostics" = "Diagnósticos completos...";
"settings.start" = "Iniciar";
"settings.stop" = "Detener";
"settings.restart" = "Reiniciar";
"settings.restart_required" = "Reinicio requerido";

/* Onboarding */
"onboarding.welcome_title" = "Bienvenido a LabTether";
"onboarding.welcome_subtitle" = "Conecta este Mac a tu hub de LabTether\npara gestión remota.";
"onboarding.auth_title" = "Autenticación";
"onboarding.auth_subtitle" = "Usa un token de inscripción para registrar este dispositivo,\no un token de API si ya está inscrito.";
"onboarding.identity_title" = "Identidad (Opcional)";
"onboarding.identity_subtitle" = "Establece un ID de activo y grupo, o déjalo en blanco\npara detección automática.";
"onboarding.next" = "Siguiente";
"onboarding.back" = "Atrás";
"onboarding.finish" = "Finalizar e iniciar agente";
"onboarding.skip" = "Omitir";
"onboarding.paste_clipboard" = "Pegar del portapapeles";

/* About */
"about.title" = "Agente LabTether";
"about.version" = "Versión";
"about.agent" = "Agente:";
"about.not_running" = "No ejecutándose";
"about.website" = "Sitio web";
"about.documentation" = "Documentación";
"about.support" = "Soporte";

/* Session History */
"session.title" = "HISTORIAL DE SESIONES";
"session.empty" = "No se han registrado sesiones aún";
"session.clear" = "Borrar historial";
"session.clear_title" = "¿Borrar historial de sesiones?";
"session.clear_message" = "Esto eliminará todos los eventos de sesión registrados.";
"session.today" = "Hoy";
"session.yesterday" = "Ayer";

/* Bandwidth */
"bandwidth.title" = "ANCHO DE BANDA";
"bandwidth.this_session" = "Esta sesión";
"bandwidth.today" = "Hoy";
"bandwidth.last_30_days" = "Últimos 30 días";
"bandwidth.empty" = "Los datos de ancho de banda aparecerán después de que el agente se ejecute por un tiempo";

/* Connection Diagnostics */
"diagnostics.title" = "Diagnósticos de conexión";
"diagnostics.run" = "Ejecutar";
"diagnostics.rerun" = "Re-ejecutar";
"diagnostics.close" = "Cerrar";
"diagnostics.copy_results" = "Copiar resultados";
"diagnostics.dns" = "Resolución DNS";
"diagnostics.tcp" = "Conexión TCP";
"diagnostics.tls" = "Negociación TLS";
"diagnostics.http" = "Accesibilidad HTTP";

/* Uninstall */
"uninstall.title" = "¿Desinstalar agente LabTether?";
"uninstall.message" = "Esto eliminará toda la configuración, credenciales e historial. La aplicación se cerrará.";
"uninstall.confirm" = "Desinstalar y salir";
"uninstall.cancel" = "Cancelar";
```

- [ ] **Step 4: Create L10n enum**

Create `Sources/LabTetherAgent/Localization/L10n.swift`:

```swift
import Foundation

/// Type-safe localized string constants.
/// Usage: `L10n.connected` instead of hardcoded `"Connected"`.
enum L10n {
    private static let bundle = Bundle.module

    // MARK: - Status
    static var connected: String { NSLocalizedString("status.connected", bundle: bundle, comment: "") }
    static var disconnected: String { NSLocalizedString("status.disconnected", bundle: bundle, comment: "") }
    static var connecting: String { NSLocalizedString("status.connecting", bundle: bundle, comment: "") }
    static var starting: String { NSLocalizedString("status.starting", bundle: bundle, comment: "") }
    static var stopped: String { NSLocalizedString("status.stopped", bundle: bundle, comment: "") }
    static var error: String { NSLocalizedString("status.error", bundle: bundle, comment: "") }
    static var reconnecting: String { NSLocalizedString("status.reconnecting", bundle: bundle, comment: "") }
    static var enrolling: String { NSLocalizedString("status.enrolling", bundle: bundle, comment: "") }
    static var authFailed: String { NSLocalizedString("status.auth_failed", bundle: bundle, comment: "") }
    static var statusUnavailable: String { NSLocalizedString("status.unavailable", bundle: bundle, comment: "") }

    // MARK: - Menu Bar
    static var menuOpenConsole: String { NSLocalizedString("menu.open_console", bundle: bundle, comment: "") }
    static var menuViewDevice: String { NSLocalizedString("menu.view_device", bundle: bundle, comment: "") }
    static var menuPopOut: String { NSLocalizedString("menu.pop_out", bundle: bundle, comment: "") }
    static var menuViewLogs: String { NSLocalizedString("menu.view_logs", bundle: bundle, comment: "") }
    static var menuCopyDiagnostics: String { NSLocalizedString("menu.copy_diagnostics", bundle: bundle, comment: "") }
    static var menuTestConnection: String { NSLocalizedString("menu.test_connection", bundle: bundle, comment: "") }
    static var menuSettings: String { NSLocalizedString("menu.settings", bundle: bundle, comment: "") }
    static var menuAbout: String { NSLocalizedString("menu.about", bundle: bundle, comment: "") }
    static var menuSetupWizard: String { NSLocalizedString("menu.setup_wizard", bundle: bundle, comment: "") }
    static var menuUninstall: String { NSLocalizedString("menu.uninstall", bundle: bundle, comment: "") }

    // MARK: - Settings
    static var settingsConnection: String { NSLocalizedString("settings.connection", bundle: bundle, comment: "") }
    static var settingsSecurity: String { NSLocalizedString("settings.security", bundle: bundle, comment: "") }
    static var settingsAdvanced: String { NSLocalizedString("settings.advanced", bundle: bundle, comment: "") }
    static var settingsHubURL: String { NSLocalizedString("settings.hub_url", bundle: bundle, comment: "") }
    static var settingsAPIToken: String { NSLocalizedString("settings.api_token", bundle: bundle, comment: "") }
    static var settingsEnrollmentToken: String { NSLocalizedString("settings.enrollment_token", bundle: bundle, comment: "") }
    static var settingsAssetID: String { NSLocalizedString("settings.asset_id", bundle: bundle, comment: "") }
    static var settingsGroupID: String { NSLocalizedString("settings.group_id", bundle: bundle, comment: "") }
    static var settingsTestConnection: String { NSLocalizedString("settings.test_connection", bundle: bundle, comment: "") }
    static var settingsFullDiagnostics: String { NSLocalizedString("settings.full_diagnostics", bundle: bundle, comment: "") }
    static var settingsStart: String { NSLocalizedString("settings.start", bundle: bundle, comment: "") }
    static var settingsStop: String { NSLocalizedString("settings.stop", bundle: bundle, comment: "") }
    static var settingsRestart: String { NSLocalizedString("settings.restart", bundle: bundle, comment: "") }
    static var settingsRestartRequired: String { NSLocalizedString("settings.restart_required", bundle: bundle, comment: "") }

    // MARK: - Onboarding
    static var onboardingWelcomeTitle: String { NSLocalizedString("onboarding.welcome_title", bundle: bundle, comment: "") }
    static var onboardingWelcomeSubtitle: String { NSLocalizedString("onboarding.welcome_subtitle", bundle: bundle, comment: "") }
    static var onboardingAuthTitle: String { NSLocalizedString("onboarding.auth_title", bundle: bundle, comment: "") }
    static var onboardingAuthSubtitle: String { NSLocalizedString("onboarding.auth_subtitle", bundle: bundle, comment: "") }
    static var onboardingIdentityTitle: String { NSLocalizedString("onboarding.identity_title", bundle: bundle, comment: "") }
    static var onboardingIdentitySubtitle: String { NSLocalizedString("onboarding.identity_subtitle", bundle: bundle, comment: "") }
    static var onboardingNext: String { NSLocalizedString("onboarding.next", bundle: bundle, comment: "") }
    static var onboardingBack: String { NSLocalizedString("onboarding.back", bundle: bundle, comment: "") }
    static var onboardingFinish: String { NSLocalizedString("onboarding.finish", bundle: bundle, comment: "") }
    static var onboardingSkip: String { NSLocalizedString("onboarding.skip", bundle: bundle, comment: "") }
    static var onboardingPasteClipboard: String { NSLocalizedString("onboarding.paste_clipboard", bundle: bundle, comment: "") }

    // MARK: - About
    static var aboutTitle: String { NSLocalizedString("about.title", bundle: bundle, comment: "") }
    static var aboutVersion: String { NSLocalizedString("about.version", bundle: bundle, comment: "") }
    static var aboutAgent: String { NSLocalizedString("about.agent", bundle: bundle, comment: "") }
    static var aboutNotRunning: String { NSLocalizedString("about.not_running", bundle: bundle, comment: "") }
    static var aboutWebsite: String { NSLocalizedString("about.website", bundle: bundle, comment: "") }
    static var aboutDocumentation: String { NSLocalizedString("about.documentation", bundle: bundle, comment: "") }
    static var aboutSupport: String { NSLocalizedString("about.support", bundle: bundle, comment: "") }

    // MARK: - Session History
    static var sessionTitle: String { NSLocalizedString("session.title", bundle: bundle, comment: "") }
    static var sessionEmpty: String { NSLocalizedString("session.empty", bundle: bundle, comment: "") }
    static var sessionClear: String { NSLocalizedString("session.clear", bundle: bundle, comment: "") }
    static var sessionClearTitle: String { NSLocalizedString("session.clear_title", bundle: bundle, comment: "") }
    static var sessionClearMessage: String { NSLocalizedString("session.clear_message", bundle: bundle, comment: "") }
    static var sessionToday: String { NSLocalizedString("session.today", bundle: bundle, comment: "") }
    static var sessionYesterday: String { NSLocalizedString("session.yesterday", bundle: bundle, comment: "") }

    // MARK: - Bandwidth
    static var bandwidthTitle: String { NSLocalizedString("bandwidth.title", bundle: bundle, comment: "") }
    static var bandwidthThisSession: String { NSLocalizedString("bandwidth.this_session", bundle: bundle, comment: "") }
    static var bandwidthToday: String { NSLocalizedString("bandwidth.today", bundle: bundle, comment: "") }
    static var bandwidthLast30Days: String { NSLocalizedString("bandwidth.last_30_days", bundle: bundle, comment: "") }
    static var bandwidthEmpty: String { NSLocalizedString("bandwidth.empty", bundle: bundle, comment: "") }

    // MARK: - Connection Diagnostics
    static var diagnosticsTitle: String { NSLocalizedString("diagnostics.title", bundle: bundle, comment: "") }
    static var diagnosticsRun: String { NSLocalizedString("diagnostics.run", bundle: bundle, comment: "") }
    static var diagnosticsRerun: String { NSLocalizedString("diagnostics.rerun", bundle: bundle, comment: "") }
    static var diagnosticsClose: String { NSLocalizedString("diagnostics.close", bundle: bundle, comment: "") }
    static var diagnosticsCopyResults: String { NSLocalizedString("diagnostics.copy_results", bundle: bundle, comment: "") }
    static var diagnosticsDNS: String { NSLocalizedString("diagnostics.dns", bundle: bundle, comment: "") }
    static var diagnosticsTCP: String { NSLocalizedString("diagnostics.tcp", bundle: bundle, comment: "") }
    static var diagnosticsTLS: String { NSLocalizedString("diagnostics.tls", bundle: bundle, comment: "") }
    static var diagnosticsHTTP: String { NSLocalizedString("diagnostics.http", bundle: bundle, comment: "") }

    // MARK: - Uninstall
    static var uninstallTitle: String { NSLocalizedString("uninstall.title", bundle: bundle, comment: "") }
    static var uninstallMessage: String { NSLocalizedString("uninstall.message", bundle: bundle, comment: "") }
    static var uninstallConfirm: String { NSLocalizedString("uninstall.confirm", bundle: bundle, comment: "") }
    static var uninstallCancel: String { NSLocalizedString("uninstall.cancel", bundle: bundle, comment: "") }
}
```

- [ ] **Step 5: Write test for L10n**

Create `Tests/LabTetherAgentTests/L10nTests.swift`:

```swift
import XCTest
@testable import LabTetherAgent

final class L10nTests: XCTestCase {
    func testAllStringKeysReturnNonEmptyValues() {
        // Spot-check key strings resolve to non-empty values
        XCTAssertFalse(L10n.connected.isEmpty)
        XCTAssertFalse(L10n.menuSettings.isEmpty)
        XCTAssertFalse(L10n.onboardingWelcomeTitle.isEmpty)
        XCTAssertFalse(L10n.aboutTitle.isEmpty)
        XCTAssertFalse(L10n.sessionTitle.isEmpty)
        XCTAssertFalse(L10n.bandwidthTitle.isEmpty)
        XCTAssertFalse(L10n.diagnosticsTitle.isEmpty)
        XCTAssertFalse(L10n.uninstallTitle.isEmpty)
    }

    func testConnectedStringContainsExpectedEnglishValue() {
        // Verify English strings are loaded (not just returning the key)
        XCTAssertEqual(L10n.connected, "Connected")
    }
}
```

- [ ] **Step 6: Build and test**

Run: `swift build 2>&1 | tail -10`
Then: `swift test --filter L10nTests 2>&1 | tail -10`
Expected: Build succeeds, tests pass

- [ ] **Step 7: Commit**

```bash
git add Sources/LabTetherAgent/Localization/L10n.swift \
  Sources/LabTetherAgent/Resources/en.lproj/Localizable.strings \
  Sources/LabTetherAgent/Resources/es.lproj/Localizable.strings \
  Tests/LabTetherAgentTests/L10nTests.swift \
  Package.swift
git commit -m "feat: add L10n infrastructure with English and Spanish string files"
```

---

### Task 5: Replace hardcoded strings with L10n in view files

**Files:**
- Modify: Multiple view files (menu bar, settings, onboarding, about, pop-out sections, diagnostics)

This is a mechanical find-and-replace task across many files. The implementer should:

- [ ] **Step 1: Replace strings in menu bar views**

In `MenuBarQuickActionsSection.swift`, replace hardcoded labels:
- `"Open Web Console"` → `L10n.menuOpenConsole`
- `"View This Device"` → `L10n.menuViewDevice`
- `"Pop Out Window"` → `L10n.menuPopOut`
- `"View Logs"` → `L10n.menuViewLogs`
- `"Copy Diagnostics"` → `L10n.menuCopyDiagnostics`
- `"Test Connection"` → `L10n.menuTestConnection`
- `"Settings"` → `L10n.menuSettings`

In `MenuBarFooterSection.swift`:
- `"About"` → `L10n.menuAbout`
- `"Setup Wizard"` → `L10n.menuSetupWizard`
- `"Uninstall"` → `L10n.menuUninstall`
- Uninstall alert strings → `L10n.uninstallTitle`, `L10n.uninstallMessage`, `L10n.uninstallConfirm`, `L10n.uninstallCancel`

- [ ] **Step 2: Replace strings in onboarding views**

In `OnboardingWelcomeStep.swift`:
- `"Welcome to LabTether"` → `L10n.onboardingWelcomeTitle`
- Welcome subtitle → `L10n.onboardingWelcomeSubtitle`

In `OnboardingAuthStep.swift`:
- `"Authentication"` → `L10n.onboardingAuthTitle`
- Auth subtitle → `L10n.onboardingAuthSubtitle`

In `OnboardingIdentityStep.swift`:
- `"Identity (Optional)"` → `L10n.onboardingIdentityTitle`
- Identity subtitle → `L10n.onboardingIdentitySubtitle`
- `"Finish & Start Agent"` → `L10n.onboardingFinish`
- `"Test Connection"` → `L10n.settingsTestConnection`

In `OnboardingView.swift`:
- `"Next"` → `L10n.onboardingNext`
- `"Back"` → `L10n.onboardingBack`

- [ ] **Step 3: Replace strings in About view**

In `AboutView.swift`:
- `"LabTether Agent"` → `L10n.aboutTitle`
- `"Not running"` → `L10n.aboutNotRunning`
- `"Website"` → `L10n.aboutWebsite`
- `"Documentation"` → `L10n.aboutDocumentation`
- `"Support"` → `L10n.aboutSupport`

- [ ] **Step 4: Replace strings in pop-out and diagnostics views**

In `PopOutSessionHistorySection.swift`:
- `"SESSION HISTORY"` → `L10n.sessionTitle`
- `"No sessions recorded yet"` → `L10n.sessionEmpty`
- `"Clear History"` → `L10n.sessionClear`
- `"Clear Session History?"` → `L10n.sessionClearTitle`
- Clear message → `L10n.sessionClearMessage`
- `"Today"` → `L10n.sessionToday`
- `"Yesterday"` → `L10n.sessionYesterday`

In `PopOutBandwidthSection.swift`:
- `"BANDWIDTH"` → `L10n.bandwidthTitle`
- `"This Session"` → `L10n.bandwidthThisSession`
- `"Today"` → `L10n.bandwidthToday`
- `"Last 30 Days"` → `L10n.bandwidthLast30Days`
- Empty state text → `L10n.bandwidthEmpty`

In `ConnectionDiagnosticsSheet.swift`:
- `"Connection Diagnostics"` → `L10n.diagnosticsTitle`
- `"Run"` → `L10n.diagnosticsRun`
- `"Re-run"` → `L10n.diagnosticsRerun`
- `"Close"` → `L10n.diagnosticsClose`
- `"Copy Results"` → `L10n.diagnosticsCopyResults`

In `SettingsConnectionTab.swift`:
- `"Test Connection"` → `L10n.settingsTestConnection`
- `"Full Diagnostics..."` → `L10n.settingsFullDiagnostics`

- [ ] **Step 5: Build and run full test suite**

Run: `swift build 2>&1 | tail -10`
Then: `swift test 2>&1 | grep "Executed.*tests"`
Expected: Build succeeds, all tests pass

- [ ] **Step 6: Commit**

```bash
git add Sources/LabTetherAgent/Views/ \
  Sources/LabTetherAgent/Services/UninstallManager.swift
git commit -m "feat: replace hardcoded user-facing strings with L10n localized constants"
```

---

### Task 6: Final integration test

- [ ] **Step 1: Run full test suite**

Run: `swift test 2>&1 | tail -30`
Expected: All tests PASS

- [ ] **Step 2: Build release**

Run: `swift build -c release 2>&1 | grep -v CLAUDE.md | grep -E "warning:|error:|Build complete"`
Expected: Build succeeds

- [ ] **Step 3: Verify string count consistency**

Run: `grep -c '=' Sources/LabTetherAgent/Resources/en.lproj/Localizable.strings && grep -c '=' Sources/LabTetherAgent/Resources/es.lproj/Localizable.strings`
Expected: Both files have the same number of entries
