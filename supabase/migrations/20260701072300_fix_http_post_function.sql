-- Fix http_post function call - convert jsonb body to text

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

    -- Query for users who should receive push notifications
    FOR v_token_record IN
        SELECT DISTINCT upt.token, upt.user_id
        FROM public.user_push_tokens upt
        WHERE upt.user_id IN (
            SELECT user1_id FROM public.conversations WHERE id = NEW.conversation_id
            UNION
            SELECT user2_id FROM public.conversations WHERE id = NEW.conversation_id
        )
        AND upt.user_id <> NEW.sender_id
    LOOP
        -- Try to send push notification
        BEGIN
            -- Use http_post with proper text conversion
            v_response := http_post(
                v_supabase_url || '/functions/v1/send-push',
                ARRAY['Content-Type: application/json'::http_header, 
                       ('apikey: ' || v_anon_key)::http_header,
                       ('Authorization: Bearer ' || v_anon_key)::http_header],
                jsonb_build_object(
                    'token', v_token_record.token,
                    'title', 'Gushu',
                    'body', 'Knock Knock'
                )::text
            );
        EXCEPTION WHEN OTHERS THEN
            -- Log error but don't fail the message insert
            RAISE WARNING 'Failed to send push notification: %', SQLERRM;
        END;
    END LOOP;

    RETURN NEW;
END;
$function$;
