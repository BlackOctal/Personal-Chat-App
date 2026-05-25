-- ============================================================
-- Migration 005: Fix conversation list visibility
-- Run this in the Supabase SQL editor (Dashboard → SQL Editor → New query)
-- ============================================================

-- The original cp_select policy relied solely on is_conversation_participant(),
-- which queries conversation_participants itself. In some edge cases (first-time
-- users, timing windows after a new conversation is created) this can return
-- false for the user's own rows, making the entire conversations list disappear.
--
-- Fix: explicitly allow users to ALWAYS see their own participation rows using
-- a direct user_id = auth.uid() check, while still allowing them to see
-- co-participants via the function (needed to display the other user's info).

drop policy if exists "cp_select" on public.conversation_participants;

create policy "cp_select" on public.conversation_participants
  for select to authenticated
  using (
    user_id = auth.uid()                            -- always see own rows (O(1), no recursion)
    or is_conversation_participant(conversation_id) -- see co-participants in shared conversations
  );
