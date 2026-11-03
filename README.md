# Meal Planner

An offline iPhone and iPad app for planning meals from ingredients you have. Scan a photo or enter ingredients, confirm your pantry, and browse 20 bundled recipes. The app stores pantry items, favorites, and preferences on-device; no account or API key is required.

## Run

Open `Recipe Maker/Recipe Maker.xcodeproj` in Xcode, select the **Recipe Maker** scheme, and run on an iPhone or iPad simulator. The deployment target is iOS/iPadOS 17.5. To run on a device, select your own signing team and bundle identifier.

Try adding `banana, oats, peanut butter`, then tap **Find recipes**. The system photo picker works without broad photo-library access. Camera permission is requested only when you use the camera; photos are processed on-device.

## Maintain recipes

Edit `Catalog/recipes.json`, keep existing recipe IDs stable, increment `catalogVersion`, and regenerate the bundled SQLite database:

```sh
python3 scripts/build-catalog.py
python3 scripts/test-catalog.py
bash scripts/test-core.sh
```

Commit the JSON and generated `Recipe Maker/Recipe Maker/Core/Resources/recipes.sqlite` together. The importer validates the data and replaces the database atomically. Schema changes also require repository compatibility tests.

## Test

```sh
python3 scripts/test-catalog.py
bash scripts/test-core.sh
python3 scripts/test-recognition-evaluation.py
python3 scripts/vision/test_benchmark.py
```

Run the iOS unit and UI tests with **Product → Test** in Xcode, or use an available simulator ID:

```sh
xcodebuild -showdestinations -project "Recipe Maker/Recipe Maker.xcodeproj" -scheme "Recipe Maker"
xcodebuild test -project "Recipe Maker/Recipe Maker.xcodeproj" -scheme "Recipe Maker" \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UDID' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

If necessary, prefix Xcode commands with `env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. Vision inference is unreliable on the installed simulator; its manual-entry failure path is tested there. Validate recognition, camera permissions, accessibility, and repeated scans on physical devices before release.

## Recognition

The default app uses Apple's on-device image classifier across the whole photo and overlapping regions. Suggestions require confirmation and may miss small, covered, or packaged items. An experimental detector and trained classifier were evaluated, but neither is bundled; default scans do not estimate counts or quantities. Freshness and allergen detection are not implemented.

Recipe matching uses ingredient names, not quantities or substitutions. Dietary filters depend on the listed recipe ingredients. The app has no cloud sync or nutrition estimates.

See [architecture](docs/ARCHITECTURE.md) for implementation details and [ML results](docs/VISION_RESULTS.md) for benchmarks, limitations, and reproduction commands. Photo fixtures have separate license notices in their test directory.
