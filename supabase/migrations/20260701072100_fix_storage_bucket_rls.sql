-- Fix Storage Bucket RLS policies for chat-media uploads

-- Drop ALL existing policies on storage.objects first
DROP POLICY IF EXISTS "Users can upload chat media" ON storage.objects;
DROP POLICY IF EXISTS "Users can read chat media" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own chat media" ON storage.objects;
DROP POLICY IF EXISTS "allow_authenticated_upload" ON storage.objects;
DROP POLICY IF EXISTS "allow_authenticated_read" ON storage.objects;
DROP POLICY IF EXISTS "allow_delete_own_media" ON storage.objects;
DROP POLICY IF EXISTS "allow_service_role_full" ON storage.objects;
DROP POLICY IF EXISTS "storage_insert_authenticated" ON storage.objects;
DROP POLICY IF EXISTS "storage_select_authenticated" ON storage.objects;
DROP POLICY IF EXISTS "storage_update_authenticated" ON storage.objects;
DROP POLICY IF EXISTS "storage_delete_authenticated" ON storage.objects;
DROP POLICY IF EXISTS "storage_service_role_all" ON storage.objects;

-- Ensure chat-media bucket exists
INSERT INTO storage.buckets (id, name, public) 
VALUES ('chat-media', 'chat-media', false)
ON CONFLICT (id) DO UPDATE SET name = 'chat-media', public = false;

-- Allow authenticated users to upload files
CREATE POLICY "storage_insert_authenticated"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'chat-media');

-- Allow authenticated users to read files from chat-media bucket
CREATE POLICY "storage_select_authenticated"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (bucket_id = 'chat-media');

-- Allow authenticated users to delete files
CREATE POLICY "storage_delete_authenticated"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (bucket_id = 'chat-media');

-- Allow service role full access
CREATE POLICY "storage_service_role_all"
  ON storage.objects
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
