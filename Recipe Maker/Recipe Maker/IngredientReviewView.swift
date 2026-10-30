import SwiftUI
import UIKit

struct PhotoReview: Identifiable {
    let id = UUID()
    let image: UIImage
    let result: RecognitionResult
    var message: String?
}

struct IngredientReviewView: View {
    let review: PhotoReview
    let add: ([String]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<String>
    @State private var manual = ""

    init(review: PhotoReview, add: @escaping ([String]) -> Void) {
        self.review = review
        self.add = add
        // Each suggestion must be confirmed, including the highest-scored one.
        _selected = State(initialValue: [])
    }

    private var additions: [String] { Array(selected.union(Ingredient.parse(manual))).sorted() }
    private var hasLongName: Bool {
        manual.components(separatedBy: CharacterSet(charactersIn: ",\n"))
            .contains { Ingredient.normalize($0).count > 60 }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Image(uiImage: review.image).resizable().scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                        .accessibilityLabel("Selected ingredient photo")
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
                if review.result.candidates.isEmpty {
                    Text(review.message ?? "Name the ingredient below.")
                        .font(.subheadline).foregroundStyle(MealTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .listRowBackground(Color.clear)
                } else {
                    Section("Select what you see") {
                        ForEach(review.result.candidates) { candidate in
                            Button {
                                if selected.contains(candidate.name) { selected.remove(candidate.name) }
                                else { selected.insert(candidate.name) }
                            } label: {
                                HStack(spacing: 12) {
                                    Text(candidate.name.capitalized).foregroundStyle(MealTheme.ink)
                                    Spacer()
                                    Image(systemName: selected.contains(candidate.name) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(MealTheme.accent).font(.title2)
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).listRowBackground(MealTheme.surface)
                                .accessibilityLabel("Suggested ingredient, \(candidate.name)")
                                .accessibilityIdentifier("candidate-\(candidate.name)")
                                .accessibilityValue(selected.contains(candidate.name) ? "Selected" : "Not selected")
                        }
                    }
                }
                Section {
                    TextField("Ingredient names", text: $manual,
                              prompt: Text("Add or correct a name").foregroundColor(MealTheme.secondary), axis: .vertical)
                        .textInputAutocapitalization(.never).lineLimit(1...3).frame(minHeight: 44)
                        .accessibilityIdentifier("reviewIngredientInput")
                        .listRowBackground(MealTheme.surface)
                    if hasLongName { Text("60 characters per name, max.").font(.caption).foregroundStyle(.red) }
                } footer: { Text("Separate names with commas.") }
                Label("Photos stay on your device", systemImage: "lock")
                    .font(.caption).foregroundStyle(MealTheme.secondary).listRowBackground(Color.clear)
            }.listStyle(.insetGrouped).mealSurface()
            .navigationTitle("Confirm ingredients").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add \(additions.count)") { add(additions); dismiss() }
                        .fontWeight(.semibold).disabled(additions.isEmpty || hasLongName)
                        .accessibilityLabel("Add \(additions.count) confirmed ingredients")
                        .accessibilityIdentifier("confirmIngredients")
                }
            }
        }
    }
}
