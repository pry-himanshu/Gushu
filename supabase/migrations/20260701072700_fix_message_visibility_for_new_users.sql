-- Verify and fix message visibility for all conversations

-- First, let's ensure conversation_settings are created for all participants when they join
-- Create a function to initialize conversation settings for a user if they don't exist
CREATE OR REPLACE FUNCTION public.init_conversation_settings(p_user_id UUID, p_conversation_id UUID)
RETURNS TABLE(id UUID, conversation_id UUID, user_id UUID) AS $$
BEGIN
    INSERT INTO public.conversation_settings (user_id, conversation_id)
    VALUES (p_user_id, p_conversation_id)
    ON CONFLICT (user_id, conversation_id) DO NOTHING;

    RETURN QUERY
    SELECT cs.id, cs.conversation_id, cs.user_id
    FROM public.conversation_settings cs
    WHERE cs.user_id = p_user_id AND cs.conversation_id = p_conversation_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Function to verify message visibility for a user in a conversation
CREATE OR REPLACE FUNCTION public.check_message_visibility(p_user_id UUID, p_conversation_id UUID)
RETURNS TABLE(
    total_messages BIGINT,
    visible_messages BIGINT,
    deleted_for_user BIGINT,
    expired_messages BIGINT,
    user_settings_exist BOOLEAN
) AS $$
DECLARE
    v_total BIGINT;
    v_visible BIGINT;
    v_deleted BIGINT;
    v_expired BIGINT;
    v_settings_exist BOOLEAN;
BEGIN
    -- Check if conversation settings exist
    SELECT EXISTS(
        SELECT 1 FROM public.conversation_settings
        WHERE user_id = p_user_id AND conversation_id = p_conversation_id
    ) INTO v_settings_exist;

    -- Total messages in conversation
    SELECT COUNT(*) INTO v_total
    FROM public.messages
    WHERE conversation_id = p_conversation_id;

    -- Messages deleted for this user
    SELECT COUNT(DISTINCT m.id) INTO v_deleted
    FROM public.messages m
    LEFT JOIN public.message_deletions md ON m.id = md.message_id AND md.user_id = p_user_id
    WHERE m.conversation_id = p_conversation_id AND md.message_id IS NOT NULL;

    -- Messages that have expired
    SELECT COUNT(*) INTO v_expired
    FROM public.messages
    WHERE conversation_id = p_conversation_id 
    AND disappear_after_view = false
    AND expires_at IS NOT NULL
    AND expires_at < NOW();

    -- Visible messages (not deleted, not expired)
    SELECT COUNT(DISTINCT m.id) INTO v_visible
    FROM public.messages m
    LEFT JOIN public.message_deletions md ON m.id = md.message_id AND md.user_id = p_user_id
    WHERE m.conversation_id = p_conversation_id
    AND md.message_id IS NULL  -- Not deleted for this user
    AND (m.disappear_after_view = true OR m.expires_at IS NULL OR m.expires_at > NOW());

    RETURN QUERY SELECT v_total, v_visible, v_deleted, v_expired, v_settings_exist;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.init_conversation_settings TO authenticated;
GRANT EXECUTE ON FUNCTION public.check_message_visibility TO authenticated;
