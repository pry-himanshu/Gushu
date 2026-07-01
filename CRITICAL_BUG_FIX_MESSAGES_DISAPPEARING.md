# Critical Bug Fix: Messages Disappearing When Users Join Chat

## The Problem

**Symptoms:**
- User A sends messages while User B is away
- When User B joins the chat, new messages don't appear
- Messages from User B also disappear
- Refreshing or rejoining chat doesn't help

## Root Cause

The bug was in `src/lib/messages.functions.ts` in the `listMessages` function:

```javascript
// WRONG - This logic was blocking message visibility
if (!conv && !userSettings) {
  return [];
}
```

**Why this was wrong:**
1. When User B joins a chat for the **first time**, they may not have a `conversation_settings` entry yet
2. The code checked: "If BOTH conversation AND user settings don't exist, return empty"
3. This meant: New users couldn't see ANY messages until their settings were created
4. Even after messages loaded, they would disappear if settings weren't properly initialized

## The Fix

Changed the logic to:
1. **Verify the conversation exists** and the user is a participant
2. **If yes** → Fetch messages (with or without user settings)
3. **User settings are optional** - they're only needed to track cleared_at time

```javascript
// CORRECT - Allow messages even without user settings
if (!conv || (conv.user1_id !== userId && conv.user2_id !== userId)) {
  return [];
}
```

## Files Changed

1. **[src/lib/messages.functions.ts](src/lib/messages.functions.ts)** - Fixed listMessages logic
2. **[supabase/migrations/20260701072700_fix_message_visibility_for_new_users.sql](supabase/migrations/20260701072700_fix_message_visibility_for_new_users.sql)** - Added diagnostic functions

## New Diagnostic Functions

### Check message visibility for a user:
```sql
SELECT * FROM public.check_message_visibility('user-id', 'conversation-id');
```

Returns:
- `total_messages` - All messages in the conversation
- `visible_messages` - Messages the user can see
- `deleted_for_user` - Messages deleted by this user
- `expired_messages` - Messages that have expired
- `user_settings_exist` - Whether user has settings entry

### Initialize settings for a user (if needed):
```sql
SELECT * FROM public.init_conversation_settings('user-id', 'conversation-id');
```

## Testing the Fix

1. **Deploy the code fix** - Update [src/lib/messages.functions.ts](src/lib/messages.functions.ts)
2. **Run the migration** - Apply `20260701072700_fix_message_visibility_for_new_users.sql`
3. **Test scenario:**
   - User A sends message to User B
   - User B is away (not in chat)
   - User B joins chat
   - **Expected:** New messages appear immediately
   - **Verify:** Run `check_message_visibility()` - should show messages as visible

## Related Tables & Functions

**Tables involved:**
- `messages` - All messages with RLS
- `conversation_settings` - User-specific chat settings
- `conversations` - Conversation definitions
- `message_deletions` - Tracks user-specific message deletions

**RLS Policy (messages table):**
```sql
CREATE POLICY "messages_select_authenticated" ON public.messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.conversations
      WHERE id = messages.conversation_id
      AND (user1_id = auth.uid() OR user2_id = auth.uid())
    )
  );
```

This policy ensures users can only see messages from conversations they're part of.

## Why Messages Were Also Disappearing

When User B's `conversation_settings` didn't exist:
1. Frontend calls `listMessages()` → returns `[]`
2. Frontend displays empty chat
3. User B sends a message → Message inserted to database
4. But RLS allows it (user is participant)
5. Next call to `listMessages()` with empty settings → might not return the message properly
6. Message appears to disappear

**Now fixed** - Settings are optional, messages are fetched based on conversation participation only.

## Prevention Going Forward

Make sure:
1. ✅ Check conversation participation first (not settings)
2. ✅ Settings are always optional for reading messages
3. ✅ Verify user is participant in conversations table before accessing messages
4. ✅ Don't skip messages just because user settings don't exist

## Next Steps

1. Deploy [src/lib/messages.functions.ts](src/lib/messages.functions.ts) changes
2. Run migration `20260701072700_fix_message_visibility_for_new_users.sql`
3. Test with User A → User B scenario
4. Use diagnostic functions if issues persist
