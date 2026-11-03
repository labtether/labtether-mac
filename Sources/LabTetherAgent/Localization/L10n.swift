import Foundation

/// Localized string accessors for all user-visible text in LabTether Agent.
///
/// Access strings via static computed properties. SPM generates `Bundle.module`
/// when resources are processed, ensuring strings are loaded from the correct bundle
/// regardless of how the executable is invoked.
///
/// Example usage:
/// ```swift
/// Text(L10n.connected)
/// label.stringValue = L10n.menuSettings
/// ```
enum L10n {
    private static let bundle = BundleHelper.resourceBundle

    // MARK: - Status

    /// "Connected" / "Conectado"
    static var connected: String {
        NSLocalizedString("status.connected", bundle: bundle, comment: "")
    }

    /// "Disconnected" / "Desconectado"
    static var disconnected: String {
        NSLocalizedString("status.disconnected", bundle: bundle, comment: "")
    }

    /// "Connecting" / "Conectando"
    static var connecting: String {
        NSLocalizedString("status.connecting", bundle: bundle, comment: "")
    }

    /// "Starting" / "Iniciando"
    static var starting: String {
        NSLocalizedString("status.starting", bundle: bundle, comment: "")
    }

    /// "Stopped" / "Detenido"
    static var stopped: String {
        NSLocalizedString("status.stopped", bundle: bundle, comment: "")
    }

    /// "Error" / "Error"
    static var statusError: String {
        NSLocalizedString("status.error", bundle: bundle, comment: "")
    }

    /// "Reconnecting" / "Reconectando"
    static var reconnecting: String {
        NSLocalizedString("status.reconnecting", bundle: bundle, comment: "")
    }

    /// "Enrolling" / "Inscribiendo"
    static var enrolling: String {
        NSLocalizedString("status.enrolling", bundle: bundle, comment: "")
    }

    /// "Token refused" / "Token rechazado"
    static var authFailed: String {
        NSLocalizedString("status.auth_failed", bundle: bundle, comment: "")
    }

    /// "Status unavailable" / "Estado no disponible"
    static var statusUnavailable: String {
        NSLocalizedString("status.unavailable", bundle: bundle, comment: "")
    }

    // MARK: - Menu Bar Quick Actions

    /// "Open web console" / "Abrir consola web"
    static var menuOpenConsole: String {
        NSLocalizedString("menu.open_console", bundle: bundle, comment: "")
    }

    /// "Open device page" / "Abrir página del dispositivo"
    static var menuViewDevice: String {
        NSLocalizedString("menu.view_device", bundle: bundle, comment: "")
    }

    /// "Pop out" / "Ventana flotante"
    static var menuPopOut: String {
        NSLocalizedString("menu.pop_out", bundle: bundle, comment: "")
    }

    /// "View logs" / "Ver registros"
    static var menuViewLogs: String {
        NSLocalizedString("menu.view_logs", bundle: bundle, comment: "")
    }

    /// "Copy diagnostics" / "Copiar diagnósticos"
    static var menuCopyDiagnostics: String {
        NSLocalizedString("menu.copy_diagnostics", bundle: bundle, comment: "")
    }

    /// "Test connection" / "Probar conexión"
    static var menuTestConnection: String {
        NSLocalizedString("menu.test_connection", bundle: bundle, comment: "")
    }

    /// "Settings…" / "Ajustes…"
    static var menuSettings: String {
        NSLocalizedString("menu.settings", bundle: bundle, comment: "")
    }

    // MARK: - Menu Bar Window

    /// "Alerts" / "Alertas"
    static var menuAlerts: String {
        NSLocalizedString("menu.alerts", bundle: bundle, comment: "")
    }

    /// "Update available" / "Actualización disponible"
    static var menuUpdateAvailable: String {
        NSLocalizedString("menu.update_available", bundle: bundle, comment: "")
    }

    /// "Quit" / "Salir"
    static var menuQuit: String {
        NSLocalizedString("menu.quit", bundle: bundle, comment: "")
    }

    // MARK: - Menu Bar Footer

    /// "About LabTether" / "Acerca de LabTether"
    static var menuAbout: String {
        NSLocalizedString("menu.about", bundle: bundle, comment: "")
    }

    /// "Run setup again" / "Volver a configurar"
    static var menuSetupWizard: String {
        NSLocalizedString("menu.setup_wizard", bundle: bundle, comment: "")
    }

    /// "Reset and uninstall…" / "Restablecer y desinstalar…"
    static var menuUninstall: String {
        NSLocalizedString("menu.uninstall", bundle: bundle, comment: "")
    }

    // MARK: - Settings Tabs

    /// "Connection" / "Conexión"
    static var settingsConnection: String {
        NSLocalizedString("settings.connection", bundle: bundle, comment: "")
    }

