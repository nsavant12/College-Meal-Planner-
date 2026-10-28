# Recipe database

The app reads `Recipe Maker/Recipe Maker/Core/Resources/recipes.sqlite`. Recipes are data, not Swift source. `RecipeCatalog.swift` only locates the database; `RecipeRepository` owns SQLite queries and validates the database format.

`recipes.json` is the editable seed/import source. It is not parsed by the app. `schema.sql` defines normalized tables for recipes, ordered ingredients, ordered cooking steps, and catalog metadata, with primary keys, foreign keys, uniqueness constraints, and validation checks.

## Update the catalog

1. Edit `recipes.json`. Keep existing recipe IDs stable so users' saved recipes continue to resolve. Use canonical lowercase ingredient names consistent with the app's normalization rules.
2. Increment `catalogVersion` when publishing changed content.
3. Run `python3 scripts/build-catalog.py` from the repository root.
4. Run `python3 scripts/test-catalog.py` and `bash scripts/test-core.sh`.
5. Review and manually commit the source data and generated database together.

The importer validates all input before replacing the database. It builds in a temporary file, verifies relationships and integrity, and atomically replaces the output only on success. Failed imports leave the previous database intact. CI checks that the committed database matches the source and schema.

The importer also accepts `--source`, `--schema`, and `--output` paths for independent catalog validation.

## Schema and updates

The SQLite application ID is `0x4D504C4E` (MPLN), schema version is `PRAGMA user_version = 1`, and content version is stored separately in `catalog_metadata`. The repository rejects unrelated databases, unsupported schema versions, broken relationships, and incomplete recipe records.

The catalog is read-only in the signed app bundle. An app update replaces it; no migration of the user's pantry is needed because user data is stored separately. For a schema change, add support for that schema in the repository and update its compatibility tests together with the database. Do not simply increment `user_version` without a corresponding reader change.

Search and ID lookup bind user values as SQLite parameters. A fetch uses three ordered queries for recipes, ingredients, and steps, avoiding per-recipe queries. The app caches the loaded catalog for local ranking and filtering. This is appropriate for the current small offline catalog; a substantially larger catalog can use the repository's database search and pagination rather than loading everything.

There is no remote recipe service or synchronization layer. Adding recipes does not require changes to the app's views or compiling recipe objects into Swift. Shipping new catalog content currently means including the regenerated database in an app update.
