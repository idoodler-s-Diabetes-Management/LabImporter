import SafariServices
import SwiftUI
import UIKit

// MARK: - App info

enum AppInfo {
    private static func string(_ key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String,
              !value.isEmpty else { return nil }
        return value
    }

    static var version: String { string("CFBundleShortVersionString") ?? "—" }
    static var build: String { string("CFBundleVersion") ?? "—" }
    static var branch: String { string("GitBranch") ?? "unknown" }
    static var commit: String { string("GitCommit") ?? "unknown" }

    /// The app's license text, read from the `LICENSE` file copied into the
    /// bundle at build time (see the "Copy LICENSE" build phase). This keeps the
    /// single source of truth in the repo-root `LICENSE` rather than duplicating
    /// it in source. Returns a short message if the file is missing.
    static var licenseText: String {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return String(localized: "The license is unavailable in this build.")
        }
        return text
    }

    /// Web URL of the repository this build came from, stamped into `Info.plist`
    /// at build time (`GitRepositoryURL`) so forks open their own repo. Returns
    /// `nil` when the build did not stamp a URL (e.g. local Xcode builds), in
    /// which case the GitHub buttons are hidden.
    static var repositoryURL: URL? {
        guard let value = string("GitRepositoryURL") else { return nil }
        return webURL(from: value)
    }

    /// URL that opens the "new issue" composer for `repositoryURL`, pre-filling
    /// the body with build metadata to help triage reports.
    static var newIssueURL: URL? {
        guard let base = repositoryURL?.appendingPathComponent("issues/new"),
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return nil }
        let body = """


        ---
        Version: \(version) (\(build))
        Branch: \(branch)
        Commit: \(commit)
        """
        components.queryItems = [URLQueryItem(name: "body", value: body)]
        return components.url
    }

    /// Normalizes a git remote string (`https`, `.git` suffix, or `git@host:owner/repo`
    /// SSH form) into a browsable `https` web URL.
    private static func webURL(from remote: String) -> URL? {
        var value = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if let range = value.range(of: "git@") {
            // git@github.com:owner/repo(.git) -> https://github.com/owner/repo
            let hostAndPath = value[range.upperBound...].replacingOccurrences(of: ":", with: "/")
            value = "https://" + hostAndPath
        }
        if value.hasSuffix(".git") {
            value = String(value.dropLast(4))
        }
        return URL(string: value)
    }
}

// MARK: - Build / installation details

extension AppInfo {
    /// How this build reached the device. Drives the build-info card's badge and
    /// whether an expiry date can be shown. Everything here is derived on device —
    /// no network — in keeping with the app's no-server design.
    enum InstallKind {
        case appStore
        case testFlight
        /// Development / ad-hoc / enterprise — a build that carries an embedded
        /// provisioning profile and therefore a hard expiry.
        case development
        case simulator
    }

