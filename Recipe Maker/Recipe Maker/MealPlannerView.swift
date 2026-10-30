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
        .tint(MealTheme.accent)
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
    @State private var recognitionTask: IngredientRecognitionTask?
    @State private var scanID: UUID?
    @State private var scanProgress = 0.0
    @ScaledMetric(relativeTo: .subheadline) private var suggestionWidth: CGFloat = 140
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Scan ingredients")
                                .font(.system(.title2, design: .serif, weight: .semibold))
                            Text("Keep each item visible.")
                                .font(.subheadline).foregroundStyle(MealTheme.cream.opacity(0.85))
                        }.fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "viewfinder")
                            .font(.system(size: 34, weight: .ultraLight))
                            .overlay(Image(systemName: "leaf.fill").font(.system(size: 17)))
                            .accessibilityHidden(true)
                    }.foregroundStyle(MealTheme.cream)
                    if dynamicTypeSize > .large {
                        VStack(spacing: 10) { cameraButton; libraryButton }
                    } else {
                        HStack(spacing: 10) { cameraButton; libraryButton }
                    }
                    if isAnalyzing {
                        HStack(spacing: 16) {
                            ProgressView("Scanning…", value: scanProgress).tint(MealTheme.cream)
                                .foregroundStyle(MealTheme.cream).accessibilityIdentifier("recognitionProgress")
                            Button("Cancel", action: cancelRecognition)
                                .foregroundStyle(MealTheme.cream).frame(minWidth: 44, minHeight: 44)
                                .buttonStyle(.borderless).accessibilityIdentifier("cancelRecognition")
                        }
                    }
                }.padding(22)
                    .background(MealTheme.forest, in: RoundedRectangle(cornerRadius: 26))
                    .listRowInsets(EdgeInsets()).listRowBackground(Color.clear).listRowSeparator(.hidden)
            }
            Section {
                HStack(alignment: .center, spacing: 8) {
                    Image(systemName: "plus").foregroundStyle(MealTheme.accent).accessibilityHidden(true)
                    TextField("Ingredient names", text: $input,
                              prompt: Text("Add an ingredient").foregroundColor(MealTheme.secondary), axis: .vertical)
                        .lineLimit(1...3).textInputAutocapitalization(.never).frame(minHeight: 44)
                        .submitLabel(.done).focused($inputFocused)
                        .accessibilityLabel("Ingredient names").accessibilityIdentifier("ingredientInput")
                        .accessibilityHint("Separate ingredient names with commas")
                        .onSubmit(addInput)
                    Button(action: addInput) {
                        Image(systemName: "arrow.up.circle.fill").font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                    }.buttonStyle(.borderless).accessibilityLabel("Add ingredients")
                        .accessibilityIdentifier("addIngredients")
                        .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .opacity(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.35 : 1)
                }.listRowBackground(MealTheme.surface).listRowSeparator(.hidden)
                if !model.suggestedIngredients.isEmpty {
                    LazyVGrid(columns: [GridItem(dynamicTypeSize.isAccessibilitySize ? .flexible() : .adaptive(minimum: suggestionWidth), alignment: .leading)], alignment: .leading) {
                        ForEach(model.suggestedIngredients, id: \.self) { name in
                            Button { model.add(name) } label: {
                                Label(name.capitalized, systemImage: "plus")
                                    .font(.subheadline.weight(.medium))
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(.horizontal, 12).padding(.vertical, 8).frame(minHeight: 44)
                                    .background(MealTheme.soft, in: Capsule())
                            }.buttonStyle(.plain).foregroundStyle(MealTheme.accent)
                                .accessibilityLabel("Add \(name)").accessibilityIdentifier("suggestion-\(name)")
                        }
                    }.padding(.bottom, 6).listRowBackground(MealTheme.surface).listRowSeparator(.hidden)
                }
            } footer: {
                if inputFocused { Text("Separate names with commas.").foregroundStyle(MealTheme.secondary) }
            }

            Section {
                if model.state.pantry.isEmpty {
                    MealEmptyState(title: "A fresh start", message: "Add ingredients. Find your next meal.",
                                   symbol: "basket", identifier: "emptyPantry")
                        .listRowBackground(Color.clear).listRowSeparator(.hidden)
                } else {
                    ForEach(model.state.pantry.sorted(), id: \.self) { name in
                        Label(name.capitalized, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(MealTheme.ink).padding(.vertical, 4)
                            .accessibilityIdentifier("pantry-\(name)")
                            .listRowBackground(MealTheme.surface)
                    }.onDelete { offsets in
                        let sorted = model.state.pantry.sorted()
                        for index in offsets { model.remove(sorted[index]) }
                    }
                }
            } header: {
                HStack {
                    Text("In your pantry").font(.system(.title3, design: .serif, weight: .semibold))
                    Spacer()
                    Text("\(model.state.pantry.count)").font(.subheadline.monospacedDigit())
                }.textCase(nil).foregroundStyle(MealTheme.ink)
            }
        }
        .listStyle(.insetGrouped).listSectionSpacing(20).mealSurface()
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !model.state.pantry.isEmpty && !inputFocused {
                Button(action: findRecipes) {
                    HStack { Text("Find recipes"); Spacer(); Image(systemName: "arrow.right") }
                }.buttonStyle(MealActionStyle()).accessibilityIdentifier("findRecipes")
                    .frame(maxWidth: 680).padding(.horizontal, 20).padding(.vertical, 10)
                    .frame(maxWidth: .infinity).background(MealTheme.background)
            }
        }
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
        .sheet(isPresented: $showAbout) { AboutView(model: model) }
        .onDisappear(perform: cancelRecognition)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { cancelRecognition() }
        }
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

    private var cameraButton: some View {
        Button(action: openCamera) { Label("Camera", systemImage: "camera.fill") }
            .buttonStyle(MealActionStyle(prominent: false))
            .disabled(isAnalyzing || isRequestingCamera).accessibilityIdentifier("takePhoto")
            .accessibilityLabel("Take photo")
    }

    private var libraryButton: some View {
        Button { inputFocused = false; picker = .library } label: { Label("Photos", systemImage: "photo") }
            .buttonStyle(MealActionStyle(prominent: false))
            .disabled(isAnalyzing || isRequestingCamera).accessibilityIdentifier("choosePhoto")
            .accessibilityLabel("Choose photo")
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
        pendingPhoto = nil
        pendingError = nil
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
        let id = UUID()
        scanID = id
        scanProgress = 0
        isAnalyzing = true
        recognitionTask = recognizer.recognize(cgImage, orientation: .up, progress: { value in
            if scanID == id { scanProgress = value }
        }) { result in
            guard scanID == id else { return }
            scanID = nil
            recognitionTask = nil
            isAnalyzing = false
            switch result {
            case .success(let recognition):
                review = PhotoReview(image: UIImage(cgImage: cgImage), result: recognition)
            case .failure:
                // Preserve the photo and a manual path even if Vision is unavailable.
                review = PhotoReview(image: UIImage(cgImage: cgImage), result: RecognitionResult(candidates: [], source: ""),
                                     message: "Recognition unavailable. Add a name below.")
            }
        }
    }

    private func cancelRecognition() {
        scanID = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        isAnalyzing = false
        scanProgress = 0
    }
}
