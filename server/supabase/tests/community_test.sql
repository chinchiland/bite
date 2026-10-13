-- Bite's community, checked as the people who use it: a visitor, someone signed in who has not
-- accepted the rules, a sharer and three neighbours. Run by `supabase test db` on every push
-- (.github/workflows/server.yml). Everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(39);

-- The shape: it fails closed.

select is(
  (select count(*)::int from pg_tables where schemaname = 'public' and not rowsecurity),
  0, 'every public table has row level security');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname in ('public', 'private') and p.prosecdef
      and not exists (select 1 from unnest(coalesce(p.proconfig, '{}'::text[])) setting where setting like 'search_path=%')),
  0, 'every security definer function pins its search path');

select is(
  array(select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute') order by 1),
  array['dishes_near'],
  'a visitor can only look');

select is(
  array(select p.proname::text from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and has_function_privilege('authenticated', p.oid, 'execute') order by 1),
  array['delete_my_data', 'dishes_near', 'hide_author', 'rate_dish', 'report_content', 'save_profile', 'set_agree', 'share_estimate'],
  'someone signed in can call the eight functions, and nothing else');

select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm')
      and (has_table_privilege('anon', c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
        or has_table_privilege('authenticated', c.oid, 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
        or has_any_column_privilege('anon', c.oid, 'INSERT, UPDATE, REFERENCES')
        or has_any_column_privilege('authenticated', c.oid, 'INSERT, UPDATE, REFERENCES'))),
  0, 'no client writes a table directly');

select is(
  (select count(*)::int from pg_namespace n
    where n.nspname = 'private'
      and (has_schema_privilege('anon', n.oid, 'USAGE') or has_schema_privilege('authenticated', n.oid, 'USAGE'))),
  0, 'the private schema is out of reach');

create table public.added_later (id int);
select ok(
  not has_table_privilege('anon', 'public.added_later', 'SELECT')
    and not has_table_privilege('authenticated', 'public.added_later', 'SELECT'),
  'a table added later starts private');
drop table public.added_later;

-- The people.
insert into auth.users (id, email) values
  ('a0000000-0000-0000-0000-00000000000a', 'sharer@bite.test'),
  ('b0000000-0000-0000-0000-00000000000b', 'neighbour@bite.test'),
  ('c0000000-0000-0000-0000-00000000000c', 'third@bite.test'),
  ('d0000000-0000-0000-0000-00000000000d', 'fourth@bite.test');

-- A visitor, not signed in.
set local role anon;
set local request.jwt.claim.sub = '';

select throws_ok(
  $$ select public.share_estimate('{}'::jsonb, '{}'::jsonb, '{}'::jsonb) $$,
  '42501', null, 'a visitor cannot share');
select is(jsonb_array_length(public.dishes_near(46.5167, 6.6215, 3000)), 0, 'a visitor can look, and nothing is there yet');
select throws_ok($$ select count(*) from public.profiles $$, '42501', null, 'a visitor cannot list people');

-- The sharer, signed in, rules not accepted yet.
set local role authenticated;
set local request.jwt.claim.sub = 'a0000000-0000-0000-0000-00000000000a';

select throws_ok(
  $$ select public.share_estimate(
       '{"id":"10000000-0000-0000-0000-000000000001","name":"El Beirout","latitude":46.5167,"longitude":6.6215}',
       '{"id":"20000000-0000-0000-0000-000000000001","name":"Chicken shawarma"}',
       '{"id":"30000000-0000-0000-0000-000000000001","source":"entered","kcal":590,"protein":37,"carbs":55,"fat":24}') $$,
  '42501', 'not allowed to share', 'no sharing before the rules are accepted');
select lives_ok($$ select public.save_profile('Dylan') $$, 'your name, and the rules accepted');
select lives_ok(
  $$ select public.share_estimate(
       '{"id":"10000000-0000-0000-0000-000000000001","name":"El Beirout","latitude":46.5167,"longitude":6.6215}',
       '{"id":"20000000-0000-0000-0000-000000000001","name":"Chicken shawarma"}',
       '{"id":"30000000-0000-0000-0000-000000000001","source":"entered","kcal":590,"protein":37,"carbs":55,"fat":24}') $$,
  'then you can share');
select is(jsonb_array_length(public.dishes_near(46.5167, 6.6215, 3000)), 1, 'a new dish shows to you while it waits');

-- A neighbour, before signing up.
set local request.jwt.claim.sub = 'b0000000-0000-0000-0000-00000000000b';

select is(jsonb_array_length(public.dishes_near(46.5167, 6.6215, 3000)), 0, 'and to nobody else');
select throws_ok($$ update public.dishes set status = 'visible' $$, '42501', null, 'nobody approves a dish from the app');
select throws_ok(
  $$ insert into public.agrees (estimate_id, user_id) values ('30000000-0000-0000-0000-000000000001', 'b0000000-0000-0000-0000-00000000000b') $$,
  '42501', null, 'nobody writes a table directly');

-- Moderation approves the dish.
reset role;
update public.dishes set status = 'visible' where id = '20000000-0000-0000-0000-000000000001';
set local role authenticated;
set local request.jwt.claim.sub = 'b0000000-0000-0000-0000-00000000000b';

select is(jsonb_array_length(public.dishes_near(46.5167, 6.6215, 3000)), 1, 'once approved, everyone nearby sees it');
select is(public.dishes_near(46.5167, 6.6215, 3000) -> 0 -> 'estimates' -> 0 ->> 'author', 'Dylan', 'with the name of who counted it');
select is(jsonb_array_length(public.dishes_near(46.5167, 7.6215, 3000)), 0, 'and nobody 75 km away does');

select lives_ok($$ select public.save_profile('Léa') $$, 'the neighbour joins');
select is((select count(*)::int from public.profiles), 1, 'you read your own profile, nobody else''s');
select lives_ok($$ select public.set_agree('30000000-0000-0000-0000-000000000001', true) $$, 'the neighbour agrees');
select is((select agree_count from public.estimates where id = '30000000-0000-0000-0000-000000000001'), 1, 'and the count goes up');

-- The sharer agrees with their own estimate.
set local request.jwt.claim.sub = 'a0000000-0000-0000-0000-00000000000a';
select lives_ok($$ select public.set_agree('30000000-0000-0000-0000-000000000001', true) $$, 'agreeing with yourself does not fail');
select is((select agree_count from public.estimates where id = '30000000-0000-0000-0000-000000000001'), 1, 'but counts for nothing');

-- Stars.
set local request.jwt.claim.sub = 'b0000000-0000-0000-0000-00000000000b';
select lives_ok($$ select public.rate_dish('20000000-0000-0000-0000-000000000001', 5::smallint) $$, 'the neighbour rates the dish');
select is((select rating_count from public.dishes where id = '20000000-0000-0000-0000-000000000001'), 1, 'and the stars count once');

-- Three different people report the estimate.
select lives_ok($$ select public.report_content(null, '30000000-0000-0000-0000-000000000001', 'Far too low') $$, 'a first report');
set local request.jwt.claim.sub = 'c0000000-0000-0000-0000-00000000000c';
select lives_ok($$ select public.save_profile('Tom') $$, 'a third person joins');
select lives_ok($$ select public.report_content(null, '30000000-0000-0000-0000-000000000001', 'Wrong') $$, 'a second report');
set local request.jwt.claim.sub = 'd0000000-0000-0000-0000-00000000000d';
select lives_ok($$ select public.save_profile('Sara') $$, 'a fourth person joins');
select lives_ok($$ select public.report_content(null, '30000000-0000-0000-0000-000000000001', 'Wrong') $$, 'a third report');
set local request.jwt.claim.sub = 'b0000000-0000-0000-0000-00000000000b';
select is(
  jsonb_array_length(public.dishes_near(46.5167, 6.6215, 3000) -> 0 -> 'estimates'), 0,
  'three reports hide an estimate until someone looks');

-- Hiding someone.
select lives_ok($$ select public.hide_author('a0000000-0000-0000-0000-00000000000a') $$, 'the neighbour hides the sharer');
select is(jsonb_array_length(public.dishes_near(46.5167, 6.6215, 3000)), 0, 'and no longer sees what they shared');

-- Twenty shares an hour at most.
set local request.jwt.claim.sub = 'a0000000-0000-0000-0000-00000000000a';
do $$
begin
  for i in 2..20 loop
    perform public.share_estimate(
      '{"id":"10000000-0000-0000-0000-000000000001","name":"El Beirout","latitude":46.5167,"longitude":6.6215}'::jsonb,
      jsonb_build_object('id', gen_random_uuid(), 'name', 'Dish ' || i),
      jsonb_build_object('id', gen_random_uuid(), 'source', 'entered', 'kcal', 500, 'protein', 20, 'carbs', 50, 'fat', 20));
  end loop;
end $$;
select throws_ok(
  $$ select public.share_estimate(
       '{"id":"10000000-0000-0000-0000-000000000001","name":"El Beirout","latitude":46.5167,"longitude":6.6215}',
       '{"id":"20000000-0000-0000-0000-000000000099","name":"Dish 21"}',
       '{"id":"30000000-0000-0000-0000-000000000099","source":"entered","kcal":500,"protein":20,"carbs":50,"fat":20}') $$,
  '54000', 'too many shares, try again later', 'twenty shares an hour at most');

-- Taking it all back.
select lives_ok($$ select public.delete_my_data() $$, 'you can take back everything you shared');
reset role;
select is((select count(*)::int from public.estimates where author_id = 'a0000000-0000-0000-0000-00000000000a'), 0, 'and it is gone');

select * from finish();
rollback;
