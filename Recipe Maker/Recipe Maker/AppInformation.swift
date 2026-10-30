import SwiftUI

enum AppInformation {
    static var privacyURL: URL? { publishedURL(for: "MealPlannerPrivacyPolicyURL") }
    static var supportURL: URL? { publishedURL(for: "MealPlannerSupportURL") }
    static var version: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    private static func publishedURL(for key: String) -> URL? {
        guard let text = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              let url = URL(string: text), url.scheme == "https", let host = url.host,
              !host.isEmpty, url.user == nil, url.password == nil else { return nil }
        return url
    }
}

struct AboutView: View {
    @ObservedObject var model: PlannerModel
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDeletion = false
    @State private var deletionFailed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "leaf.fill").font(.largeTitle).foregroundStyle(MealTheme.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Meal Planner").font(.system(.title2, design: .serif, weight: .semibold))
                            Text("Cook with what you have.").font(.subheadline).foregroundStyle(MealTheme.secondary)
                        }
                    }.padding(.vertical, 8)
                }.listRowBackground(MealTheme.surface)
                Section("Privacy & support") {
                    NavigationLink { PrivacyPolicyView() } label: {
                        Label("Privacy policy", systemImage: "hand.raised")
                    }.accessibilityIdentifier("privacyPolicy")
                    if let url = AppInformation.supportURL {
                        Link(destination: url) { Label("Get support", systemImage: "questionmark.circle") }
                    }
                    Label("Offline. No account or tracking.", systemImage: "lock")
                        .font(.subheadline).foregroundStyle(MealTheme.secondary)
                }.listRowBackground(MealTheme.surface)
                Section("Help") {
                    DisclosureGroup("Photo tips") {
                        Text("Use good lighting and keep each ingredient visible. The scan checks several parts of your photo, but can miss small, covered, or packaged foods. Select only what you see, and type any missing names.")
                            .font(.subheadline).foregroundStyle(MealTheme.secondary)
                    }
                    DisclosureGroup("Before you cook") {
                        Text("Pantry matching checks names, not amounts or freshness. Check quantities and package labels. Dietary filters depend on the ingredients you use and do not verify allergens.")
                            .font(.subheadline).foregroundStyle(MealTheme.secondary)
                        Text("Water is assumed available. Enable pantry staples in Filters to also count oil, salt, and pepper.")
                            .font(.subheadline).foregroundStyle(MealTheme.secondary)
                    }
                }.listRowBackground(MealTheme.surface)
                Section {
                    Button("Delete all app data", role: .destructive) { confirmDeletion = true }
                        .accessibilityIdentifier("deleteAppData")
                } header: { Text("Your data") }
                footer: { Text("Remove pantry, favorites, filters, and recovery backups.") }
                Section { Text("Meal Planner · \(AppInformation.version)").foregroundStyle(.secondary) }
            }
            .mealSurface()
            .navigationTitle("About").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Delete all app data?", isPresented: $confirmDeletion, titleVisibility: .visible) {
                Button("Delete all data", role: .destructive) {
                    if model.deleteAllData() { dismiss() }
                    else { deletionFailed = true }
                }
            } message: {
                Text("This removes your pantry, saved recipes, filters, and recovery backups from this device. It cannot be undone. Your photo library is unaffected.")
            }
            .alert("Couldn't delete data", isPresented: $deletionFailed) {
                Button("OK", role: .cancel) {}
            } message: { Text(model.storageMessage ?? "Please try again.") }
        }
    }
}

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section {
                Text("Meal Planner is designed to work on your device without an account. The app has no advertising, analytics, tracking, or developer-operated server.")
            }
            Section("Photos and camera") {
                Text("Camera access is requested only when you choose Take photo. You can decline and use manual entry or select an existing photo instead. The system photo picker gives the app only the image you choose.")
                Text("Photos are processed in memory using Apple's on-device image recognition. The app does not upload them or add them to your photo library, and releases its copy when you leave the review flow. Your original photos stay in your library.")
            }
            Section("What stays on your device") {
                Text("Your pantry ingredients, saved recipe identifiers, and filters are stored in the app's private storage so they are available next time. If you reset unreadable storage, the original file is kept locally as a recovery backup.")
                Text("This information stays until you change or delete it. Device backups managed by Apple may include app data, depending on your device settings.")
            }
            Section("Sharing and external links") {
                Text("Sharing a recipe or shopping list opens the system share sheet. Data is sent to another app or person only when you choose a destination and complete that action. The destination handles it under its own privacy practices.")
                Text("Opening a support or privacy website uses your browser. That website may receive standard connection information, such as your IP address, under its published policy.")
            }
            Section("Your choices") {
                Text("Remove individual pantry ingredients and saved recipes at any time. About Meal Planner → Delete all app data removes your pantry, favorites, filters, and local recovery backups. It does not delete your original photos or copies you have shared.")
                Text("You can revoke camera permission in Settings. Delete the app to remove its local storage. Manage existing device backups separately in your Apple device or iCloud settings.")
            }
            if let url = AppInformation.privacyURL {
                Section { Link("Read the published privacy policy", destination: url) }
            }
            if let url = AppInformation.supportURL {
                Section { Link("Contact support about privacy", destination: url) }
            }
        }
        .mealSurface()
        .navigationTitle("Privacy policy").navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("privacyPolicyScreen")
    }
}
