import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

const messageKind = z.enum(["text", "image", "video", "file", "audio", "system"]);

export const listMessages = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) => z.object({ conversationId: z.string().uuid() }).parse(input))
  .handler(async ({ data, context }) => {
    const { userId, supabase } = context;

    // Verify user is a participant in the conversation
    const { data: conv, error: convError } = await supabase
      .from("conversations")
      .select("user1_id, user2_id")
      .eq("id", data.conversationId)
      .maybeSingle();

    if (convError) throw new Error(convError.message);

    if (!conv || (conv.user1_id !== userId && conv.user2_id !== userId)) {
      return [];
    }

    // Get user's conversation settings (if they exist)
    const { data: userSettings, error: settingsError } = await supabase
      .from("conversation_settings")
      .select("cleared_at")
      .eq("conversation_id", data.conversationId)
      .eq("user_id", userId)
      .maybeSingle();

    if (settingsError) throw new Error(settingsError.message);

    let msgQuery = supabase
      .from("messages")
      .select("*, profiles!deleted_by_id(username, display_name)")
      .eq("conversation_id", data.conversationId);

    if (userSettings?.cleared_at) {
      msgQuery = msgQuery.gt("created_at", userSettings.cleared_at);
    }

    msgQuery = msgQuery.order("created_at", { ascending: true }).limit(500);

    const [msgRes, savedRes] = await Promise.all([
      msgQuery,
      supabase
        .from("message_saves" as any)
        .select("message_id, user_id, messages(*, profiles!deleted_by_id(username, display_name))")
        .eq("conversation_id", data.conversationId),
    ]);

    if (msgRes.error) throw new Error(msgRes.error.message);

    const savedData = savedRes.data ?? [];
    const allSavedIds = Array.from(new Set(savedData.map((s: any) => s.message_id as string)));
    const mySavedIds = savedData.filter((s: any) => s.user_id === userId).map((s: any) => s.message_id as string);

    const combinedMap = new Map<string, any>();
    (msgRes.data ?? []).forEach((r) => combinedMap.set(r.id, r));

    savedData.forEach((s: any) => {
      if (s.messages && !combinedMap.has(s.message_id)) {
        combinedMap.set(s.message_id, s.messages);
      }
    });

    const rows = Array.from(combinedMap.values()).sort((a, b) =>
      new Date(a.created_at).getTime() - new Date(b.created_at).getTime()
    );

    const allIds = rows.map((r: any) => r.id as string);
    if (allIds.length === 0) return [];

    const { data: deletions } = await supabase
      .from("message_deletions")
      .select("message_id")
      .eq("user_id", userId)
      .in("message_id", allIds as string[]);

    const deletedForMe = new Set((deletions ?? []).map((d: any) => d.message_id as string));
    const list = rows.filter((r: any) => !deletedForMe.has(r.id));

    const { data: reactionsData } = await supabase
      .from("message_reactions")
      .select("message_id, user_id, emoji")
      .in("message_id", allIds as string[]);

    const reactionsByMsg = new Map<string, { user_id: string; emoji: string }[]>();
    for (const r of reactionsData ?? []) {
      const arr = reactionsByMsg.get(r.message_id) ?? [];
      arr.push({ user_id: r.user_id, emoji: r.emoji });
      reactionsByMsg.set(r.message_id, arr);
    }

    const replyIds = Array.from(new Set(list.map((r: any) => r.reply_to as string).filter(Boolean)));
    let repliedMap = new Map<string, any>();

    if (replyIds.length > 0) {
      const { data: replied } = await supabase
        .from("messages")
        .select("id, content, message_type, media_name, sender_id")
        .in("id", replyIds as string[]);
      const repliedList = replied ?? [];
      const senderIds = Array.from(new Set(repliedList.map((r: any) => r.sender_id as string).filter(Boolean)));
      const { data: senders } = await supabase
        .from("profiles")
        .select("id, username, display_name")
        .in("id", senderIds);
      const senderMap = new Map((senders ?? []).map((s: any) => [s.id, s]));
      repliedMap = new Map(
        repliedList.map((m: any) => [
          m.id,
          {
            ...m,
            sender_name:
              senderMap.get(m.sender_id)?.display_name ??
              senderMap.get(m.sender_id)?.username ??
              null,
          },
        ]),
      );
    }

    return list.map((m: any) => ({
      ...m,
      is_saved: allSavedIds.includes(m.id),
      saved_by_me: mySavedIds.includes(m.id),
      reactions: reactionsByMsg.get(m.id) ?? [],
      replied_message: m.reply_to ? repliedMap.get(m.reply_to) ?? null : null,
      deleted_by_name: m.profiles?.display_name || m.profiles?.username || null,
    }));
  });

