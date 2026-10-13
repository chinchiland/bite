-- Bite's community: dishes at places, and people's calorie estimates for them.
--
-- Reading is open to everyone, signed in or not. Writing goes through the functions at the end
-- (security definer), which check who you are, that you accepted the rules, that you are not
-- banned and not posting too fast. Counters and statuses can never be written by a client.
-- Your food log never comes here: only the estimates you choose to share.
--
-- It fails closed: no client role keeps a right from Supabase's default grants, a table added
-- later starts private, and a function added later fails server/supabase/tests until it is
-- granted on purpose. The tests run on every push.

create extension if not exists postgis with schema extensions;

create schema if not exists private;

-- People, by the name others see.
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 30),
  terms_accepted_at timestamptz,
  is_banned boolean not null default false,
  is_admin boolean not null default false,
  created_at timestamptz not null default now()
);

-- Places, one per real place: by Apple Maps' id when there is one, else by name and position.
create table public.places (
  id uuid primary key,
  mapkit_id text unique,
  name text not null check (char_length(name) between 1 and 120),
  area text check (char_length(area) <= 120),
  category text check (char_length(category) <= 40),
  location extensions.geography(point, 4326) not null,
  created_at timestamptz not null default now()
);
create index places_location_idx on public.places using gist (location);

-- Dishes, one per name at a place. A new dish waits for moderation before others see it.
create table public.dishes (
  id uuid primary key,
  place_id uuid not null references public.places on delete cascade,
  -- Null once its author has left: the dish stays for the others' estimates.
  author_id uuid references public.profiles on delete set null,
  name text not null check (char_length(name) between 1 and 80),
  name_key text generated always as (lower(name)) stored,
  emoji text check (char_length(emoji) <= 16),
  photo_path text,
  status text not null default 'pending' check (status in ('pending', 'visible', 'hidden', 'rejected')),
  rating_sum integer not null default 0,
  rating_count integer not null default 0,
  created_at timestamptz not null default now(),
  unique (place_id, name_key)
);

