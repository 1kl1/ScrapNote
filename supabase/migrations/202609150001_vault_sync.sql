-- A private, versioned manifest per authenticated owner. Blobs are immutable.
begin;
create table if not exists public.vault_manifests (
  user_id uuid primary key references auth.users(id) on delete cascade,
  revision bigint not null default 1 check (revision > 0),
  entries jsonb not null default '{}'::jsonb check (jsonb_typeof(entries) = 'object'),
  updated_at timestamptz not null default now()
);
alter table public.vault_manifests enable row level security;
revoke all on public.vault_manifests from anon, authenticated;
grant select on public.vault_manifests to authenticated;
create policy "Owner reads own manifest" on public.vault_manifests
  for select to authenticated using ((select auth.uid()) = user_id);

create or replace function public.commit_vault_manifest(expected_revision bigint, new_entries jsonb)
returns bigint language plpgsql security definer set search_path = '' as $$
declare
  v_owner uuid := auth.uid();
  result bigint;
  item record;
begin
  if v_owner is null then raise exception 'Authentication required' using errcode = '42501'; end if;
  if expected_revision < 0 or jsonb_typeof(new_entries) is distinct from 'object'
     or octet_length(new_entries::text) > 4194304 then
    raise exception 'Invalid manifest' using errcode = '22023';
  end if;
  for item in select key, value from jsonb_each_text(new_entries) loop
    if item.key !~ '^(scraps|notes|assets|expenses)/' or item.key ~ '(^|/)\.\.?(/|$)'
       or item.key ~ '[\\[:cntrl:]]' or length(item.key) > 1024
       or (item.value !~ '^[a-f0-9]{64}$' and item.value <> 'directory') then
      raise exception 'Invalid manifest entry' using errcode = '22023';
    end if;
    if item.value <> 'directory' and not exists (
      select 1 from storage.objects where bucket_id = 'vault-blobs'
        and name = v_owner::text || '/' || item.value
    ) then
      raise exception 'Missing blob' using errcode = '22023';
    end if;
  end loop;
  if expected_revision = 0 then
    insert into public.vault_manifests(user_id, revision, entries)
    values (v_owner, 1, new_entries) on conflict do nothing returning revision into result;
  else
    update public.vault_manifests set entries = new_entries, revision = revision + 1, updated_at = now()
    where user_id = v_owner and revision = expected_revision returning revision into result;
  end if;
  if result is null then
    raise exception 'Another device synchronized first. Please retry.' using errcode = '40001';
  end if;
  return result;
end;
$$;
revoke all on function public.commit_vault_manifest(bigint, jsonb) from public, anon;
grant execute on function public.commit_vault_manifest(bigint, jsonb) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit)
values ('vault-blobs', 'vault-blobs', false, 26214400)
on conflict (id) do nothing;
create policy "Owner reads own blobs" on storage.objects for select to authenticated
  using (bucket_id = 'vault-blobs' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Owner creates immutable blobs" on storage.objects for insert to authenticated
  with check (bucket_id = 'vault-blobs'
    and name ~ ('^' || (select auth.uid())::text || '/[a-f0-9]{64}$'));
commit;
