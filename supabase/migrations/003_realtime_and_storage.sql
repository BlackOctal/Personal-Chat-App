-- ============================================================
-- Migration 003: Realtime subscriptions and Storage buckets
-- ============================================================

-- Enable Realtime for relevant tables
alter publication supabase_realtime add table public.messages;
alter publication supabase_realtime add table public.typing_indicators;
alter publication supabase_realtime add table public.calls;
alter publication supabase_realtime add table public.call_participants;
alter publication supabase_realtime add table public.users;
alter publication supabase_realtime add table public.conversation_participants;

-- ============================================================
-- Storage buckets
-- Note: buckets are created via Supabase dashboard or API,
-- this script documents the expected configuration.
-- Run these via Supabase dashboard SQL editor or via supabase CLI:
--   supabase storage create-bucket media --public=false
--   supabase storage create-bucket avatars --public=true
--   supabase storage create-bucket group-images --public=true
-- ============================================================

-- Storage RLS policies (applied in Supabase dashboard)
-- Bucket: avatars (public read, auth user owns their file)
-- Bucket: group-images (public read, group admin can write)
-- Bucket: media (private, only conversation participants can read)

-- These are documented here for reference; configure via Supabase dashboard
-- or storage API calls in your setup script.

-- ============================================================
-- Useful views
-- ============================================================

create or replace view public.conversation_list as
select
  c.id,
  c.type,
  c.group_id,
  c.created_by,
  c.created_at,
  c.updated_at,
  c.last_message_at,
  cp.user_id as participant_user_id,
  cp.last_read_at,
  cp.is_admin,
  cp.muted_until,
  (
    select count(*) from messages m
    where m.conversation_id = c.id
      and m.created_at > coalesce(cp.last_read_at, '1970-01-01')
      and m.sender_id != cp.user_id
      and m.deleted_for_everyone = false
  ) as unread_count,
  (
    select row_to_json(m.*) from messages m
    where m.conversation_id = c.id
      and m.deleted_for_everyone = false
    order by m.created_at desc
    limit 1
  ) as last_message
from conversations c
join conversation_participants cp on cp.conversation_id = c.id;
