-- Debug and verify push notification setup for Android

-- Create a logging table to track push notification attempts
CREATE TABLE IF NOT EXISTS public.push_notification_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    token TEXT,
    message_sent_at TIMESTAMPTZ DEFAULT NOW(),
    status TEXT, -- 'pending', 'sent', 'failed'
    error_message TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create index for querying logs
CREATE INDEX IF NOT EXISTS idx_push_logs_created ON public.push_notification_logs(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_push_logs_status ON public.push_notification_logs(status);

-- Updated trigger function with better logging
CREATE OR REPLACE FUNCTION public.handle_new_message_push_notification()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_supabase_url TEXT;
    v_anon_key TEXT;
    v_token_record RECORD;
    v_other_user_id UUID;
    v_response TEXT;
    v_is_active BOOLEAN;
BEGIN
    IF TG_OP <> 'INSERT' THEN
        RETURN NEW;
    END IF;

    -- Get the anon key from app_settings table
    SELECT value INTO v_anon_key
    FROM public.app_settings
    WHERE key = 'anon_key'
    LIMIT 1;

    -- If no anon key, exit silently
    IF v_anon_key IS NULL THEN
        RAISE WARNING 'Push notifications: No anon key found';
        RETURN NEW;
    END IF;

    -- Construct Supabase URL
    v_supabase_url := 'https://xzeqhoolzewzojjodzmx.supabase.co';

    -- Get the other user in the conversation
    SELECT CASE 
        WHEN user1_id = NEW.sender_id THEN user2_id 
        ELSE user1_id 
    END INTO v_other_user_id
    FROM public.conversations
    WHERE id = NEW.conversation_id
    LIMIT 1;

    IF v_other_user_id IS NULL THEN
        RAISE WARNING 'Push notifications: No other user found in conversation %', NEW.conversation_id;
        RETURN NEW;
    END IF;

    -- Query for push tokens of the other user
    FOR v_token_record IN
        SELECT token, device_type
        FROM public.user_push_tokens
        WHERE user_id = v_other_user_id
        ORDER BY created_at DESC
    LOOP
        -- Check if recipient is currently viewing the chat
        SELECT EXISTS(
            SELECT 1 FROM public.active_conversations
            WHERE user_id = v_other_user_id
            AND conversation_id = NEW.conversation_id
            AND updated_at > NOW() - INTERVAL '60 seconds'
        ) INTO v_is_active;

        IF v_is_active THEN
            -- User is actively viewing the chat, skip notification
            RAISE WARNING 'Push notifications: User % is active in conversation %', v_other_user_id, NEW.conversation_id;
            INSERT INTO public.push_notification_logs (user_id, token, status, error_message)
            VALUES (v_other_user_id, v_token_record.token, 'skipped', 'User is active in chat');
            CONTINUE;
        END IF;

        -- Try to send push notification via Edge Function
        BEGIN
            RAISE WARNING 'Push notifications: Sending to token % for user %', v_token_record.token, v_other_user_id;
            
            PERFORM http_post(
                v_supabase_url || '/functions/v1/send-push',
                ARRAY[
                    'Content-Type: application/json'::http_header, 
                    ('apikey: ' || v_anon_key)::http_header,
                    ('Authorization: Bearer ' || v_anon_key)::http_header
                ],
                jsonb_build_object(
                    'token', v_token_record.token,
                    'title', 'Gushu',
                    'body', 'Knock Knock',
                    'data', jsonb_build_object('conversation_id', NEW.conversation_id::text, 'device_type', v_token_record.device_type)
                )::text
            );
            
            INSERT INTO public.push_notification_logs (user_id, token, status, error_message)
            VALUES (v_other_user_id, v_token_record.token, 'sent', NULL);
            
        EXCEPTION WHEN OTHERS THEN
            -- Log error but don't fail the message insert
            RAISE WARNING 'Failed to send push notification to token %: %', v_token_record.token, SQLERRM;
            INSERT INTO public.push_notification_logs (user_id, token, status, error_message)
            VALUES (v_other_user_id, v_token_record.token, 'failed', SQLERRM);
        END;
    END LOOP;

    RETURN NEW;
END;
$function$;

-- Create a diagnostic function to check push notification setup
CREATE OR REPLACE FUNCTION public.diagnose_push_setup()
RETURNS TABLE(
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Check 1: Anon key configured
    RETURN QUERY SELECT 
        'Anon Key Configured'::TEXT as check_name,
        CASE WHEN EXISTS(SELECT 1 FROM public.app_settings WHERE key = 'anon_key') THEN 'OK' ELSE 'MISSING' END as status,
        CASE WHEN EXISTS(SELECT 1 FROM public.app_settings WHERE key = 'anon_key') THEN 'Anon key is set' ELSE 'Anon key not found in app_settings' END as details;
    
    -- Check 2: Push tokens table exists
    RETURN QUERY SELECT 
        'Push Tokens Table'::TEXT as check_name,
        CASE WHEN EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'user_push_tokens') THEN 'OK' ELSE 'MISSING' END as status,
        CASE WHEN EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'user_push_tokens') THEN 'Table exists' ELSE 'Table not found' END as details;
    
    -- Check 3: Tokens registered
    RETURN QUERY SELECT 
        'Registered Tokens'::TEXT as check_name,
        CASE WHEN (SELECT COUNT(*) FROM public.user_push_tokens) > 0 THEN 'OK' ELSE 'NONE' END as status,
        (SELECT COUNT(*) || ' tokens registered')::TEXT as details
        FROM (SELECT 1) x
        LIMIT 1;
    
    -- Check 4: Active conversations table
    RETURN QUERY SELECT 
        'Active Conversations Table'::TEXT as check_name,
        CASE WHEN EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'active_conversations') THEN 'OK' ELSE 'MISSING' END as status,
        CASE WHEN EXISTS(SELECT 1 FROM information_schema.tables WHERE table_name = 'active_conversations') THEN 'Table exists' ELSE 'Table not found' END as details;
    
    -- Check 5: Recent push logs
    RETURN QUERY SELECT 
        'Recent Push Attempts'::TEXT as check_name,
        CASE WHEN (SELECT COUNT(*) FROM public.push_notification_logs WHERE created_at > NOW() - INTERVAL '1 hour') > 0 THEN 'OK' ELSE 'NONE' END as status,
        CASE WHEN (SELECT COUNT(*) FROM public.push_notification_logs WHERE created_at > NOW() - INTERVAL '1 hour') > 0 
            THEN (SELECT COUNT(*) || ' attempts in last hour')::TEXT
            ELSE 'No push attempts in last hour' 
        END as details
        FROM (SELECT 1) x
        LIMIT 1;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Grant permissions
GRANT SELECT ON public.push_notification_logs TO authenticated;
GRANT EXECUTE ON FUNCTION public.diagnose_push_setup TO authenticated;
