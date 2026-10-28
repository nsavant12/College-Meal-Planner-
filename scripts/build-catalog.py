#!/usr/bin/env python3
"""Validate editorial recipe data and atomically generate the bundled SQLite DB."""
import argparse
import json
import os
from pathlib import Path
import re
import sqlite3
import tempfile

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = ROOT / "Recipe Maker/Recipe Maker/Core/Resources/recipes.sqlite"


def validate(document):
    if not isinstance(document, dict):
        raise ValueError("Catalog document must be an object")
    version = document.get("catalogVersion")
    if type(version) is not int or version < 1:
        raise ValueError("catalogVersion must be a positive integer")
    recipes = document.get("recipes")
    if not isinstance(recipes, list) or not recipes:
        raise ValueError("recipes must be a nonempty list")
    ids = set()
    for recipe in recipes:
        if not isinstance(recipe, dict):
            raise ValueError("Each recipe must be an object")
        identifier = recipe.get("id", "")
        if not isinstance(identifier, str) or not re.fullmatch(r"[a-z0-9]+(?:-[a-z0-9]+)*", identifier) or identifier in ids:
            raise ValueError(f"Invalid or duplicate recipe id: {identifier!r}")
        ids.add(identifier)
        for key in ("title", "summary", "symbol", "equipment", "tip"):
            if not isinstance(recipe.get(key), str) or not recipe[key].strip():
                raise ValueError(f"{identifier}: {key} must be nonempty text")
        for key in ("minutes", "servings"):
            if type(recipe.get(key)) is not int or recipe[key] < 1:
                raise ValueError(f"{identifier}: {key} must be a positive integer")
        if recipe.get("diet") not in ("any", "vegetarian", "vegan"):
            raise ValueError(f"{identifier}: unrecognized diet")
        if not isinstance(recipe.get("ingredients"), list) or not recipe["ingredients"]:
            raise ValueError(f"{identifier}: ingredients must be nonempty")
        names = set()
        for ingredient in recipe["ingredients"]:
            if not isinstance(ingredient, dict):
                raise ValueError(f"{identifier}: each ingredient must be an object")
            name = ingredient.get("name", "")
            if not isinstance(name, str) or not name or name != " ".join(name.lower().split()) or len(name) > 60 or name in names:
                raise ValueError(f"{identifier}: invalid, noncanonical, or duplicate ingredient {name!r}")
            if not isinstance(ingredient.get("amount"), str) or not ingredient["amount"].strip():
                raise ValueError(f"{identifier}: each ingredient needs an amount")
            names.add(name)
        if not isinstance(recipe.get("steps"), list) or not recipe["steps"] or any(not isinstance(step, str) or not step.strip() for step in recipe["steps"]):
            raise ValueError(f"{identifier}: steps must contain nonempty instructions")
    return sorted(recipes, key=lambda recipe: recipe["id"])


def build(source, schema, output):
    document = json.loads(source.read_text(encoding="utf-8"))
    recipes = validate(document)
    output.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix="catalog-", suffix=".sqlite", dir=output.parent)
    os.close(descriptor)
    try:
        with sqlite3.connect(temporary) as database:
            database.executescript(schema.read_text(encoding="utf-8"))
            database.execute("INSERT INTO catalog_metadata VALUES (?, ?)", ("catalog_version", str(document["catalogVersion"])))
            for recipe in recipes:
                database.execute("INSERT INTO recipes VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                                 tuple(recipe[key] for key in ("id", "title", "summary", "symbol", "minutes", "servings", "diet", "equipment", "tip")))
                database.executemany("INSERT INTO recipe_ingredients VALUES (?, ?, ?, ?)",
                                     [(recipe["id"], i, item["name"], item["amount"]) for i, item in enumerate(recipe["ingredients"])])
                database.executemany("INSERT INTO recipe_steps VALUES (?, ?, ?)",
                                     [(recipe["id"], i, step) for i, step in enumerate(recipe["steps"])])
            if database.execute("PRAGMA foreign_key_check").fetchall():
                raise ValueError("Catalog has broken relationships")
            if database.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
                raise ValueError("Catalog integrity check failed")
        database.close()
        os.chmod(temporary, 0o644)
        os.replace(temporary, output)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print(f"Built {len(recipes)} recipes (catalog v{document['catalogVersion']}) → {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=ROOT / "Catalog/recipes.json")
    parser.add_argument("--schema", type=Path, default=ROOT / "Catalog/schema.sql")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    arguments = parser.parse_args()
    try:
        build(arguments.source, arguments.schema, arguments.output)
    except (ValueError, TypeError, KeyError, sqlite3.Error, OSError) as error:
        parser.exit(1, f"Catalog build failed: {error}\n")
