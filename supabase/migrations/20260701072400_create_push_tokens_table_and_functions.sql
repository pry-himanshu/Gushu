-- Create user_push_tokens table and RPC functions for push notification token management

-- Create user_push_tokens table if it doesn't exist
CREATE TABLE IF NOT EXISTS public.user_push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    device_type TEXT, -- 'android', 'ios', 'web'
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(user_id, token)
);

-- Enable RLS on user_push_tokens
ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;

-- Drop existing RLS policies if they exist
DROP POLICY IF EXISTS "users_can_insert_own_tokens" ON public.user_push_tokens;
DROP POLICY IF EXISTS "users_can_read_own_tokens" ON public.user_push_tokens;
DROP POLICY IF EXISTS "users_can_delete_own_tokens" ON public.user_push_tokens;
DROP POLICY IF EXISTS "service_role_all_tokens" ON public.user_push_tokens;

-- Create RLS policies for user_push_tokens
-- Users can insert their own tokens
CREATE POLICY "users_can_insert_own_tokens" ON public.user_push_tokens
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Users can view their own tokens
CREATE POLICY "users_can_read_own_tokens" ON public.user_push_tokens
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Users can delete their own tokens
CREATE POLICY "users_can_delete_own_tokens" ON public.user_push_tokens
  FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());

-- Service role can do anything (for maintenance/cleanup)
CREATE POLICY "service_role_all_tokens" ON public.user_push_tokens
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_user_push_tokens_user_id ON public.user_push_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_user_push_tokens_token ON public.user_push_tokens(token);

-- Create trigger to update updated_at timestamp
CREATE OR REPLACE FUNCTION public.update_user_push_tokens_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS user_push_tokens_update_timestamp ON public.user_push_tokens;
CREATE TRIGGER user_push_tokens_update_timestamp
    BEFORE UPDATE ON public.user_push_tokens
    FOR EACH ROW
    EXECUTE FUNCTION public.update_user_push_tokens_updated_at();

-- Create RPC function to register push token
CREATE OR REPLACE FUNCTION public.register_push_token(
    p_token TEXT,
    p_device_type TEXT DEFAULT 'android'
)
RETURNS TABLE(success BOOLEAN, message TEXT) AS $$
BEGIN
    -- Insert or update the push token for the current user
    INSERT INTO public.user_push_tokens (user_id, token, device_type)
    VALUES (auth.uid(), p_token, p_device_type)
    ON CONFLICT (user_id, token) DO UPDATE
    SET device_type = p_device_type, updated_at = NOW();

    RETURN QUERY SELECT true AS success, 'Token registered successfully'::TEXT AS message;
EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT false AS success, ('Error: ' || SQLERRM)::TEXT AS message;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Create RPC function to unregister push token
CREATE OR REPLACE FUNCTION public.unregister_push_token(p_token TEXT)
RETURNS TABLE(success BOOLEAN, message TEXT) AS $$
BEGIN
    -- Delete the push token for the current user
    DELETE FROM public.user_push_tokens
    WHERE user_id = auth.uid() AND token = p_token;

    RETURN QUERY SELECT true AS success, 'Token unregistered successfully'::TEXT AS message;
EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT false AS success, ('Error: ' || SQLERRM)::TEXT AS message;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Grant permissions to authenticated users
GRANT SELECT, INSERT, DELETE ON public.user_push_tokens TO authenticated;
GRANT EXECUTE ON FUNCTION public.register_push_token TO authenticated;
GRANT EXECUTE ON FUNCTION public.unregister_push_token TO authenticated;
