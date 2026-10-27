import AVFoundation
import SwiftUI
import UIKit

struct MealPlannerView: View {
    @StateObject var model: PlannerModel
    @State private var selectedTab = 0
    @State private var showStorageReset = false

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                PantryView(model: model, findRecipes: { selectedTab = 1 })
            }
            .tabItem { Label("Pantry", systemImage: "carrot") }.tag(0)
            NavigationStack { RecipeListView(model: model, savedOnly: false) }
                .tabItem { Label("Recipes", systemImage: "fork.knife") }.tag(1)
            NavigationStack { RecipeListView(model: model, savedOnly: true) }
                .tabItem { Label("Saved", systemImage: "heart") }.tag(2)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let message = model.storageMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Changes aren't saved", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Text(message).font(.caption)
                    Button(model.needsStorageReset ? "Reset local storage…" : "Try saving again") {
                        if model.needsStorageReset { showStorageReset = true }
                        else { model.retrySave() }
                    }.font(.subheadline.bold())
                }
                .padding().frame(maxWidth: .infinity, alignment: .leading)
                .background(.regularMaterial)
            }
        }
        .confirmationDialog("Back up the old file and save this pantry?", isPresented: $showStorageReset,
                            titleVisibility: .visible) {
            Button("Back up and reset", role: .destructive) { model.resetStorage() }
        } message: {
            Text("The unreadable file will be kept as a backup on this device. Your current pantry and saved recipes will become the new saved state.")
        }
    }
}

private struct PantryAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    var settings = false
}

struct PantryView: View {
    @ObservedObject var model: PlannerModel
    let findRecipes: () -> Void
    @State private var input = ""
    @State private var picker: PhotoSource?
    @State private var pendingPhoto: UIImage?
    @State private var pendingError: Error?
    @State private var review: PhotoReview?
    @State private var isAnalyzing = false
    @State private var isRequestingCamera = false
    @State private var alert: PantryAlert?
    @State private var showClear = false
    @State private var showAbout = false
    @FocusState private var inputFocused: Bool
    @State private var recognizer = IngredientRecognizer()

