#!/usr/bin/env python3
"""Regression checks for the catalog import pipeline and committed database."""
import contextlib
import copy
import importlib.util
import io
import json
from pathlib import Path
import sqlite3
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location("catalog_builder", ROOT / "scripts/build-catalog.py")
builder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(builder)


class CatalogImportTests(unittest.TestCase):
    def setUp(self):
        self.document = json.loads((ROOT / "Catalog/recipes.json").read_text())

    def test_bundled_database_matches_editorial_source_and_schema(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "recipes.sqlite"
            with contextlib.redirect_stdout(io.StringIO()):
                builder.build(ROOT / "Catalog/recipes.json", ROOT / "Catalog/schema.sql", output)
            with sqlite3.connect(output) as generated, sqlite3.connect(f"file:{builder.DEFAULT_OUTPUT}?mode=ro", uri=True) as bundled:
                self.assertEqual(list(generated.iterdump()), list(bundled.iterdump()), "Run python3 scripts/build-catalog.py after editing the source catalog")
                self.assertEqual(bundled.execute("PRAGMA foreign_key_check").fetchall(), [])
                self.assertEqual(bundled.execute("PRAGMA integrity_check").fetchone()[0], "ok")
                self.assertEqual(bundled.execute("PRAGMA user_version").fetchone()[0], 1)
                self.assertEqual(bundled.execute("PRAGMA application_id").fetchone()[0], 0x4D504C4E)

    def test_invalid_import_preserves_previous_database(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "recipes.sqlite"
            output.write_bytes(builder.DEFAULT_OUTPUT.read_bytes())
            before = output.read_bytes()
            self.document["recipes"].append(copy.deepcopy(self.document["recipes"][0]))
            source = Path(directory) / "invalid.json"
            source.write_text(json.dumps(self.document))
            with self.assertRaises(ValueError):
                builder.build(source, ROOT / "Catalog/schema.sql", output)
            self.assertEqual(output.read_bytes(), before)

    def test_incomplete_or_malformed_content_is_rejected(self):
        for key, value in [("minutes", -1), ("servings", True), ("steps", []), ("ingredients", []), ("diet", "unknown"), ("title", "")]:
            with self.subTest(field=key):
                document = copy.deepcopy(self.document)
                document["recipes"][0][key] = value
                with self.assertRaises(ValueError):
                    builder.validate(document)
        for malformed in [[], {"catalogVersion": 1, "recipes": [None]}]:
            with self.assertRaises(ValueError):
                builder.validate(malformed)

    def test_duplicate_or_noncanonical_ingredients_are_rejected(self):
        for name in [" TOMATO ", "a" * 61, ""]:
            with self.subTest(name=name):
                document = copy.deepcopy(self.document)
                document["recipes"][0]["ingredients"][0]["name"] = name
                with self.assertRaises(ValueError):
                    builder.validate(document)
        recipe = self.document["recipes"][0]
        recipe["ingredients"].append(copy.deepcopy(recipe["ingredients"][0]))
        with self.assertRaises(ValueError):
            builder.validate(self.document)


if __name__ == "__main__":
    unittest.main()
