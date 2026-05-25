-- ============================================================
-- Migration 002: Row Level Security Policies
-- (idempotent — safe to re-run)
-- ============================================================

-- ============================================================
-- Grant table access to roles (required for RLS to work)
-- ============================================================
grant usage on schema public to anon, authenticated;

grant select, insert, update, delete on public.users                    to authenticated;
grant select, insert, update, delete on public.conversations            to authenticated;
grant select, insert, update, delete on public.conversation_participants to authenticated;
grant select, insert, update, delete on public.groups                   to authenticated;
grant select, insert, update, delete on public.group_members            to authenticated;
grant select, insert, update, delete on public.messages                 to authenticated;
grant select, insert, update, delete on public.message_reads            to authenticated;
grant select, insert, update, delete on public.attachments              to authenticated;
grant select, insert, update, delete on public.calls                    to authenticated;
grant select, insert, update, delete on public.call_participants        to authenticated;
grant select, insert, update, delete on public.notifications            to authenticated;
grant select, insert, update, delete on public.typing_indicators        to authenticated;

-- ============================================================
-- Enable RLS on all tables
-- ============================================================
alter table public.users                    enable row level security;
alter table public.conversations            enable row level security;
alter table public.conversation_participants enable row level security;
alter table public.groups                   enable row level security;
alter table public.group_members            enable row level security;
alter table public.messages                 enable row level security;
alter table public.message_reads            enable row level security;
alter table public.attachments              enable row level security;
alter table public.calls                    enable row level security;
alter table public.call_participants        enable row level security;
alter table public.notifications            enable row level security;
alter table public.typing_indicators        enable row level security;

-- ============================================================
-- Helper: is user a participant in conversation?
-- ============================================================
create or replace function public.is_conversation_participant(conv_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from conversation_participants
    where conversation_id = conv_id and user_id = auth.uid()
  );
$$;

-- ============================================================
-- USERS
-- ============================================================
drop policy if exists "users_select" on public.users;
drop policy if exists "users_update" on public.users;

create policy "users_select" on public.users
  for select to authenticated using (true);

create policy "users_update" on public.users
  for update to authenticated using (id = auth.uid());

-- ============================================================
-- CONVERSATIONS
-- ============================================================
drop policy if exists "conversations_select" on public.conversations;
drop policy if exists "conversations_insert" on public.conversations;

create policy "conversations_select" on public.conversations
  for select to authenticated
  using (is_conversation_participant(id));

create policy "conversations_insert" on public.conversations
  for insert to authenticated
  with check (created_by = auth.uid());

-- ============================================================
-- CONVERSATION PARTICIPANTS
-- ============================================================
drop policy if exists "cp_select" on public.conversation_participants;
drop policy if exists "cp_insert" on public.conversation_participants;
drop policy if exists "cp_update" on public.conversation_participants;

create policy "cp_select" on public.conversation_participants
  for select to authenticated
  using (is_conversation_participant(conversation_id));

create policy "cp_insert" on public.conversation_participants
  for insert to authenticated
  with check (
    user_id = auth.uid()
    or exists (
      select 1 from conversation_participants admins
      where admins.conversation_id = conversation_id
        and admins.user_id = auth.uid()
        and admins.is_admin = true
    )
  );

create policy "cp_update" on public.conversation_participants
  for update to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from conversation_participants admins
      where admins.conversation_id = conversation_id
        and admins.user_id = auth.uid()
        and admins.is_admin = true
    )
  );

-- ============================================================
-- GROUPS
-- ============================================================
drop policy if exists "groups_select" on public.groups;
drop policy if exists "groups_insert" on public.groups;
drop policy if exists "groups_update" on public.groups;

create policy "groups_select" on public.groups
  for select to authenticated
  using (
    exists (
      select 1 from group_members
      where group_id = id and user_id = auth.uid()
    )
  );

create policy "groups_insert" on public.groups
  for insert to authenticated
  with check (created_by = auth.uid());

create policy "groups_update" on public.groups
  for update to authenticated
  using (
    exists (
      select 1 from group_members
      where group_id = id and user_id = auth.uid() and is_admin = true
    )
  );

-- ============================================================
-- GROUP MEMBERS
-- ============================================================
drop policy if exists "gm_select" on public.group_members;
drop policy if exists "gm_insert" on public.group_members;
drop policy if exists "gm_delete" on public.group_members;

create policy "gm_select" on public.group_members
  for select to authenticated
  using (
    exists (
      select 1 from group_members gm2
      where gm2.group_id = group_id and gm2.user_id = auth.uid()
    )
  );

