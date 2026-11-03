# Architecture

## Data

`Catalog/recipes.json` and `Catalog/schema.sql` define the editable recipe catalog. `scripts/build-catalog.py` validates them and atomically generates the bundled SQLite database. `RecipeCatalog` locates the database; `RecipeRepository` validates its identity, versions, integrity, and relationships, then reads recipes with parameterized queries. The app caches the resulting records for local search and ranking.

`PlannerState` stores ingredient names, favorite recipe IDs, and preferences separately as JSON in Application Support. `PlannerStore` writes atomically. A corrupt or newer file blocks writes until the user explicitly resets it; the original is backed up. Failed writes remain in memory and can be retried. Deleting app data removes the store and its backups.

`Ingredient` normalizes case, whitespace, and explicit aliases while preserving distinctions such as dairy versus plant milk. `RecipeMatcher` filters and ranks recipes by readiness, ingredient coverage, missing count, cooking time, and stable ID. Quantities and substitutions are not inferred.

## App and recognition

The storyboard hosts SwiftUI through `ViewController`. `PlannerModel` owns shared state; the pantry, recipe, review, and information views present it. The system picker provides only the selected photo. Image I/O downsamples library images, and camera images are resized and oriented before recognition.

`IngredientRecognizer` runs on a serial background queue. It publishes an initial whole-image result, then scans nine overlapping windows and up to three salient regions. `RecognitionPolicy` validates regions, rejects weak or unsupported labels, and merges repeated names without adding correlated scores. Users confirm every suggestion. Cancellation, backgrounding, and leaving Pantry suppress stale results; individual crop failures preserve earlier results.

An optional `IngredientClassifier.mlmodelc` can replace a regional classifier request when it returns a supported label with sufficient confidence. A separate optional `IngredientDetector.mlmodelc` contract accepts instance boxes and scores; `DetectionPolicy` validates boxes and removes duplicates before producing approximate visible counts. Neither experimental model is bundled. The pantry stores names, so counts are not persisted. See [ML results](VISION_RESULTS.md) before enabling either model.

## Boundaries and validation

Photos and predictions are not sent or retained by the app. The system picker avoids broad photo-library permission; camera permission is requested on use. There is no backend, analytics, or third-party runtime in the default app.

The Swift package tests the same core sources and SQLite resource used by iOS. Python tests cover catalog generation and recognition metrics; native tests cover image handling, orchestration, and UI flows. Real-photo Vision inference remains a physical-device check because the installed iOS simulator cannot reliably initialize the classifier.

Before release, check camera grant/denial, JPEG/HEIC and iCloud imports, cancellation and backgrounding, repeated-scan memory, VoiceOver, large text, and iPad layouts on hardware. A signed archive and distribution setup require the owner's signing team and identifiers.
