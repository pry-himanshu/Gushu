-- Create active_conversations table to track which users are currently viewing which chats

CREATE TABLE IF NOT EXISTS public.active_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, conversation_id)
);

-- Enable RLS
ALTER TABLE public.active_conversations ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "users_can_insert_own_active" ON public.active_conversations;
DROP POLICY IF EXISTS "users_can_update_own_active" ON public.active_conversations;
DROP POLICY IF EXISTS "users_can_delete_own_active" ON public.active_conversations;
DROP POLICY IF EXISTS "users_can_read_own_active" ON public.active_conversations;
DROP POLICY IF EXISTS "service_role_all_active" ON public.active_conversations;

-- Users can insert their own active conversation entries
CREATE POLICY "users_can_insert_own_active" ON public.active_conversations
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Users can update their own entries
CREATE POLICY "users_can_update_own_active" ON public.active_conversations
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Users can delete their own entries
CREATE POLICY "users_can_delete_own_active" ON public.active_conversations
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- Users can read their own active conversations
CREATE POLICY "users_can_read_own_active" ON public.active_conversations
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Service role can do anything
CREATE POLICY "service_role_all_active" ON public.active_conversations
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_active_conversations_user_id ON public.active_conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_active_conversations_conversation_id ON public.active_conversations(conversation_id);
CREATE INDEX IF NOT EXISTS idx_active_conversations_updated_at ON public.active_conversations(updated_at);

-- Grant permissions
GRANT SELECT, INSERT, UPDATE, DELETE ON public.active_conversations TO authenticated;
