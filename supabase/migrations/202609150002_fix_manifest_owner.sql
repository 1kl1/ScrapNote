-- Disambiguate the PL/pgSQL owner from storage.objects.owner.
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
