-- The app's pull sync runs, per table:
--   select * from <table>
--   where user_id = :me and updated_at > :lastPulledAt
--   order by updated_at
-- A composite (user_id, updated_at) index serves the filter and the ordering
-- in one scan. The existing transactions_user_id_idx is left in place.

create index if not exists transactions_user_updated_idx
  on public.transactions (user_id, updated_at);

create index if not exists categories_user_updated_idx
  on public.categories (user_id, updated_at);
