import Foundation

/// Validates AgentSettings and returns human-readable error messages.
enum AgentSettingsValidator {
    static func validationErrors(for settings: AgentSettings) -> [String] {
        var errors: [String] = []

        if settings.hubURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errors.append("Hub URL is required.")
        } else if settings.normalizedHubWebSocketURL() == nil {
            errors.append("Hub URL must be a valid host URL (ws/wss/http/https).")
        }

        let trimmedPort = settings.agentPort.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmedPort), (1...65535).contains(value) {
            // valid
        } else {
            errors.append("Agent Port must be a number between 1 and 65535.")
        }

        let dockerMode = settings.normalizedDockerMode()
        if !AgentSettings.allowedDockerModes.contains(dockerMode) {
            errors.append("Docker mode must be one of auto, true, or false.")
        }

        if dockerMode != "false" {
            if let endpointError = settings.dockerEndpointValidationError(settings.dockerEndpoint) {
                errors.append(endpointError)
            }
            let trimmedInterval = settings.dockerDiscoveryIntervalSec.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Int(trimmedInterval), (5...3600).contains(value) {
                // valid
            } else {
                errors.append("Docker discovery interval must be a number between 5 and 3600 seconds.")
            }
        }

        let filesMode = settings.normalizedFilesRootMode()
        if !AgentSettings.allowedFileRootModes.contains(filesMode) {
            errors.append("Files Root Mode must be either home or full.")
        }

        let normalizedLevel = settings.normalizedLogLevel()
        if !AgentSettings.allowedLogLevels.contains(normalizedLevel) {
            errors.append("Log level must be one of debug, info, warn, or error.")
        }

        let trimmedSTUNURL = settings.normalizedWebRTCSTUNURL().trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSTUNURL.isEmpty {
            errors.append("WebRTC STUN URL cannot be empty.")
        }

        let trimmedCaptureFPS = settings.captureFPS.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmedCaptureFPS), (5...120).contains(value) {
            // valid
        } else {
            errors.append("Capture FPS must be a number between 5 and 120.")
        }

        if let portListError = AgentSettingsNormalization.portListValidationError(settings.servicesDiscoveryPortScanPorts) {
            errors.append("Local scan ports: \(portListError)")
        }
        if let portListError = AgentSettingsNormalization.portListValidationError(settings.servicesDiscoveryLANScanPorts) {
            errors.append("LAN scan ports: \(portListError)")
        }
        if let cidrError = AgentSettingsNormalization.cidrListValidationError(settings.servicesDiscoveryLANScanCIDRs) {
            errors.append("LAN CIDRs: \(cidrError)")
        }

        let trimmedLANMaxHosts = settings.servicesDiscoveryLANScanMaxHosts.trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Int(trimmedLANMaxHosts), (1...1024).contains(value) {
            // valid
        } else {
            errors.append("LAN scan max hosts must be a number between 1 and 1024.")
        }

        let trimmedCAFile = settings.tlsCAFile.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCAFile.isEmpty && !FileManager.default.fileExists(atPath: trimmedCAFile) {
            errors.append("CA certificate file not found: \(trimmedCAFile)")
        }

        errors.append(contentsOf: settings.secretPersistenceErrors)
        return errors
    }
}
