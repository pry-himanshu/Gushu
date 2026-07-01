# Android Push Notifications - Setup Checklist

## Critical: Firebase Credentials Must Be Set as Supabase Secrets

**⚠️ This is the most common reason Android push notifications don't work!**

### Step 1: Get Firebase Service Account JSON

1. Go to [Firebase Console](https://console.firebase.google.com/project/gu-shu)
2. Click **Project Settings** (gear icon) → **Service Accounts**
3. Click **"Generate New Private Key"**
4. Save the JSON file (keep it secret!)

### Step 2: Add Secrets to Supabase

1. Go to [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Go to **Settings** → **Secrets and Vault**
4. Add these 3 secrets from the JSON file:

```
Name: FIREBASE_PROJECT_ID
Value: (from JSON: "project_id")

Name: FIREBASE_CLIENT_EMAIL
Value: (from JSON: "client_email")

Name: FIREBASE_PRIVATE_KEY
Value: (from JSON: "private_key" - include the -----BEGIN/END PRIVATE KEY----- lines)
```

**Important:** The private key must be in this format (with newlines):
```
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC...
...
-----END PRIVATE KEY-----
```

### Step 3: Verify Setup

After adding secrets, test push notifications:

1. In Supabase SQL Editor, run:
```sql
SELECT * FROM public.diagnose_push_setup();
```

2. Check the output for all "OK" status

3. View recent push attempts:
```sql
SELECT * FROM public.push_notification_logs 
ORDER BY created_at DESC 
LIMIT 20;
```

## Android Configuration Checklist

- [ ] `google-services.json` in `android/app/`
- [ ] Firebase dependencies in `android/app/build.gradle`
- [ ] Google Services plugin applied
- [ ] `POST_NOTIFICATIONS` permission in `AndroidManifest.xml`
- [ ] Notification channel created in code
- [ ] FCM token registration working

## Testing Background Push Notifications

1. **Build and deploy to Android device:**
   ```bash
   npm run build
   npx cap sync android
   npx cap open android
   # Build and run from Android Studio
   ```

2. **Get the FCM token:**
   - Open app on Android device
   - Grant notification permission when prompted
   - Check browser console or Android logcat for: "Push registration success, token: ..."

3. **Verify token is registered:**
   ```sql
   SELECT user_id, token, device_type, created_at 
   FROM public.user_push_tokens 
   WHERE device_type = 'android'
   ORDER BY created_at DESC;
   ```

4. **Send a test message:**
   - Send a message from another user while Android user is NOT looking at the chat
   - Check Android device for notification

5. **Check logs if notification doesn't appear:**
   ```sql
   SELECT * FROM public.push_notification_logs 
   WHERE created_at > NOW() - INTERVAL '10 minutes'
   ORDER BY created_at DESC;
   ```

   Look for:
   - `status = 'sent'` - notification was sent to FCM
   - `status = 'skipped'` - user was active in the chat (intended behavior)
   - `status = 'failed'` - error occurred

## Common Issues & Solutions

### Issue: "Missing Firebase credentials" error
**Solution:** Firebase secrets not added to Supabase. Follow Step 2 above.

### Issue: Tokens registered but no notifications sent
**Solution:** Check if `active_conversations` table exists:
```sql
SELECT * FROM public.active_conversations WHERE user_id = 'your-user-id';
```
If empty, the app isn't tracking activity. Ensure the chat page is properly integrated.

### Issue: Notifications sent but not received on Android
**Solution:** 
- Ensure app is built and deployed with latest `google-services.json`
- Check Android notification settings - app may be muted
- Verify notification channel is created

### Issue: Push logs show "failed" with "No anon key" error
**Solution:** Ensure `app_settings` table has the anon key:
```sql
SELECT * FROM public.app_settings WHERE key = 'anon_key';
```

## Database Tables Used for Push Notifications

1. **user_push_tokens** - FCM tokens by user
2. **active_conversations** - Which users are actively viewing which chats
3. **push_notification_logs** - History of all push attempts (for debugging)
4. **app_settings** - Stores anon_key for edge function

## Files Involved

- Backend Trigger: Database trigger `handle_new_message_push_notification()`
- Edge Function: `/supabase/functions/send-push/index.ts`
- Client Registration: `src/lib/notification-service.ts` → `registerPushNotifications()`
- Activity Tracking: `src/routes/_authenticated/app.c.$conversationId.tsx` → Updates `active_conversations`

## Next Steps if Still Not Working

1. Run the diagnostic function in Supabase SQL Editor
2. Check `push_notification_logs` table for error messages
3. Verify Firebase project ID matches the one in Android `google-services.json`
4. Ensure device has Google Play Services installed
5. Check Android device notification settings - app permissions may be blocked