    /// The app's primary icon, loaded from the asset catalog at runtime so the
    /// build-info card can show it. Prefers the generated icon-file names Xcode
    /// injects into `CFBundleIcons` in the built `Info.plist`, then the asset name.
    /// Returns `nil` in contexts where neither resolves (e.g. some previews).
    static var icon: UIImage? {
        if let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String],
           let last = files.last,
           let image = UIImage(named: last) {
            return image
        }
        return UIImage(named: "AppIcon")
    }

    /// Where this build came from. Order matters: a build carrying an embedded
    /// provisioning profile (development / ad-hoc) is reported as `.development`
    /// even though it may also have a sandbox receipt.
    static var installKind: InstallKind {
        #if targetEnvironment(simulator)
        return .simulator
        #else
        if provisioningProfileExpiration() != nil {
            return .development
        }
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return .testFlight
        }
        return .appStore
        #endif
    }

    /// The date this build stops working, when that is knowable on device:
    /// - development / ad-hoc builds expire with their embedded provisioning
    ///   profile (`ExpirationDate`);
    /// - TestFlight builds expire 90 days after they were built.
    /// App Store builds don't expire, so this is `nil` for them.
    static var expirationDate: Date? {
        switch installKind {
        case .development:
            return provisioningProfileExpiration()
        case .testFlight:
            guard let built = buildDate else { return nil }
            return Calendar.current.date(byAdding: .day, value: 90, to: built)
        case .appStore, .simulator:
            return nil
        }
    }

    /// Best-effort build timestamp: the modification date of the main executable,
    /// stamped when the binary was linked. Used to derive the TestFlight 90-day window.
    private static var buildDate: Date? {
        guard let url = Bundle.main.executableURL,
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }

    /// Parses `ExpirationDate` out of the bundled `embedded.mobileprovision`, if any.
    /// The file is a CMS-signed blob with a plain-text XML plist inside; we slice the
    /// plist out by its delimiters (Latin-1 keeps byte offsets aligned) and decode it.
    /// App Store / TestFlight builds carry no embedded profile, so this returns `nil`.
    private static func provisioningProfileExpiration() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let raw = String(data: data, encoding: .isoLatin1),
              let start = raw.range(of: "<?xml"),
              let end = raw.range(of: "</plist>") else {
            return nil
        }
        let plistSlice = String(raw[start.lowerBound..<end.upperBound])
        guard let plistData = plistSlice.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else {
            return nil
        }
        return plist["ExpirationDate"] as? Date
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @Binding var prefs: LabDisplayPreferences
    let allCodes: [CodeName]
    /// `true` when presented as a sheet (iPhone) — shows a Close button. `false`
    /// when hosted as the detail pane of the iPad sidebar, where the split view
    /// owns dismissal and a Close button would be out of place.
    var isModal = true
    @Environment(\.dismiss) private var dismiss
    @State private var browserURL: IdentifiedURL?
    @AppStorage(CloudSyncService.enabledKey) private var iCloudSyncEnabled = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    BuildInfoCard()
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowBackground(Color.clear)
                }

                Section("Dashboard") {
                    NavigationLink {
                        LabSortEditor(prefs: $prefs, allCodes: allCodes)
                    } label: {
                        SettingsRowLabel("Sort & Visibility",
                                         systemImage: "arrow.up.arrow.down", color: .blue)
                    }
                }

                Section {
                    Toggle(isOn: $iCloudSyncEnabled) {
                        SettingsRowLabel("iCloud Sync",
                                         systemImage: "arrow.triangle.2.circlepath", color: .blue)
                    }
                } footer: {
                    Text("""
                    Sync your dashboard layout — the card order, what you pin and hide, and your \
                    custom names — across your devices. Your lab values stay in Apple Health.
                    """)
                }

                Section("LOINC") {
                    NavigationLink {
                        LoincCatalogView()
                    } label: {
                        SettingsRowLabel("Browse Catalog",
                                         systemImage: "magnifyingglass", color: .indigo)
                    }
                    NavigationLink {
                        LoincLicenseView()
                    } label: {
                        SettingsRowLabel("LOINC License", systemImage: "doc.text", color: .teal)
                    }
                    if !LoincDirectory.shared.version.isEmpty {
                        LabeledContent {
                            Text(verbatim: LoincDirectory.shared.version)
                        } label: {
                            SettingsRowLabel("Version", systemImage: "number.square", color: .gray)
                        }
                    }
                }

                Section("About") {
                    LabeledContent {
                        Text(AppInfo.branch)
                    } label: {
                        SettingsRowLabel("Branch",
                                         systemImage: "arrow.triangle.branch", color: .orange)
                    }
                    LabeledContent {
                        Text(AppInfo.commit)
                    } label: {
                        SettingsRowLabel("Commit", systemImage: "number", color: .purple)
                    }
                    NavigationLink {
                        LicenseView()
                    } label: {
                        SettingsRowLabel("License", systemImage: "doc.text", color: .pink)
                    }
                }

                Section {
                    SettingsRowLabel("Not Medical Advice",
                                     systemImage: "cross.case", color: .red)
                } footer: {
                    Text("""
                    LabImporter is not a medical device and does not provide medical advice, \
                    diagnosis, or treatment. Extracted values may be inaccurate or incomplete — \
                    always verify them against your original report. Never make medical decisions \
                    based on this app; consult a qualified healthcare professional about your results.
                    """)
                }

                Section {
                    if let repository = AppInfo.repositoryURL {
                        linkRow("View on GitHub",
                                systemImage: "chevron.left.forwardslash.chevron.right",
                                color: .gray, url: repository)
                    }
                    if let newIssue = AppInfo.newIssueURL {
                        linkRow("Report an Issue",
                                systemImage: "exclamationmark.bubble",
                                color: .red, url: newIssue)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if isModal {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(role: .close) { dismiss() }
                    }
                }
            }
            .sheet(item: $browserURL) { item in
                SafariView(url: item.url)
                    .ignoresSafeArea()
            }
        }
    }

    /// A standard settings row that opens a web URL in the in-app browser, with a
    /// trailing external-link glyph to signal it leaves the app.
    private func linkRow(_ titleKey: LocalizedStringKey,
                         systemImage: String,
                         color: Color,
                         url: URL) -> some View {
        Button {
            browserURL = IdentifiedURL(url: url)
        } label: {
            HStack {
                SettingsRowLabel(titleKey, systemImage: systemImage, color: color)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - SettingsRowLabel

/// A list-row label with a rounded, color-filled icon tile in the style of the
/// iOS Settings app — used to give the otherwise plain settings screens some life.
struct SettingsRowLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    let color: Color

    init(_ title: LocalizedStringKey, systemImage: String, color: Color) {
        self.title = title
        self.systemImage = systemImage
        self.color = color
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(color.gradient, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
    }
}

// MARK: - BuildInfoCard

/// A summary card — app icon, name, version/build, where the build came from, and
/// when it expires — shown at the top of Settings. Mirrors the material-card look
/// of the review and history headers, and computes everything on device (no
/// network), matching the app's no-server design.
struct BuildInfoCard: View {
    private var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "LabImporter"
    }

    var body: some View {
        HStack(spacing: 14) {
            icon

            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: displayName)
                    .font(.headline)
                Text("Version \(AppInfo.version) (\(AppInfo.build))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let expiry = AppInfo.expirationDate {
                    Label {
                        Text("Expires \(expiry.formatted(date: .abbreviated, time: .omitted))")
                    } icon: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            buildTypeBadge
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
        )
    }

    /// The real app icon when it resolves, falling back to a tinted glyph tile so
    /// the card still reads well in previews or odd build configurations.
    @ViewBuilder private var icon: some View {
        if let image = AppInfo.icon {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)
        } else {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(Color.accentColor.gradient)
                .frame(width: 56, height: 56)
                .overlay(
                    Image(systemName: "cross.case.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                )
        }
    }

    @ViewBuilder private var buildTypeBadge: some View {
        switch AppInfo.installKind {
        case .appStore: badge("App Store", color: .blue)
        case .testFlight: badge("TestFlight", color: .indigo)
        case .development: badge("Development", color: .orange)
        case .simulator: badge("Simulator", color: .gray)
        }
    }

    private func badge(_ title: LocalizedStringKey, color: Color) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
    }
}

// MARK: - In-app browser

/// Wraps a `URL` so it can drive a `.sheet(item:)` presentation.
struct IdentifiedURL: Identifiable {
    let id = UUID()
    let url: URL
}

/// SwiftUI wrapper around `SFSafariViewController` for in-app web browsing.
struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

// MARK: - CodeName

struct CodeName: Identifiable {
    var id: String { code }
    let code: String
    let name: String
}

// MARK: - LicenseView

/// The app's MIT license, read from the bundled `LICENSE` file via `AppInfo`.
struct LicenseView: View {
    var body: some View {
        LicenseDocumentView(title: "License", text: AppInfo.licenseText)
    }
}

// MARK: - Previews

#Preview("Settings") {
    @Previewable @State var prefs = LabDisplayPreferences()
    SettingsView(prefs: $prefs, allCodes: CodeName.sampleCodes)
}

#Preview("Build Info Card") {
    BuildInfoCard()
        .padding()
        .background(Color(.systemGroupedBackground))
}
