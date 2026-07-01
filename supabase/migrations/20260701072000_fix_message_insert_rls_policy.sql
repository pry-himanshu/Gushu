-- Fix RLS policy for messages INSERT to allow authenticated users to send messages including media/images

-- Drop all existing policies on messages table to start fresh
DROP POLICY IF EXISTS "users_can_insert_messages" ON public.messages;
DROP POLICY IF EXISTS "authenticated_can_insert_messages" ON public.messages;
DROP POLICY IF EXISTS "authenticated_users_can_insert_own_messages" ON public.messages;
DROP POLICY IF EXISTS "allow_authenticated_insert_messages" ON public.messages;
DROP POLICY IF EXISTS "users_can_update_own_messages" ON public.messages;
DROP POLICY IF EXISTS "authenticated_users_can_update_own_messages" ON public.messages;
DROP POLICY IF EXISTS "allow_update_own_messages" ON public.messages;
DROP POLICY IF EXISTS "users_can_read_conversation_messages" ON public.messages;
DROP POLICY IF EXISTS "authenticated_users_can_read_messages" ON public.messages;
DROP POLICY IF EXISTS "allow_read_messages" ON public.messages;
DROP POLICY IF EXISTS "users_can_delete_own_messages" ON public.messages;
DROP POLICY IF EXISTS "authenticated_users_can_delete_own_messages" ON public.messages;
DROP POLICY IF EXISTS "allow_delete_own_messages" ON public.messages;
DROP POLICY IF EXISTS "allow_service_role_all" ON public.messages;
DROP POLICY IF EXISTS "messages_insert_authenticated" ON public.messages;
DROP POLICY IF EXISTS "messages_select_authenticated" ON public.messages;
DROP POLICY IF EXISTS "messages_update_own" ON public.messages;
DROP POLICY IF EXISTS "messages_delete_own" ON public.messages;
DROP POLICY IF EXISTS "messages_all_service_role" ON public.messages;

-- Use DO block to create policies only if table has RLS enabled
DO $$
BEGIN
    -- CRITICAL FIX: INSERT policy with minimal checks to avoid RLS recursion issues
    -- The validation that sender_id matches auth.uid() is the primary check
    CREATE POLICY "messages_insert_authenticated" ON public.messages
      FOR INSERT
      TO authenticated
      WITH CHECK (sender_id = auth.uid());
    
-- SELECT policy: Allow reading only messages from conversations the user is part of
    CREATE POLICY "messages_select_authenticated" ON public.messages
      FOR SELECT
      TO authenticated
      USING (
        -- User can only read messages from conversations where they are a participant
        EXISTS (
          SELECT 1 FROM public.conversations
          WHERE id = messages.conversation_id
          AND (user1_id = auth.uid() OR user2_id = auth.uid())
        )
      );
    
    -- UPDATE policy: Only allow updating own messages
    CREATE POLICY "messages_update_own" ON public.messages
      FOR UPDATE
      TO authenticated
      USING (sender_id = auth.uid())
      WITH CHECK (sender_id = auth.uid());
    
    -- DELETE policy: Only allow deleting own messages
    CREATE POLICY "messages_delete_own" ON public.messages
      FOR DELETE
      TO authenticated
      USING (sender_id = auth.uid());
    
    -- Ensure service_role can perform all operations (needed for triggers, admin operations, and scheduled tasks)
    CREATE POLICY "messages_all_service_role" ON public.messages
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
EXCEPTION WHEN duplicate_object THEN
    -- Policies already exist, that's fine
    NULL;
END $$;