    var body: some View {
        List {
            Section {
                hero
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
            }
            Section {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Start with what you have", systemImage: "camera.viewfinder")
                        .font(.headline)
                    Text("Photograph one ingredient at a time, then check the suggestion before adding it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { cameraButton; libraryButton }
                        VStack(alignment: .leading, spacing: 12) { cameraButton; libraryButton }
                    }
                    if isAnalyzing {
                        ProgressView("Looking for ingredients…")
                            .font(.subheadline).accessibilityIdentifier("recognitionProgress")
                    }
                }.padding(.vertical, 8)
            }
            Section {
                HStack(alignment: .top) {
                    TextField("e.g. tomatoes, pasta, spinach", text: $input, axis: .vertical)
                        .lineLimit(1...3).textInputAutocapitalization(.never)
                        .submitLabel(.done).focused($inputFocused)
                        .accessibilityLabel("Ingredient names").accessibilityIdentifier("ingredientInput")
                        .onSubmit(addInput)
                    Button(action: addInput) { Image(systemName: "plus.circle.fill").font(.title2).frame(minWidth: 44, minHeight: 44) }
                        .buttonStyle(.borderless).accessibilityLabel("Add ingredients")
                        .accessibilityIdentifier("addIngredients")
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(Ingredient.suggestions.filter { !model.state.pantry.contains($0) }, id: \.self) { name in
                            Button { model.add(name) } label: {
                                Label(name.capitalized, systemImage: "plus").font(.subheadline)
                                    .padding(.horizontal, 12).frame(minHeight: 44)
                                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                            }.buttonStyle(.plain).foregroundStyle(Color.accentColor)
                                .accessibilityLabel("Add \(name)")
                        }
                    }
                }.listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 8, trailing: 16))
            } header: { Text("Or add by hand") }
            footer: { Text("Separate ingredients with commas. Amounts are checked when you cook.") }

            Section {
                if model.state.pantry.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Your next meal starts here.").font(.headline)
                        Text("Add a few ingredients above. We'll put the recipes closest to your pantry first.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 12)
                } else {
                    ForEach(model.state.pantry.sorted(), id: \.self) { name in
                        Label(name.capitalized, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                            .accessibilityIdentifier("pantry-\(name)")
                    }.onDelete { offsets in
                        let sorted = model.state.pantry.sorted()
                        for index in offsets { model.remove(sorted[index]) }
                    }
                    Button(action: findRecipes) {
                        HStack {
                            Text("Find my next meal").fontWeight(.semibold)
                            Spacer()
                            Image(systemName: "arrow.right")
                        }.padding(.vertical, 8)
                    }.accessibilityIdentifier("findRecipes")
                }
            } header: {
                Text("My pantry · \(model.state.pantry.count)")
            } footer: {
                if !model.state.pantry.isEmpty { Text("Swipe left to remove an ingredient when it runs out.") }
            }
        }
        .listStyle(.insetGrouped).scrollDismissesKeyboard(.interactively)
        .navigationTitle("Pantry").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { showAbout = true } label: { Image(systemName: "info.circle") }
                    .accessibilityLabel("About Meal Planner")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Clear pantry", systemImage: "trash", role: .destructive) { showClear = true }
                        .disabled(model.state.pantry.isEmpty)
                } label: { Image(systemName: "ellipsis.circle") }
                .accessibilityLabel("Pantry actions")
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { inputFocused = false }
            }
        }
        .fullScreenCover(item: $picker, onDismiss: processPhoto) { source in
            if source == .camera { CameraPicker(completion: photoPicked).ignoresSafeArea() }
            else { LibraryPicker(completion: photoPicked).ignoresSafeArea() }
        }
        .sheet(item: $review) { photo in
            IngredientReviewView(review: photo) { names in
                model.add(names.joined(separator: ","))
            }
        }
        .sheet(isPresented: $showAbout) { AboutView() }
        .confirmationDialog("Clear all pantry ingredients?", isPresented: $showClear, titleVisibility: .visible) {
            Button("Clear pantry", role: .destructive) { model.clearPantry() }
        } message: { Text("Your saved recipes will stay in your collection.") }
        .alert(item: $alert) { item in
            if item.settings {
                return Alert(title: Text(item.title), message: Text(item.message),
                             primaryButton: .default(Text("Open Settings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }, secondaryButton: .cancel())
            }
            return Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("LESS WASTE. MORE TASTE.").font(.caption.weight(.bold)).tracking(2).foregroundStyle(Color.accentColor)
            Text("Good food.\nAlready in your fridge.")
                .font(.system(.largeTitle, design: .rounded, weight: .bold)).fixedSize(horizontal: false, vertical: true)
            Text("Make something good with what you've got.")
                .font(.subheadline).foregroundStyle(.secondary)
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
    }

    private var cameraButton: some View {
        Button(action: openCamera) { Label("Take photo", systemImage: "camera.fill").frame(minHeight: 30) }
            .buttonStyle(.borderedProminent)
            .disabled(isAnalyzing || isRequestingCamera).accessibilityIdentifier("takePhoto")
    }

    private var libraryButton: some View {
        Button { inputFocused = false; picker = .library } label: {
            Label("Choose photo", systemImage: "photo").frame(minHeight: 30)
        }.buttonStyle(.bordered).disabled(isAnalyzing || isRequestingCamera)
            .accessibilityIdentifier("choosePhoto")
    }

    private func addInput() {
        let parts = input.components(separatedBy: CharacterSet(charactersIn: ",\n"))
        guard !parts.contains(where: { Ingredient.normalize($0).count > 60 }), !Ingredient.parse(input).isEmpty else {
            alert = PantryAlert(title: "Check the ingredient name", message: "Enter a name of up to 60 characters. Use commas to add more than one ingredient.")
            return
        }
        model.add(input)
        input = ""
        inputFocused = false
    }

    private func openCamera() {
        inputFocused = false
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            alert = PantryAlert(title: "No camera available", message: "Choose a photo from your library, or add ingredients by hand.")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: picker = .camera
        case .notDetermined:
            isRequestingCamera = true
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    isRequestingCamera = false
                    if granted { picker = .camera } else { cameraDenied() }
                }
            }
        case .denied: cameraDenied()
        case .restricted:
            alert = PantryAlert(title: "Camera is restricted", message: "This device doesn't allow camera access. You can choose an existing photo or add ingredients by hand.")
        @unknown default: cameraDenied()
        }
    }

    private func cameraDenied() {
        alert = PantryAlert(title: "Allow camera access", message: "Enable Camera in Settings to photograph ingredients. You can also choose an existing photo or add ingredients by hand.", settings: true)
    }

    private func photoPicked(_ result: Result<UIImage?, Error>) {
        switch result {
        case .success(let image): pendingPhoto = image
        case .failure(let error): pendingError = error
        }
        picker = nil
    }

    private func processPhoto() {
        if let error = pendingError {
            pendingError = nil
            alert = PantryAlert(title: "Couldn't open photo", message: error.localizedDescription)
            return
        }
        guard let image = pendingPhoto else { return }
        pendingPhoto = nil
        guard let cgImage = image.recognitionImage() else {
            alert = PantryAlert(title: "Couldn't open photo", message: PhotoError.unreadable.localizedDescription)
            return
        }
        isAnalyzing = true
        recognizer.recognize(cgImage, orientation: .up) { result in
            isAnalyzing = false
            switch result {
            case .success(let recognition):
                review = PhotoReview(image: UIImage(cgImage: cgImage), result: recognition)
            case .failure:
                // Preserve the photo and a manual path even if Vision is unavailable.
                review = PhotoReview(image: UIImage(cgImage: cgImage), result: RecognitionResult(candidates: [], source: ""),
                                     message: "Photo recognition isn't available right now. You can still name the ingredient below.")
            }
        }
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Small pantry. Big possibilities.", systemImage: "leaf.fill").font(.headline)
                    Text("Meal Planner helps you turn everyday ingredients into simple meals, with 20 recipes that work offline.")
                }
                Section("Your photos stay yours") {
                    Text("Recognition happens on this device. Photos are used only to suggest ingredients; the app doesn't upload or save them. No account, tracking, or subscription.")
                    Text("Your pantry, saved recipes, and filters are stored locally. Device backups may include this data.")
                }
                Section("A little help with recognition") {
                    Text("Use good lighting and photograph one ingredient at a time. Suggestions can be wrong or incomplete, so always review them. You can add any ingredient by hand.")
                }
                Section("Before you cook") {
                    Text("Pantry matching checks ingredient names, not amounts or freshness. Check quantities, food condition, and package labels before cooking. Dietary filters describe the recipes; they don't verify allergens in your products.")
                    Text("Water is assumed available. Oil, salt, and pepper are counted unless you enable pantry staples in Filters.")
                }
                Section { Text("Meal Planner · Version 1.0").foregroundStyle(.secondary) }
            }.navigationTitle("Made for your pantry").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