-- One estimate per person per dish; changing it replaces it. Only numbers, checked by range,
-- so it shows at once.
create table public.estimates (
  id uuid primary key,
  dish_id uuid not null references public.dishes on delete cascade,
  author_id uuid not null references public.profiles on delete cascade,
  source text not null check (source in ('ai', 'entered')),
  kcal numeric not null check (kcal between 0 and 5000),
  protein numeric not null check (protein between 0 and 500),
  carbs numeric not null check (carbs between 0 and 1000),
  fat numeric not null check (fat between 0 and 500),
  agree_count integer not null default 0,
  status text not null default 'visible' check (status in ('visible', 'hidden')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (dish_id, author_id)
);

create table public.agrees (
  estimate_id uuid not null references public.estimates on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  primary key (estimate_id, user_id)
);

create table public.ratings (
  dish_id uuid not null references public.dishes on delete cascade,
  user_id uuid not null references public.profiles on delete cascade,
  stars smallint not null check (stars between 1 and 5),
  primary key (dish_id, user_id)
);

create table public.reports (
  id bigint generated always as identity primary key,
  reporter_id uuid not null references public.profiles on delete cascade,
  dish_id uuid references public.dishes on delete cascade,
  estimate_id uuid references public.estimates on delete cascade,
  reason text check (char_length(reason) <= 200),
  created_at timestamptz not null default now(),
  check (dish_id is not null or estimate_id is not null)
);
create unique index reports_once on public.reports (
  reporter_id,
  coalesce(dish_id, '00000000-0000-0000-0000-000000000000'::uuid),
  coalesce(estimate_id, '00000000-0000-0000-0000-000000000000'::uuid)
);

create table public.blocks (
  blocker_id uuid not null references public.profiles on delete cascade,
  blocked_id uuid not null references public.profiles on delete cascade,
  primary key (blocker_id, blocked_id)
);

-- Apple's refresh token per person, so deleting an account can revoke it. Never exposed.
create table private.apple_tokens (
  user_id uuid primary key references auth.users on delete cascade,
  refresh_token text not null,
  updated_at timestamptz not null default now()
);

-- Row level security: read what is visible; write only through the functions below.
alter table public.profiles enable row level security;
alter table public.places enable row level security;
alter table public.dishes enable row level security;
alter table public.estimates enable row level security;
alter table public.agrees enable row level security;
alter table public.ratings enable row level security;
alter table public.reports enable row level security;
alter table public.blocks enable row level security;

-- Your own profile only: the names people see come with the dishes, through dishes_near.
create policy "your profile" on public.profiles for select using (id = auth.uid());
create policy "places are public" on public.places for select using (true);
create policy "visible dishes, and yours" on public.dishes for select
  using (status = 'visible' or author_id = auth.uid());
create policy "visible estimates, and yours" on public.estimates for select
  using (status = 'visible' or author_id = auth.uid());
create policy "your agrees" on public.agrees for select using (user_id = auth.uid());
create policy "your ratings" on public.ratings for select using (user_id = auth.uid());
create policy "your blocks" on public.blocks for select using (blocker_id = auth.uid());

-- Clients read through the policies above and write nothing directly. Supabase grants every
-- client role all rights on new public objects by default; take them all back, give back
-- reading, and make whatever comes later start private.
revoke all on all tables in schema public from anon, authenticated;
revoke all on all sequences in schema public from anon, authenticated;
grant select on public.places, public.dishes, public.estimates to anon, authenticated;
grant select on public.profiles, public.agrees, public.ratings, public.blocks to authenticated;
alter default privileges for role postgres in schema public revoke all on tables from anon, authenticated;
alter default privileges for role postgres in schema public revoke all on sequences from anon, authenticated;
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated;

-- Counters kept by the database.
create function private.count_agrees() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    update public.estimates set agree_count = agree_count + 1 where id = new.estimate_id;
  else
    update public.estimates set agree_count = greatest(agree_count - 1, 0) where id = old.estimate_id;
  end if;
  return null;
end $$;
create trigger agrees_count after insert or delete on public.agrees
  for each row execute function private.count_agrees();

create function private.count_ratings() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op in ('UPDATE', 'DELETE') then
    update public.dishes set rating_sum = rating_sum - old.stars, rating_count = rating_count - 1 where id = old.dish_id;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    update public.dishes set rating_sum = rating_sum + new.stars, rating_count = rating_count + 1 where id = new.dish_id;
  end if;
  return null;
end $$;
create trigger ratings_count after insert or update or delete on public.ratings
  for each row execute function private.count_ratings();

-- Three different people reporting the same thing hide it at once, until someone looks.
create function private.hide_reported() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.estimate_id is not null
     and (select count(distinct reporter_id) from public.reports where estimate_id = new.estimate_id) >= 3 then
    update public.estimates set status = 'hidden' where id = new.estimate_id;
  end if;
  if new.dish_id is not null
     and (select count(distinct reporter_id) from public.reports where dish_id = new.dish_id) >= 3 then
    update public.dishes set status = 'hidden' where id = new.dish_id;
  end if;
  return null;
end $$;
create trigger reports_hide after insert on public.reports
  for each row execute function private.hide_reported();

-- Who may write: signed in, rules accepted, not banned.
create function private.writer() returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'sign in to share' using errcode = '28000';
  end if;
  if not exists (select 1 from public.profiles where id = v_me and terms_accepted_at is not null and not is_banned) then
    raise exception 'not allowed to share' using errcode = '42501';
  end if;
  return v_me;
end $$;

-- Your name as people see it, and that you accepted the rules (the first time is kept).
create function public.save_profile(p_name text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'sign in first' using errcode = '28000';
  end if;
  insert into public.profiles (id, display_name, terms_accepted_at)
    values (v_me, btrim(p_name), now())
    on conflict (id) do update
      set display_name = excluded.display_name,
          terms_accepted_at = coalesce(public.profiles.terms_accepted_at, excluded.terms_accepted_at);
end $$;

-- Share your estimate of a dish at a place: the place and the dish are found or added, your
-- estimate replaces your last one. About twenty an hour at most.
create function public.share_estimate(p_place jsonb, p_dish jsonb, p_estimate jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := private.writer();
  v_point extensions.geography := extensions.st_setsrid(
    extensions.st_makepoint((p_place->>'longitude')::float8, (p_place->>'latitude')::float8), 4326
  )::extensions.geography;
  v_place uuid;
  v_dish uuid;
  v_estimate uuid;
begin
  if (select count(*) from public.estimates where author_id = v_me and updated_at > now() - interval '1 hour') >= 20 then
    raise exception 'too many shares, try again later' using errcode = '54000';
  end if;

  if p_place->>'mapkit_id' is not null then
    select id into v_place from public.places where mapkit_id = p_place->>'mapkit_id';
  end if;
  if v_place is null then
    select id into v_place from public.places
      where lower(name) = lower(p_place->>'name') and extensions.st_dwithin(location, v_point, 50)
      limit 1;
  end if;
  if v_place is null then
    insert into public.places (id, mapkit_id, name, area, category, location)
      values ((p_place->>'id')::uuid, p_place->>'mapkit_id', p_place->>'name', p_place->>'area', p_place->>'category', v_point)
      returning id into v_place;
  end if;

  select id into v_dish from public.dishes where place_id = v_place and name_key = lower(p_dish->>'name');
  if v_dish is null then
    insert into public.dishes (id, place_id, author_id, name, emoji)
      values ((p_dish->>'id')::uuid, v_place, v_me, p_dish->>'name', p_dish->>'emoji')
      returning id into v_dish;
  end if;

  insert into public.estimates (id, dish_id, author_id, source, kcal, protein, carbs, fat)
    values ((p_estimate->>'id')::uuid, v_dish, v_me, p_estimate->>'source',
            (p_estimate->>'kcal')::numeric, (p_estimate->>'protein')::numeric,
            (p_estimate->>'carbs')::numeric, (p_estimate->>'fat')::numeric)
    on conflict (dish_id, author_id) do update
      set source = excluded.source, kcal = excluded.kcal, protein = excluded.protein,
          carbs = excluded.carbs, fat = excluded.fat, updated_at = now()
    returning id into v_estimate;

  return jsonb_build_object('place_id', v_place, 'dish_id', v_dish, 'estimate_id', v_estimate);
end $$;

-- Dishes near a point, nearest first, with their visible estimates, minus people you hid.
create function public.dishes_near(p_latitude float8, p_longitude float8, p_radius integer default 3000) returns jsonb
language sql stable security definer set search_path = '' as $$
  with here as (
    select extensions.st_setsrid(extensions.st_makepoint(p_longitude, p_latitude), 4326)::extensions.geography as point
  ),
  hidden as (
    select blocked_id from public.blocks where blocker_id = auth.uid()
  ),
  near as (
    select extensions.st_distance(p.location, here.point) as distance,
      jsonb_build_object(
        'id', d.id, 'name', d.name, 'emoji', d.emoji, 'photo_path', d.photo_path,
        'rating_sum', d.rating_sum, 'rating_count', d.rating_count,
        'my_rating', (select r.stars from public.ratings r where r.dish_id = d.id and r.user_id = auth.uid()),
        'place', jsonb_build_object(
          'id', p.id, 'name', p.name, 'area', p.area, 'category', p.category,
          'latitude', extensions.st_y(p.location::extensions.geometry),
          'longitude', extensions.st_x(p.location::extensions.geometry)
        ),
        'estimates', coalesce((
          select jsonb_agg(jsonb_build_object(
            'id', e.id, 'author_id', e.author_id, 'author', pr.display_name, 'source', e.source,
            'kcal', e.kcal, 'protein', e.protein, 'carbs', e.carbs, 'fat', e.fat,
            'agrees', e.agree_count,
            'agreed_by_me', exists (select 1 from public.agrees a where a.estimate_id = e.id and a.user_id = auth.uid()),
            'is_mine', e.author_id = auth.uid()
          ) order by e.agree_count desc)
          from public.estimates e
            join public.profiles pr on pr.id = e.author_id
          where e.dish_id = d.id
            and (e.status = 'visible' or e.author_id = auth.uid())
            and not pr.is_banned
            and e.author_id not in (select blocked_id from hidden)
        ), '[]'::jsonb)
      ) as item
    from public.dishes d
      join public.places p on p.id = d.place_id
      left join public.profiles author on author.id = d.author_id
      cross join here
    where (d.status = 'visible' or d.author_id = auth.uid())
      and coalesce(not author.is_banned, true)
      and (d.author_id is null or d.author_id not in (select blocked_id from hidden))
      and extensions.st_dwithin(p.location, here.point, least(p_radius, 20000))
    order by distance
    limit 100
  )
  select coalesce(jsonb_agg(item order by distance), '[]'::jsonb) from near;
$$;

-- Agree with someone else's visible estimate, or take it back.
create function public.set_agree(p_estimate uuid, p_agree boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := private.writer();
begin
  if p_agree then
    insert into public.agrees (estimate_id, user_id)
      select e.id, v_me from public.estimates e
      where e.id = p_estimate and e.status = 'visible' and e.author_id <> v_me
      on conflict do nothing;
  else
    delete from public.agrees where estimate_id = p_estimate and user_id = v_me;
  end if;
end $$;

-- Your stars for a visible dish; null takes them back.
create function public.rate_dish(p_dish uuid, p_stars smallint) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := private.writer();
begin
  if p_stars is null then
    delete from public.ratings where dish_id = p_dish and user_id = v_me;
  else
    insert into public.ratings (dish_id, user_id, stars)
      select d.id, v_me, p_stars from public.dishes d where d.id = p_dish and d.status = 'visible'
      on conflict (dish_id, user_id) do update set stars = excluded.stars;
  end if;
end $$;

-- Report a dish or an estimate. Signed in only, so reports cannot be faked in bulk.
create function public.report_content(p_dish uuid, p_estimate uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'sign in to report' using errcode = '28000';
  end if;
  insert into public.reports (reporter_id, dish_id, estimate_id, reason)
    values (v_me, p_dish, p_estimate, left(p_reason, 200))
    on conflict do nothing;
end $$;

-- Hide everything a person shares, for you.
create function public.hide_author(p_author uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'sign in to hide' using errcode = '28000';
  end if;
  insert into public.blocks (blocker_id, blocked_id) values (v_me, p_author) on conflict do nothing;
end $$;

-- Everything you shared goes: your estimates, agrees, stars and hides, and dishes nobody else
-- estimated. The account itself goes in the delete-account function.
create function public.delete_my_data() returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_me uuid := auth.uid();
begin
  if v_me is null then
    raise exception 'sign in first' using errcode = '28000';
  end if;
  delete from public.estimates where author_id = v_me;
  delete from public.dishes d
    where d.author_id = v_me and not exists (select 1 from public.estimates e where e.dish_id = d.id);
  update public.dishes set author_id = null where author_id = v_me;
  delete from public.agrees where user_id = v_me;
  delete from public.ratings where user_id = v_me;
  delete from public.blocks where blocker_id = v_me;
end $$;

revoke execute on all functions in schema public from public, anon, authenticated;
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function public.dishes_near(float8, float8, integer) to anon, authenticated;
grant execute on function public.save_profile(text) to authenticated;
grant execute on function public.share_estimate(jsonb, jsonb, jsonb) to authenticated;
grant execute on function public.set_agree(uuid, boolean) to authenticated;
grant execute on function public.rate_dish(uuid, smallint) to authenticated;
grant execute on function public.report_content(uuid, uuid, text) to authenticated;
grant execute on function public.hide_author(uuid) to authenticated;
grant execute on function public.delete_my_data() to authenticated;
