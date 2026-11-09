-- =========================================================
-- Bagaicha Villa — Supabase Database Schema
-- =========================================================
-- Run this in the Supabase SQL editor (or via `supabase db push`).
-- Assumes Supabase Auth is used for login (auth.users), with a
-- "profiles" table extending it to carry role + role-specific IDs.
--
-- AUTH APPROACH:
--   Guests   -> Supabase phone-OTP auth (phone number is the identity)
--   Staff    -> Supabase email/password auth, using an internal email
--               like "bv014@staff.bagaichavilla.internal" mapped to
--               their staff number, so login UI can still just ask
--               for "staff number" and translate it behind the scenes
--   Admin    -> Supabase email/password auth (username mapped to email
--               the same way, or a real email if you prefer)
-- =========================================================

-- ---------- Extensions ----------
create extension if not exists pgcrypto;

-- ---------- Enums ----------
create type user_role as enum ('guest', 'staff', 'admin');
create type order_source as enum ('customer_online', 'staff_billing');
create type order_status as enum ('pending', 'preparing', 'ready', 'completed', 'cancelled');
create type payment_status as enum ('pending', 'paid', 'failed');
create type payment_method as enum ('cash', 'esewa', 'khalti', 'bank_transfer');
create type menu_category as enum ('Starters', 'Mains', 'Drinks', 'Desserts');
create type appearance_tab as enum ('home', 'menu', 'order', 'social', 'profile');

-- =========================================================
-- PROFILES  (one row per auth.users row, regardless of role)
-- =========================================================
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role user_role not null,
  full_name text not null,
  phone text unique,               -- guests
  staff_number text unique,        -- staff
  username text unique,            -- admin
  avatar_url text,
  bio text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_profiles_role on profiles(role);

-- =========================================================
-- MENU
-- =========================================================
create table menu_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  price numeric(10,2) not null check (price >= 0),
  category menu_category not null,
  photo_url text,
  is_available boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- =========================================================
-- INVENTORY
-- =========================================================
create table inventory_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  category text not null,
  unit text not null,              -- kg, g, litre, ml, pcs
  stock numeric(10,2) not null default 0 check (stock >= 0),
  reorder_threshold numeric(10,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Which inventory items a dish consumes, and how much per order
create table recipe_links (
  id uuid primary key default gen_random_uuid(),
  menu_item_id uuid not null references menu_items(id) on delete cascade,
  inventory_item_id uuid not null references inventory_items(id) on delete cascade,
  quantity_used numeric(10,3) not null check (quantity_used > 0),
  unique (menu_item_id, inventory_item_id)
);

-- Manual stock changes (restock, correction, audit adjustment)
create table inventory_adjustments (
  id uuid primary key default gen_random_uuid(),
  inventory_item_id uuid not null references inventory_items(id) on delete cascade,
  change_amount numeric(10,2) not null,   -- positive = added, negative = deducted
  reason text not null,                   -- 'restock', 'sale_deduction', 'audit_correction', 'manual'
  recorded_by uuid references profiles(id),
  created_at timestamptz not null default now()
);

-- =========================================================
-- ORDERS / BILLING
-- =========================================================
create table orders (
  id uuid primary key default gen_random_uuid(),
  order_number text unique not null,          -- e.g. 'BV-0042', generate in app or trigger
  source order_source not null,               -- who created it
  guest_id uuid references profiles(id),      -- set when a guest ordered online
  staff_id uuid references profiles(id),      -- set when staff created/handled the bill
  status order_status not null default 'pending',
  payment_status payment_status not null default 'pending',
  payment_method payment_method,
  subtotal numeric(10,2) not null default 0,
  tax numeric(10,2) not null default 0,
  total numeric(10,2) not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  menu_item_id uuid references menu_items(id),
  name_snapshot text not null,        -- dish name at time of order (survives menu edits)
  price_snapshot numeric(10,2) not null,
  quantity int not null check (quantity > 0)
);

create table payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references orders(id) on delete cascade,
  method payment_method not null,
  amount numeric(10,2) not null,
  transaction_ref text,               -- gateway reference for eSewa/Khalti/bank transfer
  status payment_status not null default 'pending',
  created_at timestamptz not null default now()
);

-- =========================================================
-- SOCIAL FEED
-- =========================================================
create table posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references profiles(id) on delete cascade,
  text_content text,
  photo_url text,
  is_hidden boolean not null default false,   -- admin moderation
  created_at timestamptz not null default now()
);

create table comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references posts(id) on delete cascade,
  author_id uuid not null references profiles(id) on delete cascade,
  text_content text not null,
  is_hidden boolean not null default false,   -- admin moderation
  created_at timestamptz not null default now()
);

-- =========================================================
-- APPEARANCE SETTINGS (admin-managed backgrounds per tab)
-- =========================================================
create table appearance_settings (
  tab appearance_tab primary key,
  image_url text,
  updated_at timestamptz not null default now()
);

insert into appearance_settings (tab) values
  ('home'), ('menu'), ('order'), ('social'), ('profile');

-- =========================================================
-- ROW LEVEL SECURITY
-- =========================================================
alter table profiles enable row level security;
alter table menu_items enable row level security;
alter table inventory_items enable row level security;
alter table recipe_links enable row level security;
alter table inventory_adjustments enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table payments enable row level security;
alter table posts enable row level security;
alter table comments enable row level security;
alter table appearance_settings enable row level security;

