-- Update push notification trigger to work with the new user_push_tokens table

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

    -- Query for push tokens of the other user
    FOR v_token_record IN
        SELECT token, device_type
        FROM public.user_push_tokens
        WHERE user_id = v_other_user_id
        ORDER BY created_at DESC
    LOOP
        -- Check if recipient is currently viewing the chat
        -- If they are active in the conversation, skip push notification
        IF EXISTS (
            SELECT 1 FROM public.active_conversations
            WHERE user_id = v_other_user_id
            AND conversation_id = NEW.conversation_id
            AND updated_at > NOW() - INTERVAL '60 seconds'
        ) THEN
            -- User is actively viewing the chat, skip notification
            CONTINUE;
        END IF;

        -- Try to send push notification via Edge Function
        BEGIN
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
                    'data', jsonb_build_object('conversation_id', NEW.conversation_id::text)
                )::text
            );
        EXCEPTION WHEN OTHERS THEN
            -- Log error but don't fail the message insert
            RAISE WARNING 'Failed to send push notification to token %: %', v_token_record.token, SQLERRM;
        END;
    END LOOP;

    RETURN NEW;
END;
$function$;

-- Ensure the trigger exists on the messages table
DROP TRIGGER IF EXISTS handle_new_message_push_notification ON public.messages;
CREATE TRIGGER handle_new_message_push_notification
    AFTER INSERT ON public.messages
    FOR EACH ROW
    EXECUTE FUNCTION public.handle_new_message_push_notification();
