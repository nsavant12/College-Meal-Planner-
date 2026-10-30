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
                HStack(alignment: .firstTextBaseline) {
                    Text(savedOnly ? "Your collection" : "On the menu")
                        .font(.system(.title, design: .serif, weight: .semibold))
                    Spacer()
                    MealBadge(title: "\(matches.count)")
                }.padding(.vertical, 4).listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                if !savedOnly && filtered {
                    Text(filterSummary).font(.caption.weight(.medium)).foregroundStyle(MealTheme.accent)
                        .listRowBackground(Color.clear).listRowInsets(EdgeInsets())
                }
            }
            if let message = model.catalogMessage {
                ContentUnavailableView {
                    Label("Recipe library unavailable", systemImage: "books.vertical")
                } description: {
                    Text(message)
                } actions: {
                    Button("Try again") { model.reloadCatalog() }
                }.listRowBackground(Color.clear)
            } else if matches.isEmpty {
                VStack(spacing: 16) {
                    MealEmptyState(title: savedOnly && model.state.favorites.isEmpty ? "No favorites yet" : "No matches",
                                   message: savedOnly && model.state.favorites.isEmpty ? "Tap a heart to save a recipe." : "Try another search or reset your filters.",
                                   symbol: savedOnly ? "heart" : "magnifyingglass",
                                   identifier: savedOnly ? "emptySaved" : "emptyRecipeResults")
                    if !query.isEmpty { Button("Clear search") { query = "" }.buttonStyle(MealActionStyle(prominent: false)) }
                    if !savedOnly && filtered { Button("Reset filters") { resetFilters() }.buttonStyle(MealActionStyle(prominent: false)) }
                }.mealCard().listRowBackground(Color.clear).listRowInsets(EdgeInsets()).listRowSeparator(.hidden)
            } else {
                Section {
                    ForEach(matches) { match in
                        NavigationLink(value: match.recipe.id) {
                            RecipeRow(match: match, saved: model.state.favorites.contains(match.id))
                        }.accessibilityIdentifier("recipe-\(match.id)")
                            .listRowBackground(MealTheme.surface).listRowSeparator(.hidden)
                    }
                }
            }
        }
        .listStyle(.insetGrouped).listRowSpacing(8).mealSurface()
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            if !dynamicTypeSize.isAccessibilitySize {
                Text(match.recipe.symbol).font(.system(size: 36))
                    .frame(width: 68, height: 80)
                    .background(match.isReady ? MealTheme.soft : MealTheme.gold, in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(match.recipe.title).font(.system(.headline, design: .serif, weight: .semibold))
                    .foregroundStyle(MealTheme.ink).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Label("\(match.recipe.minutes) min", systemImage: "clock")
                    if saved { Image(systemName: "heart.fill").accessibilityLabel("Saved") }
                }.font(.caption).foregroundStyle(MealTheme.secondary)
                Text(match.isReady ? "Ready to cook" : "\(match.missing.count) missing")
                    .font(.caption.weight(.semibold)).foregroundStyle(match.isReady ? MealTheme.accent : MealTheme.secondary)
            }
        }.padding(.vertical, 8).accessibilityElement(children: .combine)
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
                Section("Preferences") {
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
                footer: { Text("Count oil, salt, and pepper as available.") }
                Section {
                    Button("Reset all filters") { model.updatePreferences(RecipePreferences()) }
                }
            }
            .mealSurface()
            .navigationTitle("Filters").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

