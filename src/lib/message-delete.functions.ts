import { createServerFn } from "@tanstack/react-start";
import { z } from "zod";
import { requireSupabaseAuth } from "@/integrations/supabase/auth-middleware";

export const deleteForMe = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) =>
    z.object({ messageId: z.string().uuid(), conversationId: z.string().uuid() }).parse(input),
  )
  .handler(async ({ data, context }) => {
    try {
      const { supabase, userId } = context;

      // Insert the deletion record for this user
      const { error } = await supabase.from("message_deletions").upsert(
        {
          message_id: data.messageId,
          user_id: userId,
          deleted_for_all: false,
        },
        { onConflict: "message_id,user_id" },
      );
      if (error) throw error;

      // Check if both participants have deleted this message
      const { data: conv } = await supabase
        .from("conversations")
        .select("user1_id, user2_id")
        .eq("id", data.conversationId)
        .single();

      if (conv) {
        const participants = [conv.user1_id, conv.user2_id];

        const { data: deletions } = await supabase
          .from("message_deletions")
          .select("user_id")
          .eq("message_id", data.messageId);

        const deletedUserIds = (deletions ?? []).map((d) => d.user_id);
        const allParticipantsDeleted = participants.every((p) => deletedUserIds.includes(p));

        if (allParticipantsDeleted) {
          // Get message media path before deletion
          const { data: msg } = await supabase
            .from("messages")
            .select("media_path")
            .eq("id", data.messageId)
            .maybeSingle();

          // Hard delete the message
          const { supabaseAdmin } = await import("@/integrations/supabase/client.server");

          // Delete message_deletions entries first (due to FK constraint)
          await supabaseAdmin.from("message_deletions").delete().eq("message_id", data.messageId);
          await supabaseAdmin.from("messages").delete().eq("id", data.messageId);

          // Remove media from storage if present
          if (msg?.media_path) {
            await supabaseAdmin.storage.from("chat-media").remove([msg.media_path]);
          }
        }
      }

      return { ok: true };
    } catch (e: any) {
      console.error("Delete for me error:", e);
      throw new Error("Could not hide message. Please try again.");
    }
  });

export const deleteForEveryone = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) =>
    z.object({ messageId: z.string().uuid(), conversationId: z.string().uuid() }).parse(input),
  )
  .handler(async ({ data, context }) => {
    try {
      const { data: msg } = await context.supabase
        .from("messages")
        .select("sender_id, media_path")
        .eq("id", data.messageId)
        .single();
        
      if (!msg) throw new Error("Message not found");
      if (msg.sender_id !== context.userId) {
        throw new Error("Only the sender can delete for everyone");
      }

      // Remove media if present
      if (msg.media_path) {
        const { supabaseAdmin } = await import("@/integrations/supabase/client.server");
        await supabaseAdmin.storage
          .from("chat-media")
          .remove([msg.media_path]);
      }

      // Soft delete from database (marks as deleted_for_all and sets deleted_by_id)
      const { error } = await context.supabase.rpc("soft_delete_message_for_everyone" as any, {
        _msg_id: data.messageId,
        _sender_id: context.userId,
      });
      
      if (error) throw error;

      return { ok: true };
    } catch (e: any) {
      console.error("Delete for everyone error:", e);
      throw new Error(e.message ?? "Message deletion failed. You might not have permission.");
    }
  });

export const markViewed = createServerFn({ method: "POST" })
  .middleware([requireSupabaseAuth])
  .validator((input: unknown) => z.object({ messageId: z.string().uuid() }).parse(input))
  .handler(async ({ data, context }) => {
    const { supabase, userId } = context;

    const { data: msg } = await (supabase
      .from("messages") as any)
      .select("id, message_type, view_count, viewed_at")
      .eq("id", data.messageId)
      .maybeSingle();

    if (!msg) return { ok: true };

    const updateData: Record<string, any> = {
      viewed_at: msg.viewed_at ?? new Date().toISOString(),
    };

    if (msg.message_type && ["image", "video", "file"].includes(msg.message_type)) {
      updateData.view_count = (msg.view_count ?? 0) + 1;
    }

    await (supabase.from("messages") as any)
      .update(updateData)
      .eq("id", data.messageId);

    return { ok: true };
  });
