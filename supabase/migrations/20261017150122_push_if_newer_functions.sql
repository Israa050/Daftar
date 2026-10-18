-- Push a create/update only if the server row is not newer.
--
-- The client used an unconditional upsert, so a stale offline edit could
-- overwrite a newer edit made on another device before the pull ever saw it.
-- These functions apply last-write-wins on the server: the write happens only
-- when the stored updated_at is not newer than the pushed one. A rejected stale
-- write is a silent no-op, so the client still dequeues the entry and the pull
-- that follows brings the newer row down.
--
-- <= (not <) on purpose: a retried push of the same edit has an equal
-- updated_at and must still succeed.
--
-- security invoker keeps Row Level Security in force; user_id comes from
-- auth.uid(), so a caller can only write its own rows. Deletes are unchanged.

create or replace function public.push_category(
  p_id         uuid,
  p_name       text,
  p_color_hex  text,
  p_updated_at timestamptz
)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.categories (id, user_id, name, color_hex, updated_at)
  values (p_id, auth.uid(), p_name, p_color_hex, p_updated_at)
  on conflict (id) do update
    set name       = excluded.name,
        color_hex  = excluded.color_hex,
        updated_at = excluded.updated_at
    where public.categories.updated_at <= excluded.updated_at;
$$;

create or replace function public.push_transaction(
  p_id           uuid,
  p_amount_minor integer,
  p_type         text,
  p_note         text,
  p_category_id  uuid,
  p_occurred_at  timestamptz,
  p_created_at   timestamptz,
  p_updated_at   timestamptz
)
returns void
language sql
security invoker
set search_path = ''
as $$
  insert into public.transactions (
    id, user_id, amount_minor, type, note, category_id,
    occurred_at, created_at, updated_at
  )
  values (
    p_id, auth.uid(), p_amount_minor, p_type, p_note, p_category_id,
    p_occurred_at, p_created_at, p_updated_at
  )
  on conflict (id) do update
    set amount_minor = excluded.amount_minor,
        type         = excluded.type,
        note         = excluded.note,
        category_id  = excluded.category_id,
        occurred_at  = excluded.occurred_at,
        updated_at   = excluded.updated_at
    where public.transactions.updated_at <= excluded.updated_at;
$$;

-- Only signed-in users (anonymous sign-ins use the authenticated role) may call
-- them.
revoke execute on function public.push_category(uuid, text, text, timestamptz)
  from public, anon;
grant execute on function public.push_category(uuid, text, text, timestamptz)
  to authenticated;

revoke execute on function public.push_transaction(
  uuid, integer, text, text, uuid, timestamptz, timestamptz, timestamptz
) from public, anon;
grant execute on function public.push_transaction(
  uuid, integer, text, text, uuid, timestamptz, timestamptz, timestamptz
) to authenticated;