struct RecipeDetailView: View {
    @ObservedObject var model: PlannerModel
    let recipe: Recipe
    @State private var completedSteps: Set<Int> = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var match: RecipeMatch { model.match(recipe) }
    private var isSaved: Bool { model.state.favorites.contains(recipe.id) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        if !dynamicTypeSize.isAccessibilitySize {
                            Text(recipe.symbol).font(.system(size: 48))
                                .frame(width: 76, height: 88)
                                .background(MealTheme.gold, in: RoundedRectangle(cornerRadius: 22))
                                .accessibilityHidden(true)
                        }
                        Text(recipe.title).font(.system(.title, design: .serif, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                    }
                    Text(recipe.summary).font(.subheadline).foregroundStyle(MealTheme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) { metadata }
                    } else { HStack(spacing: 14) { metadata } }
                    Label(recipe.equipment, systemImage: "frying.pan").font(.caption).foregroundStyle(MealTheme.secondary)
                }.mealCard().listRowBackground(Color.clear).listRowInsets(EdgeInsets())
            }
            Section {
                ForEach(recipe.ingredients) { ingredient in
                    ingredientRow(ingredient).listRowBackground(MealTheme.surface)
                }
            } header: { Text("Ingredients") }
            footer: { Text("Check quantities before cooking.") }

            if !match.missing.isEmpty {
                Section {
                    ShareLink(item: shoppingText) {
                        Label("Shopping list · \(match.missing.count) missing", systemImage: "square.and.arrow.up")
                    }.accessibilityIdentifier("shareShoppingList")
                }.listRowBackground(MealTheme.soft)
            }

            Section {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    Button {
                        if completedSteps.contains(index) { completedSteps.remove(index) }
                        else { completedSteps.insert(index) }
                    } label: {
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: completedSteps.contains(index) ? "checkmark.circle.fill" : "circle")
                                .font(.title2).foregroundStyle(MealTheme.accent).padding(.top, 2)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Step \(index + 1)").font(.caption.weight(.semibold))
                                    .foregroundStyle(MealTheme.accent)
                                Text(step).foregroundStyle(completedSteps.contains(index) ? .secondary : .primary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }.padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Step \(index + 1). \(step)")
                        .accessibilityValue(completedSteps.contains(index) ? "Completed" : "Not completed")
                        .accessibilityHint("Double tap to toggle completion")
                        .accessibilityIdentifier("cookingStep-\(index)").listRowBackground(MealTheme.surface)
                }
                if completedSteps.count == recipe.steps.count {
                    Label("Enjoy your meal!", systemImage: "checkmark.seal.fill")
                        .font(.headline).foregroundStyle(MealTheme.accent)
                        .accessibilityIdentifier("cookingComplete")
                }
                if !completedSteps.isEmpty {
                    Button("Reset cooking checklist") { completedSteps.removeAll() }
                }
            } header: { Text("Let's cook · \(completedSteps.count)/\(recipe.steps.count)") }
            footer: { Text("Tap to check off each step.") }
            Section {
                DisclosureGroup("Kitchen tip") {
                    Text(recipe.tip).font(.subheadline).foregroundStyle(MealTheme.secondary)
                }.listRowBackground(MealTheme.surface)
            }
        }
        .listStyle(.insetGrouped).listRowSpacing(8).mealSurface()
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
        Label("\(recipe.minutes) min", systemImage: "clock").font(.caption.weight(.medium))
        Label("\(recipe.servings) \(recipe.servings == 1 ? "serving" : "servings")", systemImage: "person").font(.caption.weight(.medium))
        if recipe.diet != .any { Label(recipe.diet.title, systemImage: "leaf").font(.caption.weight(.medium)) }
    }

    private func ingredientRow(_ ingredient: RecipeIngredient) -> some View {
        let inPantry = model.state.pantry.contains(ingredient.name)
        let assumed = !inPantry && model.state.preferences.assumeStaples && RecipeMatcher.staples.contains(ingredient.name)
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: inPantry || assumed ? "checkmark.circle.fill" : "circle.dashed")
                .foregroundStyle(inPantry || assumed ? MealTheme.accent : .secondary)
                .padding(.top, 2).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(ingredient.name.capitalized).font(.body.weight(.medium))
                Text(ingredient.amount).font(.subheadline).foregroundStyle(MealTheme.secondary)
            }
            Spacer(minLength: 4)
            if assumed { MealBadge(title: "Staple") }
            else if !inPantry { MealBadge(title: "Missing", gold: true) }
        }.padding(.vertical, 4).accessibilityElement(children: .ignore)
            .accessibilityLabel("\(ingredient.name), \(ingredient.amount), \(inPantry ? "in pantry" : (assumed ? "assumed pantry staple" : "missing"))")
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
