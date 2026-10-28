PRAGMA foreign_keys = ON;
PRAGMA application_id = 0x4D504C4E;
PRAGMA user_version = 1;

CREATE TABLE catalog_metadata (
    key TEXT PRIMARY KEY NOT NULL,
    value TEXT NOT NULL
);

CREATE TABLE recipes (
    id TEXT PRIMARY KEY NOT NULL,
    title TEXT NOT NULL CHECK (length(trim(title)) > 0),
    summary TEXT NOT NULL CHECK (length(trim(summary)) > 0),
    symbol TEXT NOT NULL,
    minutes INTEGER NOT NULL CHECK (minutes > 0),
    servings INTEGER NOT NULL CHECK (servings > 0),
    diet TEXT NOT NULL CHECK (diet IN ('any', 'vegetarian', 'vegan')),
    equipment TEXT NOT NULL CHECK (length(trim(equipment)) > 0),
    tip TEXT NOT NULL
);

CREATE TABLE recipe_ingredients (
    recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position >= 0),
    name TEXT NOT NULL CHECK (length(trim(name)) > 0),
    amount TEXT NOT NULL CHECK (length(trim(amount)) > 0),
    PRIMARY KEY (recipe_id, position),
    UNIQUE (recipe_id, name)
);

CREATE TABLE recipe_steps (
    recipe_id TEXT NOT NULL REFERENCES recipes(id) ON DELETE CASCADE,
    position INTEGER NOT NULL CHECK (position >= 0),
    instruction TEXT NOT NULL CHECK (length(trim(instruction)) > 0),
    PRIMARY KEY (recipe_id, position)
);

CREATE INDEX recipe_ingredient_name ON recipe_ingredients(name, recipe_id);
CREATE INDEX recipe_diet_time ON recipes(diet, minutes, id);
