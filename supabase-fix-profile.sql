-- Run this once in Supabase SQL Editor for an existing installation.
-- It fixes recursive RLS policies and creates missing profile rows.

create or replace function public.current_user_role()
returns public.user_role
language sql
stable
security definer
set search_path = public
as $$
  select role from public.profiles where id = auth.uid();
$$;

revoke all on function public.current_user_role() from public;
grant execute on function public.current_user_role() to authenticated;

-- Backfill users created before the profile trigger existed.
insert into public.profiles (id, full_name, email, role)
select
  u.id,
  coalesce(u.raw_user_meta_data->>'full_name', split_part(u.email, '@', 1)),
  lower(u.email),
  case
    when lower(u.email) in ('admin@linkotech.com', 'admin@assignlinkotech.com')
      then 'admin'::public.user_role
    else 'member'::public.user_role
  end
from auth.users u
where u.email is not null
on conflict (id) do update
set email = excluded.email,
    full_name = coalesce(nullif(public.profiles.full_name, ''), excluded.full_name);

-- Recreate policies without querying profiles recursively from a profiles policy.
drop policy if exists "users can read allowed profiles" on public.profiles;
drop policy if exists "admins can change roles" on public.profiles;
drop policy if exists "users can read allowed entries" on public.time_entries;

create policy "users can read allowed profiles"
on public.profiles for select
to authenticated
using (
  id = auth.uid()
  or public.current_user_role() in ('manager', 'admin')
);

create policy "admins can change roles"
on public.profiles for update
to authenticated
using (public.current_user_role() = 'admin')
with check (public.current_user_role() = 'admin');

create policy "users can read allowed entries"
on public.time_entries for select
to authenticated
using (
  user_id = auth.uid()
  or public.current_user_role() in ('manager', 'admin')
);

-- Keep the intended primary admin account promoted when it exists.
update public.profiles
set role = 'admin'
where lower(email) in ('admin@linkotech.com', 'admin@assignlinkotech.com');
