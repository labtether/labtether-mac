import Combine
import Foundation

/// Notify-only update check for the signed macOS app, matching the Windows
/// tray app: ask GitHub for the latest release at most once a day, compare it
/// with this build's version, and expose it for a menu item that opens the
/// release page. It never downloads or installs anything, and network or
/// parse failures are silent.
@MainActor
final class AppUpdateChecker: ObservableObject {
    typealias Fetch = (URLRequest) async throws -> (Data, URLResponse)

    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/labtether/labtether-mac/releases/latest")!
    static let checkInterval: TimeInterval = 24 * 60 * 60
    private static let pollInterval: TimeInterval = 60 * 60
    private static let lastCheckKey = "appUpdateLastCheck"
    private static let latestVersionKey = "appUpdateLatestVersion"
    private static let releasePageKey = "appUpdateReleasePage"

    @Published private(set) var availableUpdate: AppUpdateRelease?

    private let settings: AgentSettings
    private let currentVersion: String
    private let fetch: Fetch
    private var timer: Timer?
    private var enabledObserver: AnyCancellable?
    private var checking = false

    init(
        settings: AgentSettings,
        currentVersion: String = BundleHelper.appVersion,
        fetch: @escaping Fetch = { try await URLSession.shared.data(for: $0) }
    ) {
        self.settings = settings
        self.currentVersion = currentVersion
        self.fetch = fetch
    }

    /// Starts checks for the installed app. Disposable state directories
    /// (separate QA instances) never contact GitHub.
    func start() {
        guard settings.allowsSystemIntegration else { return }
        // @Published emits the new value before it is stored, so act on the
        // emitted value rather than reading the setting back.
        enabledObserver = settings.$checkForAppUpdates
            .removeDuplicates()
            .sink { [weak self] enabled in self?.refresh(enabled: enabled) }
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.refresh(enabled: self.settings.checkForAppUpdates)
            }
        }
    }

    private func refresh(enabled: Bool) {
        guard enabled else {
            availableUpdate = nil
            return
        }
        showRecordedRelease()
        guard !checking, isCheckDue else { return }
        checking = true
        // Record the attempt first so failures still wait a full day.
        settings.setAppUpdateRecord(String(Date().timeIntervalSince1970), key: Self.lastCheckKey)
        Task { [weak self] in
            guard let self else { return }
            let release = await self.fetchLatestRelease()
            self.checking = false
            guard let release else { return }
            self.settings.setAppUpdateRecord(release.version, key: Self.latestVersionKey)
            self.settings.setAppUpdateRecord(release.pageURL.absoluteString, key: Self.releasePageKey)
            if self.settings.checkForAppUpdates { self.showRecordedRelease() }
        }
    }

    private var isCheckDue: Bool {
        guard let last = Double(settings.appUpdateRecord(Self.lastCheckKey)) else { return true }
        let elapsed = Date().timeIntervalSince1970 - last
        // A clock that moved backwards also makes the record due.
        return elapsed >= Self.checkInterval || elapsed < 0
    }

    /// Keeps a found update visible across relaunches until this build is at
    /// least that version.
    private func showRecordedRelease() {
        let version = settings.appUpdateRecord(Self.latestVersionKey)
        guard AppVersion.isNewer(version, than: currentVersion) else {
            if availableUpdate != nil { availableUpdate = nil }
            return
        }
        let page = AppUpdateRelease.trustedPage(URL(string: settings.appUpdateRecord(Self.releasePageKey)))
        let next = AppUpdateRelease(version: version, pageURL: page)
        if availableUpdate != next { availableUpdate = next }
    }

    private func fetchLatestRelease() async -> AppUpdateRelease? {
        var request = URLRequest(
            url: Self.latestReleaseAPI,
            cachePolicy: .reloadIgnoringLocalCacheData,
            timeoutInterval: 15
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("LabTetherAgent-macOS/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        guard let result = try? await fetch(request),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return AppUpdateRelease.parse(result.0)
    }
}