export const sendMessage = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) =>
    z
      .object({
        conversationId: z.string().uuid(),
        replyTo: z.string().uuid().optional(),
        content: z.string().max(4000, "Message cannot exceed 4000 characters").optional(),
        media: z
          .object({
            path: z.string(),
            mime: z.string(),
            name: z.string(),
            size: z.number().int().nonnegative(),
            kind: messageKind,
          })
          .optional(),
      })
      .refine((v) => (v.content && v.content.trim().length > 0) || v.media, {
        message: "Empty message",
      })
      .parse(input),
  )
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;

    const { data: row, error } = await (supabase
      .from("messages") as any)
      .insert({
        conversation_id: data.conversationId,
        sender_id: userId,
        content: data.content?.trim() || null,
        reply_to: data.replyTo ?? null,
        media_path: data.media?.path ?? null,
        media_mime: data.media?.mime ?? null,
        media_name: data.media?.name ?? null,
        media_size: data.media?.size ?? null,
        message_type: data.media?.kind ?? "text",
      })
      .select()
      .single();
    if (error) throw new Error(error.message);

    return row;
  });

export const editMessage = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) =>
    z.object({ id: z.string().uuid(), content: z.string().trim().min(1).max(4000, "Message cannot exceed 4000 characters") }).parse(input),
  )
  .handler(async ({ data, context }) => {
    const { error } = await context.supabase
      .from("messages")
      .update({ content: data.content, edited: true })
      .eq("id", data.id)
      .eq("sender_id", context.userId);
    if (error) throw new Error(error.message);
    return { ok: true };
  });

export const markRead = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) => z.object({ conversationId: z.string().uuid() }).parse(input))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;
    const nowString = new Date().toISOString();

    await (supabase.from("messages") as any)
      .update({ read_at: nowString, first_read_at: nowString })
      .eq("conversation_id", data.conversationId)
      .neq("sender_id", userId)
      .is("read_at", null);

    return { ok: true };
  });

const ALLOWED_MIME =
  /^(image\/(png|jpeg|webp|gif)|video\/(mp4|webm|quicktime)|audio\/(webm|ogg|mpeg|mp4|aac|m4a)|application\/pdf|application\/zip|text\/.*|application\/(msword|vnd\.openxmlformats-officedocument.*))$/;

export const createMediaUpload = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) =>
    z
      .object({
        conversationId: z.string().uuid(),
        name: z.string().min(1).max(200),
        mime: z.string().min(1).max(120).regex(ALLOWED_MIME, "Unsupported file type"),
        size: z
          .number()
          .int()
          .positive()
          .max(25 * 1024 * 1024),
      })
      .parse(input),
  )
  .handler(async ({ data, context }) => {
    const ext = data.name.includes(".") ? data.name.split(".").pop() : "bin";
    const path = `${data.conversationId}/${crypto.randomUUID()}.${ext}`;
    const { data: signed, error } = await context.supabase.storage
      .from("chat-media")
      .createSignedUploadUrl(path);
    if (error) throw new Error(error.message);
    return { path, token: signed.token };
  });

export const signedMediaUrl = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) => z.object({ path: z.string().min(1).max(300) }).parse(input))
  .handler(async ({ data, context }) => {
    const { data: signed, error } = await context.supabase.storage
      .from("chat-media")
      .createSignedUrl(data.path, 60 * 60);
    if (error) throw new Error(error.message);
    return { url: signed.signedUrl };
  });

export const saveMessage = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) => z.object({ messageId: z.string().uuid() }).parse(input))
  .handler(async ({ data, context }) => {
    const { error } = await (context.supabase as any).rpc("save_message", { _msg_id: data.messageId });
    if (error) throw new Error(error.message);
    return { ok: true };
  });

export const unsaveMessage = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) => z.object({ messageId: z.string().uuid() }).parse(input))
  .handler(async ({ data, context }) => {
    const { error } = await (context.supabase as any).rpc("unsave_message", { _msg_id: data.messageId });
    if (error) throw new Error(error.message);
    return { ok: true };
  });
