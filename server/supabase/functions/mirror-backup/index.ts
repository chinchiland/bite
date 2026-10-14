// Your mirror, kept forever: a home for the photo files the app has already sealed on the
// phone. Bite only ever receives ciphertext it has no key to: the photos are sealed to a key
// that lives in the person's iCloud Keychain, so neither Bite nor anyone reading this storage
// can open them.
//
// There is no account. A phone proves which shelf is its own by signing each request with a
// key that also lives in its iCloud Keychain; the shelf's name is the SHA-256 of that public
// key, so nobody can read or write a shelf without the key, and a new iPhone on the same Apple
// Account finds its shelf again.
//
// POST /mirror-backup?op=put|get|delete|list&name=<file>
//   x-mirror-key        the signing public key, X9.63 (65 bytes), base64
//   x-mirror-time       seconds since 1970, within five minutes of now
//   x-mirror-signature  ECDSA P-256 SHA-256 over "op\nname\ntime\nsha256(body) in hex", raw r||s, base64
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const BUCKET = "mirror";
const MAX_FILE = 2_500_000; // a 1600 pixel photo is 300 to 800 KB
const MAX_FILES = 400; // a photo every four weeks is about 13 a year, two files each
const NAME = /^([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}(-t)?|manifest)\.bite$/;

function bytes(base64: string): Uint8Array<ArrayBuffer> | null {
  try {
    return Uint8Array.from(atob(base64), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}

async function hex(data: Uint8Array<ArrayBuffer>): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", data);
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("POST only", { status: 405 });
  const url = new URL(request.url);
  const op = url.searchParams.get("op") ?? "";
  const name = url.searchParams.get("name") ?? "";
  if (!["put", "get", "delete", "list"].includes(op)) return Response.json({ error: "op" }, { status: 400 });
  if (op !== "list" && !NAME.test(name)) return Response.json({ error: "name" }, { status: 400 });

  // The signature: this shelf's key, now.
  const key = bytes(request.headers.get("x-mirror-key") ?? "");
  const signature = bytes(request.headers.get("x-mirror-signature") ?? "");
  const time = Number(request.headers.get("x-mirror-time") ?? "0");
  if (!key || key.length !== 65 || !signature || signature.length !== 64) return Response.json({ error: "signature" }, { status: 401 });
  if (!Number.isFinite(time) || Math.abs(Date.now() / 1000 - time) > 300) return Response.json({ error: "time" }, { status: 401 });
  const body = op === "put" ? new Uint8Array(await request.arrayBuffer()) : new Uint8Array();
  if (body.length > MAX_FILE) return Response.json({ error: "size" }, { status: 413 });
  const message = new TextEncoder().encode(`${op}\n${name}\n${time}\n${await hex(body)}`);
  const publicKey = await crypto.subtle.importKey("raw", key, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]).catch(() => null);
  const valid = publicKey
    ? await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, publicKey, signature, message).catch(() => false)
    : false;
  if (!valid) return Response.json({ error: "signature" }, { status: 401 });

  const shelf = await hex(key);
  const storage = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!).storage.from(BUCKET);
  const path = `${shelf}/${name}`;

  switch (op) {
    case "list": {
      const { data, error } = await storage.list(shelf, { limit: 1000 });
      if (error) return Response.json({ error: "busy" }, { status: 503 });
      return Response.json({ names: (data ?? []).map((file) => file.name).filter((n) => NAME.test(n)) });
    }
    case "get": {
      const { data, error } = await storage.download(path);
      if (error || !data) return Response.json({ error: "missing" }, { status: 404 });
      return new Response(data, { headers: { "Content-Type": "application/octet-stream" } });
    }
    case "delete": {
      await storage.remove([path]);
      return Response.json({ ok: true });
    }
    default: {
      // A shelf holds a person's photos, not a stranger's files.
      const { data } = await storage.list(shelf, { limit: 1000 });
      const known = new Set((data ?? []).map((file) => file.name));
      if (!known.has(name) && known.size >= MAX_FILES) return Response.json({ error: "full" }, { status: 507 });
      const { error } = await storage.upload(path, body, { upsert: true, contentType: "application/octet-stream" });
      if (error) return Response.json({ error: "busy" }, { status: 503 });
      return Response.json({ ok: true });
    }
  }
});
