create extension if not exists pgcrypto;

create type public.user_role as enum ('member', 'manager', 'admin');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  email text unique not null,
  role public.user_role not null default 'member',
  created_at timestamptz not null default now()
);

create table public.time_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  work_date date not null,
  start_time time not null,
  end_time time not null,
  duration_minutes integer not null check (duration_minutes > 0 and duration_minutes <= 1440),
  description text not null check (char_length(description) between 2 and 1200),
  created_at timestamptz not null default now(),
  constraint valid_time_range check (end_time > start_time)
);

create index time_entries_user_date_idx on public.time_entries(user_id, work_date desc);

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email, '@', 1)),
    lower(new.email),
    case when lower(new.email) = 'admin@linkotech.com' then 'admin'::public.user_role else 'member'::public.user_role end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

alter table public.profiles enable row level security;
alter table public.time_entries enable row level security;

create policy "users can read allowed profiles"
on public.profiles for select
to authenticated
using (
  id = auth.uid()
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('manager','admin'))
);

create policy "admins can change roles"
on public.profiles for update
to authenticated
using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'))
with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.role = 'admin'));

create policy "users can read allowed entries"
on public.time_entries for select
to authenticated
using (
  user_id = auth.uid()
  or exists (select 1 from public.profiles p where p.id = auth.uid() and p.role in ('manager','admin'))
);

create policy "users can create own entries"
on public.time_entries for insert
to authenticated
with check (user_id = auth.uid());

create policy "users can update own entries"
on public.time_entries for update
to authenticated
using (user_id = auth.uid())
with check (user_id = auth.uid());

create policy "users can delete own entries"
on public.time_entries for delete
to authenticated
using (user_id = auth.uid());

-- The first account registered with admin@linkotech.com becomes Admin automatically.
-- All other new accounts start as Employee (member).
-- Admins can promote users to Manager or Admin from the application.