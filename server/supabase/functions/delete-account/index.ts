// Delete my shared counts and account, from Settings in the app: revokes the Apple token,
// removes everything the person shared, then the account itself. The food log is on the phone
// and never was here.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import postgres from "https://deno.land/x/postgresjs@v3.4.4/mod.js";
import { revoke } from "../_shared/apple.ts";

const sql = postgres(Deno.env.get("SUPABASE_DB_URL")!, { prepare: false });

Deno.serve(async (request) => {
  if (request.method !== "POST") return new Response("POST only", { status: 405 });
  const authorization = request.headers.get("Authorization") ?? "";
  const url = Deno.env.get("SUPABASE_URL")!;
  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { data: { user } } = await admin.auth.getUser(authorization.replace("Bearer ", ""));
  if (!user) return new Response("Sign in first", { status: 401 });

  const rows = await sql`select refresh_token from private.apple_tokens where user_id = ${user.id}`;
  if (rows.length > 0) await revoke(rows[0].refresh_token);

  // As the person, so delete_my_data sees who they are.
  const asUser = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, { global: { headers: { Authorization: authorization } } });
  const { error } = await asUser.rpc("delete_my_data");
  if (error) return new Response(error.message, { status: 500 });

  const { error: deleteError } = await admin.auth.admin.deleteUser(user.id);
  if (deleteError) return new Response(deleteError.message, { status: 500 });
  return Response.json({ ok: true });
});
