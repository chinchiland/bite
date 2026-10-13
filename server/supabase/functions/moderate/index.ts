// A new dish waits as "pending" until this looks at its name. A database webhook on inserts
// into public.dishes calls it (set the header x-webhook-secret to MODERATION_SECRET). The name
// goes to OpenAI's free moderation endpoint; a flagged name is rejected, the rest becomes
// visible. Estimates are numbers checked by range in the database, so they need no review.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

Deno.serve(async (request) => {
  if (request.headers.get("x-webhook-secret") !== Deno.env.get("MODERATION_SECRET")) {
    return new Response("Not allowed", { status: 401 });
  }
  const payload = await request.json();
  const dish = payload?.record;
  if (payload?.table !== "dishes" || !dish?.id || dish.status !== "pending") {
    return Response.json({ skipped: true });
  }

  const check = await fetch("https://api.openai.com/v1/moderations", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${Deno.env.get("OPENAI_API_KEY")}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model: "omni-moderation-latest", input: dish.name }),
  });
  if (!check.ok) {
    // Left pending: it shows to its author only, and is looked at again on the next run.
    return new Response("Moderation unavailable", { status: 502 });
  }
  const result = await check.json();
  const flagged = result?.results?.[0]?.flagged === true;

  const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error } = await admin.from("dishes").update({ status: flagged ? "rejected" : "visible" }).eq("id", dish.id);
  if (error) return new Response(error.message, { status: 500 });
  return Response.json({ status: flagged ? "rejected" : "visible" });
});
