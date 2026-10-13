-- A new dish waits as pending until the moderate function has read its name. The database asks
-- for that itself, on every new dish. The function's address and the secret it checks live in
-- Vault on the live project, set once by hand, never in this repo: without them, nothing is sent
-- and the dish simply waits.
create extension if not exists pg_net;

create function private.ask_moderation() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'moderation_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'moderation_secret';
  if v_url is null or v_secret is null then
    return null;
  end if;
  perform net.http_post(
    url := v_url,
    body := jsonb_build_object('type', 'INSERT', 'table', 'dishes', 'record', to_jsonb(new)),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret)
  );
  return null;
end $$;

create trigger dishes_moderate after insert on public.dishes
  for each row execute function private.ask_moderation();

revoke execute on function private.ask_moderation() from public, anon, authenticated;
