-- Comprehensive fix for storage.objects RLS policies - remove all problematic policies and create simple ones

-- First, drop ALL existing policies on storage.objects
DO $$
DECLARE
    policy_name TEXT;
BEGIN
    FOR policy_name IN 
        SELECT policyname FROM pg_policies 
        WHERE tablename = 'objects' AND schemaname = 'storage'
    LOOP
        EXECUTE 'DROP POLICY IF EXISTS "' || policy_name || '" ON storage.objects';
    END LOOP;
END $$;

-- Ensure chat-media bucket exists
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-media', 'chat-media', false)
ON CONFLICT (id) DO UPDATE SET name = 'chat-media', public = false;

-- Create ultra-simple policies that don't check owner_id or other problematic conditions

-- Allow authenticated users to INSERT files into chat-media bucket
CREATE POLICY "storage_insert_authenticated"
  ON storage.objects
  FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'chat-media');

-- Allow authenticated users to SELECT files from chat-media bucket
CREATE POLICY "storage_select_authenticated"
  ON storage.objects
  FOR SELECT
  TO authenticated
  USING (bucket_id = 'chat-media');

-- Allow authenticated users to UPDATE files in chat-media bucket
CREATE POLICY "storage_update_authenticated"
  ON storage.objects
  FOR UPDATE
  TO authenticated
  USING (bucket_id = 'chat-media')
  WITH CHECK (bucket_id = 'chat-media');

-- Allow authenticated users to DELETE files from chat-media bucket
CREATE POLICY "storage_delete_authenticated"
  ON storage.objects
  FOR DELETE
  TO authenticated
  USING (bucket_id = 'chat-media');

-- Allow service_role to do anything
CREATE POLICY "storage_service_role_all"
  ON storage.objects
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
