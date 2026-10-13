// The words and the JSON shape of a photo estimate, kept exactly as the app sends them to Claude
// (Bite/Services/ClaudeVision.swift and Shared/Model/MealEstimate.swift), so both paths answer
// in the same shape and the app reads either one the same way. Change all three together.

export function prompt(language: string, isLabel: boolean): string {
  const task = isLabel
    ? "This photo shows a nutrition label or a food package. Read it for a calorie tracker: one item for one serving as the label states it, or 100 g when it gives no serving."
    : "This photo is for a calorie tracker. Estimate what one person is eating.";
  return `${task}

List each food or drink you can see as its own item, with the grams on the plate and the kcal, and the protein, carbs, fat, fiber and sugar in grams for that amount. Count cooking oil, butter, sauces and dressings you can see or that the dish normally contains. If the photo shows a nutrition label or a packaged product, use what it says.

Give the meal a short title and one fitting food emoji. Set confidence to low when portions are hidden or hard to judge. Use the note for the one thing most likely to change the number, in one short sentence, or leave it empty.

Ask about that same thing in doubt, so the person can settle it in one tap: a short question, and two or three short answers from least to most, each with the grams of one item for that answer. Set item to that item's index in items, 0 for the first. The grams you gave the item must be one of the answers, the likeliest, and never 0. When nothing is in doubt, leave the question empty and give no answers.

If there is no food in the photo, return no items and say so in the note.

Write the title, item names, note, question and answers in this language: ${language}.`;
}

const item = {
  type: "object",
  properties: {
    name: { type: "string" },
    emoji: { type: "string" },
    grams: { type: "number" },
    kcal: { type: "number" },
    protein: { type: "number" },
    carbs: { type: "number" },
    fat: { type: "number" },
    fiber: { type: "number" },
    sugar: { type: "number" },
  },
  required: ["name", "emoji", "grams", "kcal", "protein", "carbs", "fat", "fiber", "sugar"],
  additionalProperties: false,
};

const answer = {
  type: "object",
  properties: {
    label: { type: "string", description: "Two or three words, in the requested language." },
    grams: { type: "number", description: "Grams of the item for this answer." },
  },
  required: ["label", "grams"],
  additionalProperties: false,
};

const doubt = {
  type: "object",
  properties: {
    question: { type: "string", description: "A short question about the one thing most likely to change the number, or empty." },
    item: { type: "integer", description: "Index in items, 0 for the first, of the food the answers are about." },
    answers: { type: "array", items: answer, description: "Two or three answers from least to most, or none." },
  },
  required: ["question", "item", "answers"],
  additionalProperties: false,
};

export const schema = {
  type: "object",
  properties: {
    title: { type: "string", description: "Short name for the whole meal, in the requested language." },
    emoji: { type: "string", description: "One food emoji for the meal." },
    confidence: { type: "string", enum: ["high", "medium", "low"] },
    note: { type: "string", description: "One short sentence on what could change the estimate, or empty." },
    items: { type: "array", items: item },
    doubt,
  },
  required: ["title", "emoji", "confidence", "note", "items", "doubt"],
  additionalProperties: false,
};
