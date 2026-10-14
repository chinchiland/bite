// The two estimates that aren't a plate: a restaurant menu read from a photo, every dish on it
// with a typical portion; and a dish by its name, typed in search, as it is usually served. The
// words are the ones the app sends Claude (Bite/Services/ClaudeVision.swift) and the answers
// are read by Shared/Model/TypicalDish.swift: change all three together.

const dishProperties = {
  emoji: { type: "string", description: "One food emoji." },
  grams: { type: "number", description: "Grams of a typical portion." },
  kcal: { type: "number" },
  protein: { type: "number" },
  carbs: { type: "number" },
  fat: { type: "number" },
  fiber: { type: "number" },
  sugar: { type: "number" },
};
const dishRequired = ["emoji", "grams", "kcal", "protein", "carbs", "fat", "fiber", "sugar"];

export function menuPrompt(language: string): string {
  return `This photo shows a restaurant menu, for a calorie tracker. List every dish, side and drink you can read on it, in the menu's order, at most 60.

For each one give its name as the menu writes it, a short description only when the menu has one, its price as written or empty, and an estimate for the portion a place like this usually serves: the grams, the kcal, and the protein, carbs, fat, fiber and sugar in grams, with one fitting food emoji. Count the oil, butter, sauces and sides the dish normally comes with.

Give the restaurant's name when the menu shows it, with normal capitalization, or leave it empty. If the photo is not a menu, return no dishes.

Keep the dish names in the menu's own words, with normal capitalization. Write the descriptions in this language: ${language}.`;
}

export const menuSchema = {
  type: "object",
  properties: {
    restaurant: { type: "string", description: "The restaurant's name as the menu shows it, or empty." },
    dishes: {
      type: "array",
      items: {
        type: "object",
        properties: {
          name: { type: "string" },
          description: { type: "string", description: "A few words, or empty." },
          price: { type: "string", description: "As written on the menu, or empty." },
          ...dishProperties,
        },
        required: ["name", "description", "price", ...dishRequired],
        additionalProperties: false,
      },
    },
  },
  required: ["restaurant", "dishes"],
  additionalProperties: false,
};

// What was typed comes last, on its own line, as words to estimate and nothing else.
export function dishPrompt(name: string, language: string): string {
  return `For a calorie tracker, someone typed what they ate, below. Estimate one portion of it as it is usually served, at a restaurant or at home: the grams, the kcal, and the protein, carbs, fat, fiber and sugar in grams, with one fitting food emoji. Count the oil, sauces and sides it normally comes with.

When the words could mean several dishes, estimate the most common one and say which in its name. If they are not a food or a drink, set isFood to false.

Write the name capitalized like a sentence, in this language: ${language}.

What they typed: ${name}`;
}

export const dishSchema = {
  type: "object",
  properties: {
    title: { type: "string", description: "Short name of the dish, in the requested language." },
    isFood: { type: "boolean" },
    ...dishProperties,
  },
  required: ["title", "isFood", ...dishRequired],
  additionalProperties: false,
};
