-- Create RPC functions for managing active conversation tracking

-- Function to mark user as active in a conversation
CREATE OR REPLACE FUNCTION public.mark_conversation_active(p_conversation_id UUID)
RETURNS TABLE(success BOOLEAN, message TEXT) AS $$
BEGIN
    INSERT INTO public.active_conversations (user_id, conversation_id)
    VALUES (auth.uid(), p_conversation_id)
    ON CONFLICT (user_id, conversation_id) DO UPDATE
    SET updated_at = NOW();

    RETURN QUERY SELECT true AS success, 'Marked active'::TEXT AS message;
EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT false AS success, ('Error: ' || SQLERRM)::TEXT AS message;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Function to mark user as inactive in a conversation
CREATE OR REPLACE FUNCTION public.mark_conversation_inactive(p_conversation_id UUID)
RETURNS TABLE(success BOOLEAN, message TEXT) AS $$
BEGIN
    DELETE FROM public.active_conversations
    WHERE user_id = auth.uid() AND conversation_id = p_conversation_id;

    RETURN QUERY SELECT true AS success, 'Marked inactive'::TEXT AS message;
EXCEPTION WHEN OTHERS THEN
    RETURN QUERY SELECT false AS success, ('Error: ' || SQLERRM)::TEXT AS message;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Grant execute permissions to authenticated users
GRANT EXECUTE ON FUNCTION public.mark_conversation_active TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_conversation_inactive TO authenticated;
