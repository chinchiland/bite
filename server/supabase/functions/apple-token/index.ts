// After the app signs in with Apple, it sends the one-time authorization code here. The code
// becomes a refresh token, kept in private.apple_tokens so that deleting the account can revoke
// it, as Apple requires. Nothing comes back to the app but "ok".
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import postgres from "https://deno.land/x/postgresjs@v3.4.4/mod.js";
import { refreshToken } from "../_shared/apple.ts";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { prepare: false });

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("POST only", { status: 405 });
  const jwt = request.headers.get("Authorization")?.replace("Bearer ", "") ?? "";
  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: { user } } = await admin.auth.getUser(jwt);
  if (!user) return new Response("Sign in first", { status: 401 });

  const { code } = await request.json().catch(() => ({ code: null }));
  if (typeof code !== "string" || code.length === 0) return new Response("No code", { status: 400 });
  const token = await refreshToken(code);
  if (!token) return new Response("Apple refused the code", { status: 502 });

  await sql`
    insert into private.apple_tokens (user_id, refresh_token, updated_at)
    values (${user.id}, ${token}, now())
    on conflict (user_id) do update set refresh_token = excluded.refresh_token, updated_at = now()`;
  return Response.json({ ok: true });
});
