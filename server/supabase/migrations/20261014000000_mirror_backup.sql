-- Your mirror, kept forever: one private bucket for photo files the phone has already sealed.
-- Nothing reaches it but the mirror-backup function, which checks each request's signature and
-- writes with the service role; no policy opens it to the API's roles.
insert into storage.buckets (id, name, public, file_size_limit)
values ('mirror', 'mirror', false, 2500000)
on conflict (id) do update set public = false, file_size_limit = 2500000;