    /// "Security" / "Seguridad"
    static var settingsSecurity: String {
        NSLocalizedString("settings.security", bundle: bundle, comment: "")
    }

    /// "Advanced" / "Avanzado"
    static var settingsAdvanced: String {
        NSLocalizedString("settings.advanced", bundle: bundle, comment: "")
    }

    // MARK: - Settings Connection

    /// "Hub address" / "Dirección del Hub"
    static var settingsHubURL: String {
        NSLocalizedString("settings.hub_url", bundle: bundle, comment: "")
    }

    /// "API token" / "Token de API"
    static var settingsAPIToken: String {
        NSLocalizedString("settings.api_token", bundle: bundle, comment: "")
    }

    /// "Enrollment token" / "Token de inscripción"
    static var settingsEnrollmentToken: String {
        NSLocalizedString("settings.enrollment_token", bundle: bundle, comment: "")
    }

    /// "Asset ID" / "ID de activo"
    static var settingsAssetID: String {
        NSLocalizedString("settings.asset_id", bundle: bundle, comment: "")
    }

    /// "Group ID" / "ID de grupo"
    static var settingsGroupID: String {
        NSLocalizedString("settings.group_id", bundle: bundle, comment: "")
    }

    /// "Test connection" / "Probar conexión"
    static var settingsTestConnection: String {
        NSLocalizedString("settings.test_connection", bundle: bundle, comment: "")
    }

    /// "Diagnostics…" / "Diagnósticos…"
    static var settingsFullDiagnostics: String {
        NSLocalizedString("settings.full_diagnostics", bundle: bundle, comment: "")
    }

    /// "Start" / "Iniciar"
    static var settingsStart: String {
        NSLocalizedString("settings.start", bundle: bundle, comment: "")
    }

    /// "Stop" / "Detener"
    static var settingsStop: String {
        NSLocalizedString("settings.stop", bundle: bundle, comment: "")
    }

    /// "Restart" / "Reiniciar"
    static var settingsRestart: String {
        NSLocalizedString("settings.restart", bundle: bundle, comment: "")
    }

    /// "Restart to apply changes" / "Reinicia para aplicar los cambios"
    static var settingsRestartRequired: String {
        NSLocalizedString("settings.restart_required", bundle: bundle, comment: "")
    }

    // MARK: - Onboarding

    /// "Connect this Mac to your Hub" / "Conecta este Mac a tu Hub"
    static var onboardingWelcomeTitle: String {
        NSLocalizedString("onboarding.welcome_title", bundle: bundle, comment: "")
    }

    /// "The address and a token are in the Hub under Settings › Agents." / "La dirección y un token están en el Hub, en Settings › Agents."
    static var onboardingWelcomeSubtitle: String {
        NSLocalizedString("onboarding.welcome_subtitle", bundle: bundle, comment: "")
    }

    /// "Token" / "Token"
    static var onboardingToken: String {
        NSLocalizedString("onboarding.token", bundle: bundle, comment: "")
    }

    /// "Advanced" / "Avanzado"
    static var onboardingAdvanced: String {
        NSLocalizedString("onboarding.advanced", bundle: bundle, comment: "")
    }

    /// "Connect" / "Conectar"
    static var onboardingFinish: String {
        NSLocalizedString("onboarding.finish", bundle: bundle, comment: "")
    }

    /// "Paste" / "Pegar"
    static var onboardingPasteClipboard: String {
        NSLocalizedString("onboarding.paste_clipboard", bundle: bundle, comment: "")
    }

    // MARK: - About

    /// "LabTether Agent" / "Agente LabTether"
    static var aboutTitle: String {
        NSLocalizedString("about.title", bundle: bundle, comment: "")
    }

    /// "Version" / "Versión"
    static var aboutVersion: String {
        NSLocalizedString("about.version", bundle: bundle, comment: "")
    }

    /// "Agent" / "Agente"
    static var aboutAgent: String {
        NSLocalizedString("about.agent", bundle: bundle, comment: "")
    }

    /// "not running" / "no se está ejecutando"
    static var aboutNotRunning: String {
        NSLocalizedString("about.not_running", bundle: bundle, comment: "")
    }

    /// "Website" / "Sitio web"
    static var aboutWebsite: String {
        NSLocalizedString("about.website", bundle: bundle, comment: "")
    }

    /// "Documentation" / "Documentación"
    static var aboutDocumentation: String {
        NSLocalizedString("about.documentation", bundle: bundle, comment: "")
    }

    /// "Support" / "Soporte"
    static var aboutSupport: String {
        NSLocalizedString("about.support", bundle: bundle, comment: "")
    }

    // MARK: - Session History

