import SwiftUI

struct RecipeListView: View {
    @ObservedObject var model: PlannerModel
    let savedOnly: Bool
    @State private var query = ""
    @State private var showFilters = false

    private var matches: [RecipeMatch] {
        let recipes = savedOnly ? model.recipes.filter { model.state.favorites.contains($0.id) } : model.recipes
        var preferences = savedOnly ? RecipePreferences() : model.state.preferences
        preferences.assumeStaples = model.state.preferences.assumeStaples
        return RecipeMatcher.recommendations(in: recipes, pantry: model.state.pantry, preferences: preferences, query: query)
    }

    private var filtered: Bool {
        let p = model.state.preferences
        return p.diet != .any || p.maximumMinutes != 0 || p.readyOnly
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(savedOnly ? "The keepers." : "What sounds good?")
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                    if !savedOnly && filtered {
                        Text(filterSummary).font(.caption.weight(.medium)).foregroundStyle(Color.accentColor)
                    }
                }.padding(.vertical, 8).listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 12, trailing: 0))
            }
            if matches.isEmpty {
                ContentUnavailableView {
                    Label(savedOnly && model.state.favorites.isEmpty ? "Your favorites live here" : "No recipes found",
                          systemImage: savedOnly ? "heart" : "magnifyingglass")
                } description: {
                    Text(savedOnly && model.state.favorites.isEmpty
                         ? "Open any recipe and tap the heart to save it for another day."
                         : "Try another search or loosen your filters to see more ideas.")
                } actions: {
                    if !query.isEmpty { Button("Clear search") { query = "" } }
                    if !savedOnly && filtered { Button("Reset filters") { resetFilters() } }
                }.listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(matches) { match in
                        NavigationLink(value: match.recipe.id) {
                            RecipeRow(match: match, saved: model.state.favorites.contains(match.id))
                        }.accessibilityIdentifier("recipe-\(match.id)")
                    }
                } header: {
                    Text("\(matches.count) \(matches.count == 1 ? "recipe" : "recipes") · \(savedOnly ? "your collection" : "closest pantry matches first")")
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(savedOnly ? "Saved recipes" : "Recipes").navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Recipe or ingredient")
        .navigationDestination(for: String.self) { id in
            if let recipe = model.recipes.first(where: { $0.id == id }) { RecipeDetailView(model: model, recipe: recipe) }
        }
        .toolbar {
            if !savedOnly {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Label("Filters", systemImage: filtered ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }.accessibilityIdentifier("recipeFilters")
                }
            }
        }
        .sheet(isPresented: $showFilters) { RecipeFiltersView(model: model) }
    }

    private var subtitle: String {
        if savedOnly { return "A little collection of meals you'll want to make again." }
        if model.state.pantry.isEmpty { return "Explore simple meals, or add pantry ingredients to find your closest matches." }
        return "Simple meals, sorted around the ingredients you already have."
    }

    private var filterSummary: String {
        let p = model.state.preferences
        var parts: [String] = []
        if p.diet != .any { parts.append(p.diet.title) }
        if p.maximumMinutes > 0 { parts.append("Up to \(p.maximumMinutes) min") }
        if p.readyOnly { parts.append("All ingredients on hand") }
        return parts.joined(separator: " · ")
    }

    private func resetFilters() {
        var preferences = RecipePreferences()
        preferences.assumeStaples = model.state.preferences.assumeStaples
        model.updatePreferences(preferences)
    }
}

private struct RecipeRow: View {
    let match: RecipeMatch
    let saved: Bool
    @ScaledMetric(relativeTo: .title) private var symbolSize: CGFloat = 38

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(match.recipe.symbol).font(.system(size: symbolSize))
                .padding(10).background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(match.recipe.title).font(.headline).foregroundStyle(.primary)
                Text(match.recipe.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(3)
                Text("\(match.recipe.minutes) min · \(match.recipe.servings) \(match.recipe.servings == 1 ? "serving" : "servings")")
                    .font(.caption).foregroundStyle(.secondary)
                Label(match.isReady ? "All ingredients on hand" : "\(match.available.count) of \(match.recipe.ingredients.count) ingredients on hand",
                      systemImage: match.isReady ? "checkmark.circle.fill" : "basket")
                    .font(.caption.weight(.medium)).foregroundStyle(match.isReady ? Color.accentColor : .secondary)
                if saved { Label("Saved", systemImage: "heart.fill").font(.caption).foregroundStyle(Color.accentColor) }
            }
        }.padding(.vertical, 10).accessibilityElement(children: .combine)
    }
}

struct RecipeFiltersView: View {
    @ObservedObject var model: PlannerModel
    @Environment(\.dismiss) private var dismiss

