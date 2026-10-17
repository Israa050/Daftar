-- Baseline: the public schema as it exists on the live project, reconstructed
-- from queries against information_schema, pg_constraint, pg_tables,
-- pg_policies and pg_indexes (no Docker, so not a pg_dump).
--
-- This is already applied on the live project. Register it there with
--   supabase migration repair --status applied 20261017083716
-- instead of pushing it. Every statement is idempotent, so running it against
-- an existing database changes nothing.
--
-- updated_at has no trigger by design: the client sets it explicitly, so
-- last-write-wins compares when an edit happened on the device, not when it
-- happened to reach the server.

create table if not exists public.categories (
  id         uuid primary key,
  user_id    uuid not null references auth.users (id) on delete cascade,
  name       text not null,
  color_hex  text,
  updated_at timestamptz not null default now(),
  constraint categories_user_id_name_key unique (user_id, name)
);

create table if not exists public.transactions (
  id           uuid primary key,
  user_id      uuid not null references auth.users (id) on delete cascade,
  amount_minor integer not null,
  type         text not null check (type in ('income', 'expense')),
  note         text,
  category_id  uuid references public.categories (id) on delete set null,
  occurred_at  timestamptz not null,
  created_at   timestamptz not null,
  updated_at   timestamptz not null default now()
);

create index if not exists transactions_user_id_idx
  on public.transactions (user_id);
create index if not exists transactions_category_id_idx
  on public.transactions (category_id);

alter table public.categories enable row level security;
alter table public.transactions enable row level security;

drop policy if exists "own transactions only" on public.transactions;
create policy "own transactions only" on public.transactions
  for all to public
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "own categories only" on public.categories;
create policy "own categories only" on public.categories
  for all to public
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