create policy "gm_insert" on public.group_members
  for insert to authenticated
  with check (
    added_by = auth.uid()
    and (
      auth.uid() = (select created_by from groups where id = group_id)
      or exists (
        select 1 from group_members admins
        where admins.group_id = group_id and admins.user_id = auth.uid() and admins.is_admin = true
      )
    )
  );

create policy "gm_delete" on public.group_members
  for delete to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from group_members admins
      where admins.group_id = group_id and admins.user_id = auth.uid() and admins.is_admin = true
    )
  );

-- ============================================================
-- MESSAGES
-- ============================================================
drop policy if exists "messages_select" on public.messages;
drop policy if exists "messages_insert" on public.messages;
drop policy if exists "messages_update" on public.messages;

create policy "messages_select" on public.messages
  for select to authenticated
  using (is_conversation_participant(conversation_id));

create policy "messages_insert" on public.messages
  for insert to authenticated
  with check (
    sender_id = auth.uid()
    and is_conversation_participant(conversation_id)
  );

create policy "messages_update" on public.messages
  for update to authenticated
  using (
    sender_id = auth.uid()
    or exists (
      select 1 from conversation_participants cp
      where cp.conversation_id = conversation_id
        and cp.user_id = auth.uid()
        and cp.is_admin = true
    )
  );

-- ============================================================
-- MESSAGE READS
-- ============================================================
drop policy if exists "mr_select" on public.message_reads;
drop policy if exists "mr_insert" on public.message_reads;

create policy "mr_select" on public.message_reads
  for select to authenticated
  using (
    exists (
      select 1 from messages m
      where m.id = message_id
        and is_conversation_participant(m.conversation_id)
    )
  );

create policy "mr_insert" on public.message_reads
  for insert to authenticated
  with check (user_id = auth.uid());

-- ============================================================
-- ATTACHMENTS
-- ============================================================
drop policy if exists "attachments_select" on public.attachments;
drop policy if exists "attachments_insert" on public.attachments;

create policy "attachments_select" on public.attachments
  for select to authenticated
  using (
    exists (
      select 1 from messages m
      where m.id = message_id
        and is_conversation_participant(m.conversation_id)
    )
  );

create policy "attachments_insert" on public.attachments
  for insert to authenticated
  with check (
    exists (
      select 1 from messages m
      where m.id = message_id
        and m.sender_id = auth.uid()
    )
  );

-- ============================================================
-- CALLS
-- ============================================================
drop policy if exists "calls_select" on public.calls;
drop policy if exists "calls_insert" on public.calls;
drop policy if exists "calls_update" on public.calls;

create policy "calls_select" on public.calls
  for select to authenticated
  using (is_conversation_participant(conversation_id));

create policy "calls_insert" on public.calls
  for insert to authenticated
  with check (
    initiator_id = auth.uid()
    and is_conversation_participant(conversation_id)
  );

create policy "calls_update" on public.calls
  for update to authenticated
  using (is_conversation_participant(conversation_id));

-- ============================================================
-- CALL PARTICIPANTS
-- ============================================================
drop policy if exists "callp_select" on public.call_participants;
drop policy if exists "callp_insert" on public.call_participants;
drop policy if exists "callp_update" on public.call_participants;

create policy "callp_select" on public.call_participants
  for select to authenticated
  using (
    exists (
      select 1 from calls c
      where c.id = call_id
        and is_conversation_participant(c.conversation_id)
    )
  );

create policy "callp_insert" on public.call_participants
  for insert to authenticated
  with check (user_id = auth.uid());

create policy "callp_update" on public.call_participants
  for update to authenticated
  using (user_id = auth.uid());

-- ============================================================
-- NOTIFICATIONS
-- ============================================================
drop policy if exists "notifications_select" on public.notifications;
drop policy if exists "notifications_update" on public.notifications;

create policy "notifications_select" on public.notifications
  for select to authenticated using (user_id = auth.uid());

create policy "notifications_update" on public.notifications
  for update to authenticated using (user_id = auth.uid());

-- ============================================================
-- TYPING INDICATORS
-- ============================================================
drop policy if exists "typing_select" on public.typing_indicators;
drop policy if exists "typing_insert" on public.typing_indicators;
drop policy if exists "typing_update" on public.typing_indicators;
drop policy if exists "typing_delete" on public.typing_indicators;

create policy "typing_select" on public.typing_indicators
  for select to authenticated
  using (is_conversation_participant(conversation_id));

create policy "typing_insert" on public.typing_indicators
  for insert to authenticated
  with check (
    user_id = auth.uid()
    and is_conversation_participant(conversation_id)
  );

create policy "typing_update" on public.typing_indicators
  for update to authenticated
  using (user_id = auth.uid());

create policy "typing_delete" on public.typing_indicators
  for delete to authenticated
  using (user_id = auth.uid());