    private func preference<Value>(_ path: WritableKeyPath<RecipePreferences, Value>) -> Binding<Value> {
        Binding(get: { model.state.preferences[keyPath: path] }, set: { value in
            var preferences = model.state.preferences
            preferences[keyPath: path] = value
            model.updatePreferences(preferences)
        })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Make it yours") {
                    Picker("Diet", selection: preference(\.diet)) {
                        ForEach(Diet.allCases) { diet in Text(diet.title).tag(diet) }
                    }.accessibilityIdentifier("dietFilter")
                    Picker("Cooking time", selection: preference(\.maximumMinutes)) {
                        Text("Any time").tag(0)
                        Text("15 minutes or less").tag(15)
                        Text("30 minutes or less").tag(30)
                        Text("45 minutes or less").tag(45)
                    }
                    Toggle("All ingredients on hand", isOn: preference(\.readyOnly))
                        .accessibilityIdentifier("readyOnlyFilter")
                }
                Section {
                    Toggle("I have pantry staples", isOn: preference(\.assumeStaples))
                        .accessibilityIdentifier("staplesFilter")
                } header: { Text("Pantry staples") }
                footer: { Text("Count olive oil, salt, and black pepper as available. Everything else must be in your pantry. Check amounts before cooking.") }
                Section {
                    Button("Reset all filters") { model.updatePreferences(RecipePreferences()) }
                } footer: { Text("Filters are saved on this device. Your Saved tab always shows your full collection. Dietary labels depend on using the ingredient types specified in each recipe.") }
            }
            .navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RecipeDetailView: View {
    @ObservedObject var model: PlannerModel
    let recipe: Recipe
    @State private var completedSteps: Set<Int> = []

    private var match: RecipeMatch { model.match(recipe) }
    private var isSaved: Bool { model.state.favorites.contains(recipe.id) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    Text(recipe.symbol).font(.system(size: 64)).accessibilityHidden(true)
                    Text(recipe.title).font(.system(.largeTitle, design: .rounded, weight: .bold))
                        .accessibilityAddTraits(.isHeader)
                    Text(recipe.summary).foregroundStyle(.secondary)
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { metadata }
                        VStack(alignment: .leading, spacing: 8) { metadata }
                    }.font(.subheadline.weight(.medium)).foregroundStyle(Color.accentColor)
                    Label(recipe.equipment, systemImage: "frying.pan").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.vertical, 12).listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
            Section {
                ForEach(recipe.ingredients) { ingredient in
                    ingredientRow(ingredient)
                }
            } header: { Text("Ingredients · \(recipe.servings) \(recipe.servings == 1 ? "serving" : "servings")") }
            footer: { Text("Pantry checks names, not quantities. Make sure you have enough of each ingredient.") }

            if !match.missing.isEmpty {
                Section {
                    ShareLink(item: shoppingText) {
                        Label("Share missing ingredients (\(match.missing.count))", systemImage: "square.and.arrow.up")
                    }.accessibilityIdentifier("shareShoppingList")
                } header: { Text("A quick shopping list") }
                footer: { Text("Send the ingredients you're missing to Notes, Messages, or someone shopping with you.") }
            }

            Section {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    Button {
                        if completedSteps.contains(index) { completedSteps.remove(index) }
                        else { completedSteps.insert(index) }
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: completedSteps.contains(index) ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(Color.accentColor).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("STEP \(index + 1)").font(.caption.weight(.bold)).tracking(1)
                                    .foregroundStyle(Color.accentColor)
                                Text(step).foregroundStyle(completedSteps.contains(index) ? .secondary : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.vertical, 10)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Step \(index + 1). \(step)")
                        .accessibilityValue(completedSteps.contains(index) ? "Completed" : "Not completed")
                        .accessibilityHint("Double tap to toggle completion")
                        .accessibilityIdentifier("cookingStep-\(index)")
                }
                if completedSteps.count == recipe.steps.count {
                    Label("Nice work. Enjoy your meal!", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(Color.accentColor)
                        .accessibilityIdentifier("cookingComplete")
                }
                if !completedSteps.isEmpty {
                    Button("Reset cooking checklist") { completedSteps.removeAll() }
                }
            } header: { Text("Let's cook · \(completedSteps.count)/\(recipe.steps.count)") }
            footer: { Text("Tap a step as you finish it. The checklist resets when you leave this recipe.") }
            Section {
                Label { Text(recipe.tip) } icon: { Image(systemName: "lightbulb") }
                    .font(.subheadline).padding(.vertical, 6)
            } header: { Text("One little tip") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Let's cook").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { model.toggleFavorite(recipe) } label: {
                    Image(systemName: isSaved ? "heart.fill" : "heart")
                }.accessibilityLabel(isSaved ? "Unsave recipe" : "Save recipe")
                    .accessibilityIdentifier("saveRecipe")
            }
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: recipeText) { Label("Share recipe", systemImage: "square.and.arrow.up") }
            }
        }
    }

    @ViewBuilder private var metadata: some View {
        Label("\(recipe.minutes) min", systemImage: "clock")
        Label("\(recipe.servings) \(recipe.servings == 1 ? "serving" : "servings")", systemImage: "person")
        if recipe.diet != .any { Label(recipe.diet.title, systemImage: "leaf") }
    }

    private func ingredientRow(_ ingredient: RecipeIngredient) -> some View {
        let inPantry = model.state.pantry.contains(ingredient.name)
        let assumed = !inPantry && model.state.preferences.assumeStaples && RecipeMatcher.staples.contains(ingredient.name)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: inPantry || assumed ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(inPantry || assumed ? Color.accentColor : .secondary)
                .padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name.capitalized).font(.body.weight(.medium))
                Text(ingredient.amount).font(.subheadline).foregroundStyle(.secondary)
                Text(inPantry ? "In your pantry" : (assumed ? "Assumed pantry staple" : "Add to your shopping list"))
                    .font(.caption).foregroundStyle(inPantry || assumed ? Color.accentColor : .secondary)
            }
        }.padding(.vertical, 4).accessibilityElement(children: .combine)
    }

    private var shoppingText: String {
        "Shopping list for \(recipe.title) (\(recipe.servings) servings)\n\n" +
        match.missing.map { "• \($0.name.capitalized): \($0.amount)" }.joined(separator: "\n")
    }

    private var recipeText: String {
        "\(recipe.title)\n\(recipe.minutes) minutes · \(recipe.servings) servings\n\(recipe.equipment)\n\nIngredients\n" +
        recipe.ingredients.map { "• \($0.name.capitalized): \($0.amount)" }.joined(separator: "\n") +
        "\n\nSteps\n" + recipe.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n\n") +
        "\n\nTip: \(recipe.tip)\n\nMade with Meal Planner"
    }
}
