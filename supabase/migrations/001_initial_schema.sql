-- ============================================================
-- Migration 001: Initial Schema
-- ============================================================

-- Enable extensions
create extension if not exists "uuid-ossp";
create extension if not exists "pg_trgm";

-- ============================================================
-- USERS
-- ============================================================
create table public.users (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null unique,
  username    text not null unique,
  full_name   text not null,
  avatar_url  text,
  about       text default 'Hey there! I am using ChatApp.',
  presence    text not null default 'offline' check (presence in ('online', 'offline', 'away')),
  last_seen   timestamptz not null default now(),
  fcm_token   text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Index for username search
create index users_username_trgm on public.users using gin (username gin_trgm_ops);
create index users_full_name_trgm on public.users using gin (full_name gin_trgm_ops);

-- ============================================================
-- CONVERSATIONS
-- ============================================================
create table public.conversations (
  id              uuid primary key default uuid_generate_v4(),
  type            text not null check (type in ('direct', 'group')),
  group_id        uuid,
  created_by      uuid not null references public.users(id) on delete cascade,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  last_message_at timestamptz
);

create index conversations_last_message_at on public.conversations (last_message_at desc nulls last);

-- ============================================================
-- CONVERSATION PARTICIPANTS
-- ============================================================
create table public.conversation_participants (
  id              uuid primary key default uuid_generate_v4(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.users(id) on delete cascade,
  joined_at       timestamptz not null default now(),
  last_read_at    timestamptz,
  is_admin        boolean not null default false,
  muted_until     timestamptz,
  unique (conversation_id, user_id)
);

create index cp_user_id on public.conversation_participants (user_id);
create index cp_conversation_id on public.conversation_participants (conversation_id);

-- ============================================================
-- GROUPS
-- ============================================================
create table public.groups (
  id              uuid primary key default uuid_generate_v4(),
  name            text not null,
  description     text,
  image_url       text,
  created_by      uuid not null references public.users(id) on delete cascade,
  conversation_id uuid references public.conversations(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

create index groups_name_trgm on public.groups using gin (name gin_trgm_ops);

-- Add FK from conversations to groups after both tables exist
alter table public.conversations
  add constraint fk_conversations_group
  foreign key (group_id) references public.groups(id) on delete cascade;

-- ============================================================
-- GROUP MEMBERS
-- ============================================================
create table public.group_members (
  id          uuid primary key default uuid_generate_v4(),
  group_id    uuid not null references public.groups(id) on delete cascade,
  user_id     uuid not null references public.users(id) on delete cascade,
  is_admin    boolean not null default false,
  joined_at   timestamptz not null default now(),
  added_by    uuid not null references public.users(id) on delete cascade,
  unique (group_id, user_id)
);

create index gm_group_id on public.group_members (group_id);
create index gm_user_id on public.group_members (user_id);

-- ============================================================
-- MESSAGES
-- ============================================================
create table public.messages (
  id                    uuid primary key default uuid_generate_v4(),
  conversation_id       uuid not null references public.conversations(id) on delete cascade,
  sender_id             uuid not null references public.users(id) on delete cascade,
  content               text,
  type                  text not null default 'text'
                          check (type in ('text','image','video','audio','voice','file','link','system')),
  reply_to_id           uuid references public.messages(id) on delete set null,
  metadata              jsonb,
  deleted_for_everyone  boolean not null default false,
  deleted_for_sender    boolean not null default false,
  is_pinned             boolean not null default false,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now()
);

create index messages_conversation_id on public.messages (conversation_id, created_at desc);
create index messages_sender_id on public.messages (sender_id);
create index messages_content_trgm on public.messages using gin (content gin_trgm_ops)
  where content is not null and deleted_for_everyone = false;

-- ============================================================
-- MESSAGE READS
-- ============================================================
create table public.message_reads (
  message_id  uuid not null references public.messages(id) on delete cascade,
  user_id     uuid not null references public.users(id) on delete cascade,
  read_at     timestamptz not null default now(),
  primary key (message_id, user_id)
);

create index mr_user_id on public.message_reads (user_id);

-- ============================================================
-- ATTACHMENTS
-- ============================================================
create table public.attachments (
  id               uuid primary key default uuid_generate_v4(),
  message_id       uuid not null references public.messages(id) on delete cascade,
  storage_path     text not null,
  preview_path     text,
  mime_type        text not null,
  file_name        text not null,
  file_size        bigint not null,
  width            int,
  height           int,
  duration_seconds float,
  status           text not null default 'active' check (status in ('active', 'expired')),
  expires_at       timestamptz not null,
  created_at       timestamptz not null default now()
);

create index attachments_expires_at on public.attachments (expires_at) where status = 'active';

-- ============================================================
-- CALLS
-- ============================================================
create table public.calls (
  id               uuid primary key default uuid_generate_v4(),
  type             text not null check (type in ('voice', 'video')),
  conversation_id  uuid not null references public.conversations(id) on delete cascade,
  initiator_id     uuid not null references public.users(id) on delete cascade,
  status           text not null default 'ringing'
                     check (status in ('ringing','active','ended','missed','rejected')),
  started_at       timestamptz not null default now(),
  ended_at         timestamptz,
  duration_seconds int,
  created_at       timestamptz not null default now()
);

create index calls_conversation_id on public.calls (conversation_id, started_at desc);

-- ============================================================
-- CALL PARTICIPANTS
-- ============================================================
create table public.call_participants (
  id        uuid primary key default uuid_generate_v4(),
  call_id   uuid not null references public.calls(id) on delete cascade,
  user_id   uuid not null references public.users(id) on delete cascade,
  joined_at timestamptz,
  left_at   timestamptz,
  is_muted  boolean not null default false,
  unique (call_id, user_id)
);

-- ============================================================
-- NOTIFICATIONS
-- ============================================================
create table public.notifications (
  id          uuid primary key default uuid_generate_v4(),
  user_id     uuid not null references public.users(id) on delete cascade,
  type        text not null check (type in ('message','call','mention','group_invite')),
  title       text not null,
  body        text not null,
  data        jsonb,
  read        boolean not null default false,
  created_at  timestamptz not null default now()
);

create index notifications_user_id on public.notifications (user_id, created_at desc);

-- ============================================================
-- TYPING INDICATORS (ephemeral, not really a permanent table but useful for presence)
-- ============================================================
create table public.typing_indicators (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  user_id         uuid not null references public.users(id) on delete cascade,
  started_at      timestamptz not null default now(),
  primary key (conversation_id, user_id)
);

-- ============================================================
-- UPDATED_AT triggers
-- ============================================================
create or replace function update_updated_at_column()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger users_updated_at before update on public.users
  for each row execute function update_updated_at_column();

create trigger conversations_updated_at before update on public.conversations
  for each row execute function update_updated_at_column();

create trigger groups_updated_at before update on public.groups
  for each row execute function update_updated_at_column();

create trigger messages_updated_at before update on public.messages
  for each row execute function update_updated_at_column();

-- ============================================================
-- Function: create user profile on auth signup
-- ============================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  uname text;
begin
  -- Derive username from email
  uname := lower(split_part(new.email, '@', 1));
  -- Ensure uniqueness
  if exists (select 1 from public.users where username = uname) then
    uname := uname || '_' || substr(new.id::text, 1, 6);
  end if;

  insert into public.users (id, email, username, full_name, avatar_url)
  values (
    new.id,
    new.email,
    uname,
    coalesce(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', uname),
    new.raw_user_meta_data->>'avatar_url'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ============================================================
-- Function: update conversation last_message_at
-- ============================================================
create or replace function public.update_conversation_timestamp()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.conversations
  set last_message_at = new.created_at, updated_at = now()
  where id = new.conversation_id;
  return new;
end;
$$;

create trigger on_message_created
  after insert on public.messages
  for each row execute function public.update_conversation_timestamp();

-- ============================================================
-- Function: get or create direct conversation
-- ============================================================
create or replace function public.get_or_create_direct_conversation(other_user_id uuid)
returns uuid language plpgsql security definer set search_path = public as $$
declare
  conv_id uuid;
  me uuid := auth.uid();
begin
  -- Find existing direct conversation between the two users
  select c.id into conv_id
  from conversations c
  join conversation_participants cp1 on cp1.conversation_id = c.id and cp1.user_id = me
  join conversation_participants cp2 on cp2.conversation_id = c.id and cp2.user_id = other_user_id
  where c.type = 'direct'
  limit 1;

  if conv_id is null then
    insert into conversations (type, created_by)
    values ('direct', me)
    returning id into conv_id;

    insert into conversation_participants (conversation_id, user_id)
    values (conv_id, me), (conv_id, other_user_id);
  end if;

  return conv_id;
end;
$$;

-- ============================================================
-- Cleanup function: expire media older than 30 days
-- ============================================================
create or replace function public.expire_old_media()
returns void language plpgsql security definer set search_path = public as $$
begin
  update public.attachments
  set status = 'expired'
  where status = 'active'
    and expires_at < now();
end;
$$;
