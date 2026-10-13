-- Photo estimates made by Bite's own server. Each one is counted here before Gemini sees the
-- photo, so a person, a network and the whole app each have a ceiling that no honest use
-- reaches, even someone scanning everything in the kitchen for fun, and a runaway script can't
-- run up the bill. No photo is kept: only who, when, which model and how many tokens.
create table private.scans (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  network text not null,
  created_at timestamptz not null default now(),
  model text,
  input_tokens integer,
  output_tokens integer,
  ok boolean
);
create index scans_user_time on private.scans (user_id, created_at desc);
create index scans_network_time on private.scans (network, created_at desc);
create index scans_time on private.scans (created_at desc);

-- The ceilings, one row, changed by hand when needed. Paused stops every photo estimate at once.
create table private.scan_limits (
  id boolean primary key default true check (id),
  per_minute integer not null default 12,
  per_day integer not null default 80,
  per_network_day integer not null default 400,
  everyone_day integer not null default 20000,
  paused boolean not null default false
);
insert into private.scan_limits default values;

-- One photo estimate, if every ceiling allows it: {"id": <scan>} once counted, or
-- {"refused": "minute" | "day" | "network" | "everyone" | "paused"}. `network` is a salted hash
-- of the caller's address, never the address.
create function private.take_scan(p_user uuid, p_network text) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_limits private.scan_limits;
  v_id bigint;
begin
  select * into v_limits from private.scan_limits where id;
  if v_limits is null or v_limits.paused then
    return jsonb_build_object('refused', 'paused');
  end if;
  -- One person's scans are counted one at a time, so two at once can't both slip under.
  perform pg_advisory_xact_lock(hashtextextended(p_user::text, 0));
  if (select count(*) from private.scans where user_id = p_user and created_at > now() - interval '1 minute') >= v_limits.per_minute then
    return jsonb_build_object('refused', 'minute');
  end if;
  if (select count(*) from private.scans where user_id = p_user and created_at > now() - interval '1 day') >= v_limits.per_day then
    return jsonb_build_object('refused', 'day');
  end if;
  if (select count(*) from private.scans where network = p_network and created_at > now() - interval '1 day') >= v_limits.per_network_day then
    return jsonb_build_object('refused', 'network');
  end if;
  if (select count(*) from private.scans where created_at > now() - interval '1 day') >= v_limits.everyone_day then
    return jsonb_build_object('refused', 'everyone');
  end if;
  insert into private.scans (user_id, network) values (p_user, p_network) returning id into v_id;
  return jsonb_build_object('id', v_id);
end $$;

-- What the estimate cost, once Gemini answered: for the bill, and to spot a model that fails.
create function private.finish_scan(p_scan bigint, p_model text, p_input integer, p_output integer, p_ok boolean) returns void
language sql security definer set search_path = '' as $$
  update private.scans set model = p_model, input_tokens = p_input, output_tokens = p_output, ok = p_ok where id = p_scan;
$$;

revoke execute on function private.take_scan(uuid, text) from public, anon, authenticated;
revoke execute on function private.finish_scan(bigint, text, integer, integer, boolean) from public, anon, authenticated;
