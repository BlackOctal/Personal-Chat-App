-- ============================================================
-- Migration 004: Storage buckets + realtime fixes
-- Run this in the Supabase SQL editor (Dashboard → SQL Editor → New query)
-- ============================================================

-- ============================================================
-- Add message_reads to realtime publication
-- (Required for blue read-receipt ticks to update in real-time)
-- ============================================================
alter publication supabase_realtime add table public.message_reads;

-- ============================================================
-- Storage buckets
-- ============================================================
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('avatars',      'avatars',      true,  5242880,   array['image/jpeg','image/png','image/webp','image/gif']),
  ('group-images', 'group-images', true,  5242880,   array['image/jpeg','image/png','image/webp']),
  ('media',        'media',        false, 104857600, null)
on conflict (id) do nothing;

-- ============================================================
-- Storage policies — avatars (public bucket)
-- ============================================================
drop policy if exists "Avatars public read"         on storage.objects;
drop policy if exists "Avatars user upload"         on storage.objects;
drop policy if exists "Avatars user update"         on storage.objects;
drop policy if exists "Avatars user delete"         on storage.objects;

create policy "Avatars public read"
  on storage.objects for select
  using (bucket_id = 'avatars');

create policy "Avatars user upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Avatars user update"
  on storage.objects for update to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Avatars user delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ============================================================
-- Storage policies — group-images (public bucket)
-- ============================================================
drop policy if exists "Group images public read"   on storage.objects;
drop policy if exists "Group images user upload"   on storage.objects;

create policy "Group images public read"
  on storage.objects for select
  using (bucket_id = 'group-images');

create policy "Group images user upload"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'group-images');

create policy "Group images user update"
  on storage.objects for update to authenticated
  using (bucket_id = 'group-images');

-- ============================================================
-- Storage policies — media (private bucket: voice, images, videos)
-- ============================================================
drop policy if exists "Media authenticated upload" on storage.objects;
drop policy if exists "Media authenticated read"   on storage.objects;
drop policy if exists "Media owner delete"         on storage.objects;

create policy "Media authenticated upload"
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "Media authenticated read"
  on storage.objects for select to authenticated
  using (bucket_id = 'media');

create policy "Media owner delete"
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'media'
    and (storage.foldername(name))[1] = auth.uid()::text
  );
