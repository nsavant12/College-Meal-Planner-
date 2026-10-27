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
        _selected = State(initialValue: Set(review.result.candidates.prefix(1).map(\.name)))
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
                        .frame(maxWidth: .infinity, maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 16))
                        .accessibilityLabel("Selected ingredient photo")
                        .listRowBackground(Color.clear)
                }
                if review.result.candidates.isEmpty {
                    Section {
                        Label("Let's name this one", systemImage: "pencil.line").font(.headline)
                        Text(review.message ?? "We couldn't confidently identify an ingredient. Enter its name below, or try another photo in better light.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(review.result.candidates) { candidate in
                            Button {
                                if selected.contains(candidate.name) { selected.remove(candidate.name) }
                                else { selected.insert(candidate.name) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selected.contains(candidate.name) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(Color.accentColor).font(.title2)
                                    Text(candidate.name.capitalized).foregroundStyle(.primary)
                                    Spacer()
                                    Text("\(Int(candidate.confidence * 100))%")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }.frame(minHeight: 44)
                            }.buttonStyle(.plain)
                                .accessibilityLabel("\(candidate.name), confidence score \(Int(candidate.confidence * 100)) percent")
                                .accessibilityValue(selected.contains(candidate.name) ? "Selected" : "Not selected")
                        }
                    } header: { Text("Does this look right?") }
                    footer: {
                        Text("These are possible labels, not a count of objects. Select only what you see. Confidence scores from \(review.result.source) aren't a guarantee.")
                    }
                }
                Section {
                    TextField("Ingredient names, separated by commas", text: $manual, axis: .vertical)
                        .textInputAutocapitalization(.never).lineLimit(1...3)
                        .accessibilityIdentifier("reviewIngredientInput")
                    if hasLongName { Text("Keep each ingredient name under 61 characters.").font(.caption).foregroundStyle(.red) }
                } header: { Text("Add or correct a name") }
                footer: { Text("Only confirmed names are saved. The photo is discarded when you leave this screen.") }
            }
            .navigationTitle("Review ingredients").navigationBarTitleDisplayMode(.inline)
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
