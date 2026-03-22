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
    private static let bundle = Bundle.module

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

    /// "Auth Failed" / "Autenticación fallida"
    static var authFailed: String {
        NSLocalizedString("status.auth_failed", bundle: bundle, comment: "")
    }

    /// "Status Unavailable" / "Estado no disponible"
    static var statusUnavailable: String {
        NSLocalizedString("status.unavailable", bundle: bundle, comment: "")
    }

    // MARK: - Menu Bar Quick Actions

    /// "Open Web Console" / "Abrir consola web"
    static var menuOpenConsole: String {
        NSLocalizedString("menu.open_console", bundle: bundle, comment: "")
    }

    /// "View This Device" / "Ver este dispositivo"
    static var menuViewDevice: String {
        NSLocalizedString("menu.view_device", bundle: bundle, comment: "")
    }

    /// "Pop Out Window" / "Ventana emergente"
    static var menuPopOut: String {
        NSLocalizedString("menu.pop_out", bundle: bundle, comment: "")
    }

    /// "View Logs" / "Ver registros"
    static var menuViewLogs: String {
        NSLocalizedString("menu.view_logs", bundle: bundle, comment: "")
    }

    /// "Copy Diagnostics" / "Copiar diagnósticos"
    static var menuCopyDiagnostics: String {
        NSLocalizedString("menu.copy_diagnostics", bundle: bundle, comment: "")
    }

    /// "Test Connection" / "Probar conexión"
    static var menuTestConnection: String {
        NSLocalizedString("menu.test_connection", bundle: bundle, comment: "")
    }

    /// "Settings" / "Configuración"
    static var menuSettings: String {
        NSLocalizedString("menu.settings", bundle: bundle, comment: "")
    }

    // MARK: - Menu Bar Footer

    /// "About" / "Acerca de"
    static var menuAbout: String {
        NSLocalizedString("menu.about", bundle: bundle, comment: "")
    }

    /// "Setup Wizard" / "Asistente de configuración"
    static var menuSetupWizard: String {
        NSLocalizedString("menu.setup_wizard", bundle: bundle, comment: "")
    }

    /// "Reset & Uninstall..." / "Restablecer y desinstalar..."
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

    /// "HUB URL" / "URL DEL HUB"
    static var settingsHubURL: String {
        NSLocalizedString("settings.hub_url", bundle: bundle, comment: "")
    }

    /// "API TOKEN" / "TOKEN DE API"
    static var settingsAPIToken: String {
        NSLocalizedString("settings.api_token", bundle: bundle, comment: "")
    }

    /// "ENROLLMENT TOKEN" / "TOKEN DE INSCRIPCIÓN"
    static var settingsEnrollmentToken: String {
        NSLocalizedString("settings.enrollment_token", bundle: bundle, comment: "")
    }

    /// "ASSET ID" / "ID DE ACTIVO"
    static var settingsAssetID: String {
        NSLocalizedString("settings.asset_id", bundle: bundle, comment: "")
    }

    /// "GROUP ID" / "ID DE GRUPO"
    static var settingsGroupID: String {
        NSLocalizedString("settings.group_id", bundle: bundle, comment: "")
    }

    /// "Test Connection" / "Probar conexión"
    static var settingsTestConnection: String {
        NSLocalizedString("settings.test_connection", bundle: bundle, comment: "")
    }

    /// "Full Diagnostics..." / "Diagnósticos completos..."
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

    /// "Restart Required" / "Reinicio requerido"
    static var settingsRestartRequired: String {
        NSLocalizedString("settings.restart_required", bundle: bundle, comment: "")
    }

    // MARK: - Onboarding

    /// "Welcome to LabTether" / "Bienvenido a LabTether"
    static var onboardingWelcomeTitle: String {
        NSLocalizedString("onboarding.welcome_title", bundle: bundle, comment: "")
    }

    /// Multi-line subtitle for the welcome step.
    static var onboardingWelcomeSubtitle: String {
        NSLocalizedString("onboarding.welcome_subtitle", bundle: bundle, comment: "")
    }

    /// "Authentication" / "Autenticación"
    static var onboardingAuthTitle: String {
        NSLocalizedString("onboarding.auth_title", bundle: bundle, comment: "")
    }

    /// Multi-line subtitle for the authentication step.
    static var onboardingAuthSubtitle: String {
        NSLocalizedString("onboarding.auth_subtitle", bundle: bundle, comment: "")
    }

    /// "Identity (Optional)" / "Identidad (Opcional)"
    static var onboardingIdentityTitle: String {
        NSLocalizedString("onboarding.identity_title", bundle: bundle, comment: "")
    }

    /// Multi-line subtitle for the identity step.
    static var onboardingIdentitySubtitle: String {
        NSLocalizedString("onboarding.identity_subtitle", bundle: bundle, comment: "")
    }

    /// "Next" / "Siguiente"
    static var onboardingNext: String {
        NSLocalizedString("onboarding.next", bundle: bundle, comment: "")
    }

    /// "Back" / "Atrás"
    static var onboardingBack: String {
        NSLocalizedString("onboarding.back", bundle: bundle, comment: "")
    }

    /// "Finish & Start Agent" / "Finalizar e iniciar agente"
    static var onboardingFinish: String {
        NSLocalizedString("onboarding.finish", bundle: bundle, comment: "")
    }

    /// "Skip" / "Omitir"
    static var onboardingSkip: String {
        NSLocalizedString("onboarding.skip", bundle: bundle, comment: "")
    }

    /// "Paste from Clipboard" / "Pegar del portapapeles"
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

    /// "Agent:" / "Agente:"
    static var aboutAgent: String {
        NSLocalizedString("about.agent", bundle: bundle, comment: "")
    }

    /// "Not running" / "No ejecutándose"
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

    /// "SESSION HISTORY" / "HISTORIAL DE SESIONES"
    static var sessionTitle: String {
        NSLocalizedString("session.title", bundle: bundle, comment: "")
    }

    /// "No sessions recorded yet" / "No se han registrado sesiones aún"
    static var sessionEmpty: String {
        NSLocalizedString("session.empty", bundle: bundle, comment: "")
    }

    /// "Clear History" / "Borrar historial"
    static var sessionClear: String {
        NSLocalizedString("session.clear", bundle: bundle, comment: "")
    }

    /// "Clear Session History?" / "¿Borrar historial de sesiones?"
    static var sessionClearTitle: String {
        NSLocalizedString("session.clear_title", bundle: bundle, comment: "")
    }

    /// "This will remove all recorded session events." / "Esto eliminará todos los eventos de sesión registrados."
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

    /// "BANDWIDTH" / "ANCHO DE BANDA"
    static var bandwidthTitle: String {
        NSLocalizedString("bandwidth.title", bundle: bundle, comment: "")
    }

    /// "This Session" / "Esta sesión"
    static var bandwidthThisSession: String {
        NSLocalizedString("bandwidth.this_session", bundle: bundle, comment: "")
    }

    /// "Today" / "Hoy"
    static var bandwidthToday: String {
        NSLocalizedString("bandwidth.today", bundle: bundle, comment: "")
    }

    /// "Last 30 Days" / "Últimos 30 días"
    static var bandwidthLast30Days: String {
        NSLocalizedString("bandwidth.last_30_days", bundle: bundle, comment: "")
    }

    /// Empty state message shown before bandwidth data is available.
    static var bandwidthEmpty: String {
        NSLocalizedString("bandwidth.empty", bundle: bundle, comment: "")
    }

    // MARK: - Connection Diagnostics

    /// "Connection Diagnostics" / "Diagnósticos de conexión"
    static var diagnosticsTitle: String {
        NSLocalizedString("diagnostics.title", bundle: bundle, comment: "")
    }

    /// "Run" / "Ejecutar"
    static var diagnosticsRun: String {
        NSLocalizedString("diagnostics.run", bundle: bundle, comment: "")
    }

    /// "Re-run" / "Re-ejecutar"
    static var diagnosticsRerun: String {
        NSLocalizedString("diagnostics.rerun", bundle: bundle, comment: "")
    }

    /// "Close" / "Cerrar"
    static var diagnosticsClose: String {
        NSLocalizedString("diagnostics.close", bundle: bundle, comment: "")
    }

    /// "Copy Results" / "Copiar resultados"
    static var diagnosticsCopyResults: String {
        NSLocalizedString("diagnostics.copy_results", bundle: bundle, comment: "")
    }

    /// "DNS Resolution" / "Resolución DNS"
    static var diagnosticsDNS: String {
        NSLocalizedString("diagnostics.dns", bundle: bundle, comment: "")
    }

    /// "TCP Connection" / "Conexión TCP"
    static var diagnosticsTCP: String {
        NSLocalizedString("diagnostics.tcp", bundle: bundle, comment: "")
    }

    /// "TLS Handshake" / "Negociación TLS"
    static var diagnosticsTLS: String {
        NSLocalizedString("diagnostics.tls", bundle: bundle, comment: "")
    }

    /// "HTTP Reachability" / "Accesibilidad HTTP"
    static var diagnosticsHTTP: String {
        NSLocalizedString("diagnostics.http", bundle: bundle, comment: "")
    }

    // MARK: - Uninstall

    /// "Uninstall LabTether Agent?" / "¿Desinstalar agente LabTether?"
    static var uninstallTitle: String {
        NSLocalizedString("uninstall.title", bundle: bundle, comment: "")
    }

    /// Destructive action description shown in the uninstall alert.
    static var uninstallMessage: String {
        NSLocalizedString("uninstall.message", bundle: bundle, comment: "")
    }

    /// "Uninstall & Quit" / "Desinstalar y salir"
    static var uninstallConfirm: String {
        NSLocalizedString("uninstall.confirm", bundle: bundle, comment: "")
    }

    /// "Cancel" / "Cancelar"
    static var uninstallCancel: String {
        NSLocalizedString("uninstall.cancel", bundle: bundle, comment: "")
    }
}