-- ---- Helper: check caller's role ----
create or replace function current_role_is(target_role user_role)
returns boolean as $$
  select exists (
    select 1 from profiles
    where id = auth.uid() and role = target_role
  );
$$ language sql stable security definer;

-- ---- Profiles ----
create policy "profiles: read own" on profiles
  for select using (id = auth.uid());
create policy "profiles: staff/admin read all" on profiles
  for select using (current_role_is('staff') or current_role_is('admin'));
create policy "profiles: update own" on profiles
  for update using (id = auth.uid());

-- ---- Menu (everyone can read; only admin can write) ----
create policy "menu: public read" on menu_items
  for select using (true);
create policy "menu: admin write" on menu_items
  for all using (current_role_is('admin')) with check (current_role_is('admin'));

-- ---- Inventory (staff + admin only) ----
create policy "inventory: staff/admin read" on inventory_items
  for select using (current_role_is('staff') or current_role_is('admin'));
create policy "inventory: admin write" on inventory_items
  for all using (current_role_is('admin')) with check (current_role_is('admin'));
create policy "recipe links: staff/admin read" on recipe_links
  for select using (current_role_is('staff') or current_role_is('admin'));
create policy "recipe links: admin write" on recipe_links
  for all using (current_role_is('admin')) with check (current_role_is('admin'));
create policy "adjustments: staff/admin read" on inventory_adjustments
  for select using (current_role_is('staff') or current_role_is('admin'));
create policy "adjustments: staff/admin write" on inventory_adjustments
  for insert with check (current_role_is('staff') or current_role_is('admin'));

-- ---- Orders ----
create policy "orders: guest reads own" on orders
  for select using (guest_id = auth.uid());
create policy "orders: staff/admin read all" on orders
  for select using (current_role_is('staff') or current_role_is('admin'));
create policy "orders: guest creates own" on orders
  for insert with check (guest_id = auth.uid() or current_role_is('staff'));
create policy "orders: staff/admin update" on orders
  for update using (current_role_is('staff') or current_role_is('admin'));

create policy "order_items: follows order visibility" on order_items
  for select using (
    exists (select 1 from orders o where o.id = order_id and
      (o.guest_id = auth.uid() or current_role_is('staff') or current_role_is('admin')))
  );
create policy "order_items: insert with order" on order_items
  for insert with check (
    exists (select 1 from orders o where o.id = order_id and
      (o.guest_id = auth.uid() or current_role_is('staff')))
  );

create policy "payments: follows order visibility" on payments
  for select using (
    exists (select 1 from orders o where o.id = order_id and
      (o.guest_id = auth.uid() or current_role_is('staff') or current_role_is('admin')))
  );
create policy "payments: insert with order" on payments
  for insert with check (
    exists (select 1 from orders o where o.id = order_id and
      (o.guest_id = auth.uid() or current_role_is('staff')))
  );

-- ---- Social feed (public read of non-hidden, own write, admin moderates) ----
create policy "posts: public read non-hidden" on posts
  for select using (is_hidden = false or current_role_is('admin'));
create policy "posts: author writes own" on posts
  for insert with check (author_id = auth.uid());
create policy "posts: author updates own" on posts
  for update using (author_id = auth.uid());
create policy "posts: admin moderates" on posts
  for update using (current_role_is('admin'));
create policy "posts: admin deletes" on posts
  for delete using (current_role_is('admin'));

create policy "comments: public read non-hidden" on comments
  for select using (is_hidden = false or current_role_is('admin'));
create policy "comments: author writes own" on comments
  for insert with check (author_id = auth.uid());
create policy "comments: admin moderates" on comments
  for update using (current_role_is('admin'));
create policy "comments: admin deletes" on comments
  for delete using (current_role_is('admin'));

-- ---- Appearance settings (public read, admin write) ----
create policy "appearance: public read" on appearance_settings
  for select using (true);
create policy "appearance: admin write" on appearance_settings
  for all using (current_role_is('admin')) with check (current_role_is('admin'));

-- =========================================================
-- TRIGGER: keep updated_at fresh
-- =========================================================
create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

create trigger trg_profiles_updated before update on profiles
  for each row execute function set_updated_at();
create trigger trg_menu_items_updated before update on menu_items
  for each row execute function set_updated_at();
create trigger trg_inventory_items_updated before update on inventory_items
  for each row execute function set_updated_at();
create trigger trg_orders_updated before update on orders
  for each row execute function set_updated_at();

-- =========================================================
-- TRIGGER: auto-deduct inventory when an order is marked completed
-- (Optional but recommended — keeps stock accurate automatically)
-- =========================================================
create or replace function deduct_inventory_for_order()
returns trigger as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    update inventory_items ii
    set stock = ii.stock - (rl.quantity_used * oi.quantity)
    from order_items oi
    join recipe_links rl on rl.menu_item_id = oi.menu_item_id
    where oi.order_id = new.id and ii.id = rl.inventory_item_id;

    insert into inventory_adjustments (inventory_item_id, change_amount, reason, recorded_by)
    select rl.inventory_item_id, -(rl.quantity_used * oi.quantity), 'sale_deduction', new.staff_id
    from order_items oi
    join recipe_links rl on rl.menu_item_id = oi.menu_item_id
    where oi.order_id = new.id;
  end if;
  return new;
end;
$$ language plpgsql security definer;

create trigger trg_deduct_inventory after update on orders
  for each row execute function deduct_inventory_for_order();
