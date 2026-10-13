// Sign in with Apple, server side: the client secret Apple asks for, and the token calls.
// Set these secrets with `supabase secrets set`: APPLE_TEAM_ID, APPLE_KEY_ID, APPLE_CLIENT_ID
// (the app's bundle id) and APPLE_PRIVATE_KEY (the .p8 key's contents).
import { importPKCS8, SignJWT } from "https://deno.land/x/jose@v5.9.6/index.ts";

const audience = "https://appleid.apple.com";

/** The short-lived client secret: an ES256 JWT signed with the Sign in with Apple key. */
async function clientSecret(): Promise<string> {
  const key = await importPKCS8(Deno.env.get("APPLE_PRIVATE_KEY")!, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: Deno.env.get("APPLE_KEY_ID")! })
    .setIssuer(Deno.env.get("APPLE_TEAM_ID")!)
    .setSubject(Deno.env.get("APPLE_CLIENT_ID")!)
    .setAudience(audience)
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);
}

/** Trades the authorization code from the app's sign-in for a refresh token, kept for revoking. */
export async function refreshToken(code: string): Promise<string | null> {
  const body = new URLSearchParams({
    client_id: Deno.env.get("APPLE_CLIENT_ID")!,
    client_secret: await clientSecret(),
    code,
    grant_type: "authorization_code",
  });
  const response = await fetch(`${audience}/auth/token`, { method: "POST", body });
  if (!response.ok) return null;
  const json = await response.json();
  return json.refresh_token ?? null;
}

/** Revokes the person's Apple token, as Apple asks when an account is deleted. */
export async function revoke(token: string): Promise<boolean> {
  const body = new URLSearchParams({
    client_id: Deno.env.get("APPLE_CLIENT_ID")!,
    client_secret: await clientSecret(),
    token,
    token_type_hint: "refresh_token",
  });
  const response = await fetch(`${audience}/auth/revoke`, { method: "POST", body });
  return response.ok;
}
