-- The ceilings on Bite's own photo estimates: per minute, per day, per network, and the switch
-- that stops them all. Run by `supabase test db`; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

insert into auth.users (id, email) values
  ('e0000000-0000-0000-0000-00000000000e', 'scanner@bite.test'),
  ('f0000000-0000-0000-0000-00000000000f', 'neighbour@bite.test');

select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'private' and p.proname in ('take_scan', 'finish_scan')
      and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('authenticated', p.oid, 'execute'))),
  0, 'only the server counts scans');

select ok(private.take_scan('e0000000-0000-0000-0000-00000000000e', 'network-a') ? 'id', 'a first scan goes through');

do $$
begin
  for i in 2..12 loop
    perform private.take_scan('e0000000-0000-0000-0000-00000000000e', 'network-a');
  end loop;
end $$;
select is(private.take_scan('e0000000-0000-0000-0000-00000000000e', 'network-a') ->> 'refused', 'minute', 'a thirteenth in one minute waits');

-- The twelve were an hour ago, and 68 more today: eighty in the day.
update private.scans set created_at = now() - interval '1 hour' where user_id = 'e0000000-0000-0000-0000-00000000000e';
insert into private.scans (user_id, network, created_at)
  select 'e0000000-0000-0000-0000-00000000000e', 'network-a', now() - interval '2 hours' from generate_series(1, 68);
select is(private.take_scan('e0000000-0000-0000-0000-00000000000e', 'network-a') ->> 'refused', 'day', 'the eighty-first in a day waits until tomorrow');

update private.scans set created_at = now() - interval '25 hours' where user_id = 'e0000000-0000-0000-0000-00000000000e';
select ok(private.take_scan('e0000000-0000-0000-0000-00000000000e', 'network-a') ? 'id', 'yesterday''s scans no longer count');

insert into private.scans (user_id, network, created_at)
  select 'f0000000-0000-0000-0000-00000000000f', 'network-b', now() - interval '3 hours' from generate_series(1, 400);
select is(private.take_scan('e0000000-0000-0000-0000-00000000000e', 'network-b') ->> 'refused', 'network', 'one network has its own ceiling');

update private.scan_limits set paused = true;
select is(private.take_scan('f0000000-0000-0000-0000-00000000000f', 'network-c') ->> 'refused', 'paused', 'one switch stops every photo estimate');
update private.scan_limits set paused = false;

select lives_ok(
  $$ select private.finish_scan((select max(id) from private.scans where user_id = 'e0000000-0000-0000-0000-00000000000e'), 'gemini-3.1-flash-lite', 1345, 300, true) $$,
  'the answer is recorded');
select is(
  (select model || ' ' || input_tokens || ' ' || output_tokens from private.scans where id = (select max(id) from private.scans where user_id = 'e0000000-0000-0000-0000-00000000000e')),
  'gemini-3.1-flash-lite 1345 300', 'with its model and tokens, and no photo');

select * from finish();
rollback;
