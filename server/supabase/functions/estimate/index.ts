// Bite's photo estimates, with no key of your own: the app sends a small JPEG, this asks Gemini
// for the plate's foods and nutrition in the app's own JSON shape, and sends that back. No
// photo is kept. Every scan first passes private.take_scan, a ceiling per person, per network
// and for everyone, so a script can't run up the bill.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import postgres from "https://deno.land/x/postgresjs@v3.4.4/mod.js";
import { prompt, schema } from "./meal.ts";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { prepare: false });
// Chosen by the bench of 13 October 2026: the most accurate cheap model, no lean either way.
const MODEL = Deno.env.get("ESTIMATE_MODEL") ?? "gemini-3.1-flash-lite";
const FALLBACK = Deno.env.get("ESTIMATE_FALLBACK") ?? "gemini-3.8-flash";
const MAX_PHOTO = 3_000_000; // base64 characters, about 2.2 MB: the app sends 100 to 300 KB

type Answer = { ok: true; text: string; input: number; output: number } | { ok: false; status: number };

async function ask(model: string, jpeg: string, language: string, isLabel: boolean): Promise<Answer> {
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "x-goog-api-key": Deno.env.get("GEMINI_API_KEY") ?? "" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ inline_data: { mime_type: "image/jpeg", data: jpeg } }, { text: prompt(language, isLabel) }] }],
      generationConfig: { responseMimeType: "application/json", responseJsonSchema: schema, maxOutputTokens: 16000 },
    }),
    signal: AbortSignal.timeout(45_000),
  }).catch(() => null);
  if (!response?.ok) return { ok: false, status: response?.status ?? 0 };
  const data = await response.json().catch(() => null);
  const parts = data?.candidates?.[0]?.content?.parts ?? [];
  const text = parts.filter((p: { text?: string; thought?: boolean }) => p.text && !p.thought).map((p: { text: string }) => p.text).join("");
  const usage = data?.usageMetadata ?? {};
  try {
    JSON.parse(text);
  } catch {
    return { ok: false, status: 502 };
  }
  return { ok: true, text, input: usage.promptTokenCount ?? 0, output: (usage.candidatesTokenCount ?? 0) + (usage.thoughtsTokenCount ?? 0) };
}

async function hash(text: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("POST only", { status: 405 });

  // Who is asking: any session works, the anonymous one the app makes on first use included.
  const jwt = (request.headers.get("Authorization") ?? "").replace("Bearer ", "");
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return Response.json({ error: "signin" }, { status: 401 });

  const body = await request.json().catch(() => null);
  const jpeg = typeof body?.jpeg === "string" ? body.jpeg : "";
  if (jpeg.length === 0 || jpeg.length > MAX_PHOTO) return Response.json({ error: "photo" }, { status: 400 });
  const language = String(body?.language ?? "en").replace(/[^A-Za-z-]/g, "").slice(0, 12) || "en";
  const isLabel = body?.isLabel === true;

  // The network, as a salted hash: enough to count, never the address itself.
  const address = (request.headers.get("x-forwarded-for") ?? "").split(",")[0].trim();
  const network = await hash(`${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}:${address}`);
  const [taken] = await sql`select private.take_scan(${user.id}::uuid, ${network}) as result`;
  const result = taken.result as { id?: number; refused?: string };
  if (result.refused) return Response.json({ error: "limit", limit: result.refused }, { status: 429 });

  // One retry on the same model, then the fallback, so a hiccup at Google costs a second, not the scan.
  let used = MODEL;
  let answer = await ask(MODEL, jpeg, language, isLabel);
  if (!answer.ok) answer = await ask(MODEL, jpeg, language, isLabel);
  if (!answer.ok) {
    used = FALLBACK;
    answer = await ask(FALLBACK, jpeg, language, isLabel);
  }
  await sql`select private.finish_scan(${result.id!}, ${used}, ${answer.ok ? answer.input : null}, ${answer.ok ? answer.output : null}, ${answer.ok})`;
  if (!answer.ok) return Response.json({ error: "busy" }, { status: 503 });
  return new Response(answer.text, { headers: { "Content-Type": "application/json" } });
});