    /// "Sessions" / "Sesiones"
    static var sessionTitle: String {
        NSLocalizedString("session.title", bundle: bundle, comment: "")
    }

    /// "No sessions yet" / "Aún no hay sesiones"
    static var sessionEmpty: String {
        NSLocalizedString("session.empty", bundle: bundle, comment: "")
    }

    /// "Clear" / "Borrar"
    static var sessionClear: String {
        NSLocalizedString("session.clear", bundle: bundle, comment: "")
    }

    /// "Clear session history?" / "¿Borrar el historial de sesiones?"
    static var sessionClearTitle: String {
        NSLocalizedString("session.clear_title", bundle: bundle, comment: "")
    }

    /// "This removes all recorded sessions." / "Se eliminarán todas las sesiones registradas."
    static var sessionClearMessage: String {
        NSLocalizedString("session.clear_message", bundle: bundle, comment: "")
    }

    /// "Today" / "Hoy"
    static var sessionToday: String {
        NSLocalizedString("session.today", bundle: bundle, comment: "")
    }

    /// "Yesterday" / "Ayer"
    static var sessionYesterday: String {
        NSLocalizedString("session.yesterday", bundle: bundle, comment: "")
    }

    // MARK: - Bandwidth

    /// "Bandwidth" / "Ancho de banda"
    static var bandwidthTitle: String {
        NSLocalizedString("bandwidth.title", bundle: bundle, comment: "")
    }

    /// "This session" / "Esta sesión"
    static var bandwidthThisSession: String {
        NSLocalizedString("bandwidth.this_session", bundle: bundle, comment: "")
    }

    /// "Today" / "Hoy"
    static var bandwidthToday: String {
        NSLocalizedString("bandwidth.today", bundle: bundle, comment: "")
    }

    /// "Last 30 days" / "Últimos 30 días"
    static var bandwidthLast30Days: String {
        NSLocalizedString("bandwidth.last_30_days", bundle: bundle, comment: "")
    }

    /// "No bandwidth data yet" / "Aún no hay datos de ancho de banda"
    static var bandwidthEmpty: String {
        NSLocalizedString("bandwidth.empty", bundle: bundle, comment: "")
    }

    // MARK: - Connection Diagnostics

    /// "Connection diagnostics" / "Diagnóstico de conexión"
    static var diagnosticsTitle: String {
        NSLocalizedString("diagnostics.title", bundle: bundle, comment: "")
    }

    /// "Run" / "Ejecutar"
    static var diagnosticsRun: String {
        NSLocalizedString("diagnostics.run", bundle: bundle, comment: "")
    }

    /// "Run again" / "Ejecutar de nuevo"
    static var diagnosticsRerun: String {
        NSLocalizedString("diagnostics.rerun", bundle: bundle, comment: "")
    }

    /// "Close" / "Cerrar"
    static var diagnosticsClose: String {
        NSLocalizedString("diagnostics.close", bundle: bundle, comment: "")
    }

    /// "Copy results" / "Copiar resultados"
    static var diagnosticsCopyResults: String {
        NSLocalizedString("diagnostics.copy_results", bundle: bundle, comment: "")
    }

    /// "DNS lookup" / "Búsqueda DNS"
    static var diagnosticsDNS: String {
        NSLocalizedString("diagnostics.dns", bundle: bundle, comment: "")
    }

    /// "TCP connection" / "Conexión TCP"
    static var diagnosticsTCP: String {
        NSLocalizedString("diagnostics.tcp", bundle: bundle, comment: "")
    }

    /// "TLS handshake" / "Negociación TLS"
    static var diagnosticsTLS: String {
        NSLocalizedString("diagnostics.tls", bundle: bundle, comment: "")
    }

    /// "HTTP reachability" / "Accesibilidad HTTP"
    static var diagnosticsHTTP: String {
        NSLocalizedString("diagnostics.http", bundle: bundle, comment: "")
    }

    // MARK: - Uninstall

    /// "Uninstall LabTether?" / "¿Desinstalar LabTether?"
    static var uninstallTitle: String {
        NSLocalizedString("uninstall.title", bundle: bundle, comment: "")
    }

    /// "This removes all settings, tokens and history, then quits the app." / "Se eliminarán todos los ajustes, tokens e historial y la app se cerrará."
    static var uninstallMessage: String {
        NSLocalizedString("uninstall.message", bundle: bundle, comment: "")
    }

    /// "Uninstall and quit" / "Desinstalar y salir"
    static var uninstallConfirm: String {
        NSLocalizedString("uninstall.confirm", bundle: bundle, comment: "")
    }

    /// "Cancel" / "Cancelar"
    static var uninstallCancel: String {
        NSLocalizedString("uninstall.cancel", bundle: bundle, comment: "")
    }
}
