-- =============================================================================
-- GS HEALTH / DENTAGURU ROLLBACK SCRIPT: 03_rollback_realtime_chat_phase2b.sql
-- Target Environment: STAGING ONLY (ojinzcdldwugpnxrnjcq)
-- =============================================================================
-- CRITICAL DATA-LOSS WARNING (READ BEFORE EXECUTING):
--   This rollback script DOES NOT preserve newly created Phase 2B chat structures!
--   Executing this script PERMANENTLY DELETES:
--     1. ALL rows in public.chat_conversations
--     2. ALL rows in public.chat_participants (including unread counts & mute states)
--     3. ALL rows in public.chat_message_reads (per-user read receipts)
--     4. ALL rows in public.chat_attachments (attachment relational metadata; binary
--        files in storage.objects for 'chat-attachments' remain unreferenced if present)
--     5. ALL Phase 2B extension columns on public.chat_messages (conversation_id,
--        sender_role, message_type, reply_to_message_id, has_attachments, metadata,
--        edited_at, is_deleted, deleted_at, deleted_by)
--     6. Any chat_messages rows marked soft-deleted (is_deleted = true), purged prior
--        to dropping is_deleted so moderated/deleted messages cannot reappear.
--
-- MANDATORY PRE-ROLLBACK PROCEDURE:
--   1. Complete the Pre-Rollback Export Checklist to archive all Phase 2B tables and
--      full 19-column public.chat_messages rows to JSON/CSV before running this script.
--   2. Verify you are connected ONLY to staging project 'ojinzcdldwugpnxrnjcq'.
--   3. Explicitly edit the three safety flags in Section 0 below to confirm approval.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 0. EXPLICIT OPERATOR CONFIRMATION SAFETY GATE (Aborts by default!)
-- =============================================================================
DO $$
DECLARE
    -- Operator MUST manually change all three constants below ONLY after exporting Phase 2B data:
    v_confirm_phase2b_data_loss   CONSTANT BOOLEAN := false;
    v_confirm_pre_rollback_export CONSTANT BOOLEAN := false;
    v_confirm_staging_project_ref CONSTANT TEXT    := '';

    v_conv_count BIGINT := 0;
    v_part_count BIGINT := 0;
    v_read_count BIGINT := 0;
    v_att_count  BIGINT := 0;
BEGIN
    IF to_regclass('public.chat_conversations') IS NOT NULL THEN
        EXECUTE 'SELECT COUNT(*) FROM public.chat_conversations' INTO v_conv_count;
    END IF;
    IF to_regclass('public.chat_participants') IS NOT NULL THEN
        EXECUTE 'SELECT COUNT(*) FROM public.chat_participants' INTO v_part_count;
    END IF;
    IF to_regclass('public.chat_message_reads') IS NOT NULL THEN
        EXECUTE 'SELECT COUNT(*) FROM public.chat_message_reads' INTO v_read_count;
    END IF;
    IF to_regclass('public.chat_attachments') IS NOT NULL THEN
        EXECUTE 'SELECT COUNT(*) FROM public.chat_attachments' INTO v_att_count;
    END IF;

    RAISE NOTICE '[Rollback Pre-Check] Rows slated for permanent deletion -> chat_conversations=%, chat_participants=%, chat_message_reads=%, chat_attachments=%',
        v_conv_count, v_part_count, v_read_count, v_att_count;

    IF NOT v_confirm_phase2b_data_loss
       OR NOT v_confirm_pre_rollback_export
       OR v_confirm_staging_project_ref <> 'ojinzcdldwugpnxrnjcq' THEN
        RAISE EXCEPTION
            'ROLLBACK BLOCKED BY SAFETY GATE: Executing this script permanently deletes chat_conversations (% rows), chat_participants (% rows), chat_message_reads (% rows), chat_attachments (% rows), and Phase 2B columns on chat_messages. Complete the Pre-Rollback Data Export first, then set v_confirm_phase2b_data_loss := true, v_confirm_pre_rollback_export := true, and v_confirm_staging_project_ref := ''ojinzcdldwugpnxrnjcq''.',
            v_conv_count, v_part_count, v_read_count, v_att_count;
    END IF;
END $$;

-- =============================================================================
-- 1. REMOVE ONLY PHASE 2B REALTIME POLICIES (Preserves all unrelated policies)
-- =============================================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'realtime'
          AND table_name = 'messages'
    ) THEN
        DROP POLICY IF EXISTS chat_realtime_broadcast_select ON realtime.messages;
        DROP POLICY IF EXISTS chat_realtime_broadcast_insert ON realtime.messages;
        DROP POLICY IF EXISTS chat_realtime_anon_deny_chat_topics ON realtime.messages;
        DROP POLICY IF EXISTS chat_realtime_restrict_topic_select ON realtime.messages;
        DROP POLICY IF EXISTS chat_realtime_restrict_topic_insert ON realtime.messages;
    END IF;
END $$;

-- =============================================================================
-- 2. REMOVE ONLY PHASE 2B STORAGE POLICIES (Preserves bucket if non-empty & all other buckets)
-- =============================================================================
DROP POLICY IF EXISTS chat_storage_objects_select_authorized ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_insert_authorized ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_update_authorized ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_anon_deny_all ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_restrict_select ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_restrict_insert ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_restrict_update ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_restrict_delete ON storage.objects;

DELETE FROM storage.buckets
WHERE id = 'chat-attachments'
  AND NOT EXISTS (
      SELECT 1 FROM storage.objects WHERE bucket_id = 'chat-attachments'
  );

-- If non-empty objects remain in chat-attachments, force bucket to remain strictly private
UPDATE storage.buckets
SET public = false
WHERE id = 'chat-attachments';

-- =============================================================================
-- 3. DROP PHASE 2B TRIGGERS & RLS POLICIES ON PUBLIC CHAT TABLES
--    Guarded with to_regclass(...) IS NOT NULL on the 4 Phase 2B tables so
--    partial-state or repeated rollbacks never fail on missing relations.
-- =============================================================================
DROP TRIGGER IF EXISTS trg_chat_messages_before_insert ON public.chat_messages;
DROP TRIGGER IF EXISTS trg_chat_messages_after_insert ON public.chat_messages;
DROP TRIGGER IF EXISTS trg_chat_messages_after_update_unread ON public.chat_messages;

DROP POLICY IF EXISTS chat_messages_select_authorized ON public.chat_messages;
DROP POLICY IF EXISTS chat_messages_insert_authorized ON public.chat_messages;

DO $$
BEGIN
    IF to_regclass('public.chat_attachments') IS NOT NULL THEN
        EXECUTE 'DROP POLICY IF EXISTS chat_attachments_select_authorized ON public.chat_attachments';
    END IF;

    IF to_regclass('public.chat_message_reads') IS NOT NULL THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_chat_message_reads_before_write ON public.chat_message_reads';
        EXECUTE 'DROP TRIGGER IF EXISTS trg_chat_message_reads_after_write ON public.chat_message_reads';
        EXECUTE 'DROP POLICY IF EXISTS chat_message_reads_select_authorized ON public.chat_message_reads';
        EXECUTE 'DROP POLICY IF EXISTS chat_message_reads_insert_self ON public.chat_message_reads';
        EXECUTE 'DROP POLICY IF EXISTS chat_message_reads_update_self ON public.chat_message_reads';
    END IF;

    IF to_regclass('public.chat_participants') IS NOT NULL THEN
        EXECUTE 'DROP TRIGGER IF EXISTS trg_chat_participants_before_update_read ON public.chat_participants';
        EXECUTE 'DROP POLICY IF EXISTS chat_participants_select_authorized ON public.chat_participants';
        EXECUTE 'DROP POLICY IF EXISTS chat_participants_update_self_read_state ON public.chat_participants';
    END IF;

    IF to_regclass('public.chat_conversations') IS NOT NULL THEN
        EXECUTE 'DROP POLICY IF EXISTS chat_conversations_select_authorized ON public.chat_conversations';
    END IF;
END $$;

-- =============================================================================
-- 4. DROP ALL PHASE 2B HELPER & TRIGGER FUNCTIONS (In reverse dependency order)
-- =============================================================================
DROP FUNCTION IF EXISTS public.fn_chat_message_reads_after_write();
DROP FUNCTION IF EXISTS public.fn_chat_message_reads_before_write();
DROP FUNCTION IF EXISTS public.fn_chat_participants_before_update_read();
DROP FUNCTION IF EXISTS public.fn_chat_messages_after_update_unread();
DROP FUNCTION IF EXISTS public.fn_chat_messages_after_insert();
DROP FUNCTION IF EXISTS public.fn_chat_messages_before_insert();
DROP FUNCTION IF EXISTS public.can_subscribe_chat_realtime_topic(TEXT);
DROP FUNCTION IF EXISTS public.can_update_chat_storage_object(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.can_upload_chat_storage_object(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.can_read_chat_storage_object(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.recompute_participant_unread_count(UUID, UUID);
DROP FUNCTION IF EXISTS public.is_valid_chat_read_receipt(UUID, UUID);
DROP FUNCTION IF EXISTS public.is_valid_conversation_receiver(UUID, UUID);
DROP FUNCTION IF EXISTS public.is_message_in_conversation(UUID, UUID);
DROP FUNCTION IF EXISTS public.is_authorized_chat_sender(UUID);
DROP FUNCTION IF EXISTS public.is_authorized_chat_reader(UUID);
DROP FUNCTION IF EXISTS public.resolve_chat_message_type(TEXT, TEXT);
DROP FUNCTION IF EXISTS public.map_user_role_to_chat_role(TEXT);
DROP FUNCTION IF EXISTS public.try_parse_uuid(TEXT);
DROP FUNCTION IF EXISTS public.caller_jwt_role();

-- =============================================================================
-- 5. CLEANLY REVERT PHASE 2B EXTENSIONS ON public.chat_messages
-- =============================================================================
-- Backfill synthetic room_id on any UUID-only messages and purge soft-deleted rows
-- BEFORE dropping is_deleted so moderated messages can never reappear publicly
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'chat_messages'
          AND column_name = 'is_deleted'
    ) THEN
        EXECUTE 'DELETE FROM public.chat_messages WHERE is_deleted = true';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'chat_messages'
          AND column_name = 'conversation_id'
    ) THEN
        EXECUTE $sql$
            UPDATE public.chat_messages
            SET room_id = COALESCE(
                'CONV_' || UPPER(REPLACE(conversation_id::TEXT, '-', '_')),
                'PATIENT_GENERAL'
            )
            WHERE room_id IS NULL OR BTRIM(room_id) = ''
        $sql$;
    ELSE
        UPDATE public.chat_messages
        SET room_id = 'PATIENT_GENERAL'
        WHERE room_id IS NULL OR BTRIM(room_id) = '';
    END IF;
END $$;

ALTER TABLE public.chat_messages
    ALTER COLUMN room_id SET NOT NULL;

-- Drop cross-table and Phase 2B constraints before dropping columns/tables
ALTER TABLE IF EXISTS public.chat_conversations
    DROP CONSTRAINT IF EXISTS fk_chat_conversations_last_message,
    DROP CONSTRAINT IF EXISTS chk_chat_conversations_type,
    DROP CONSTRAINT IF EXISTS chk_chat_conversations_status,
    DROP CONSTRAINT IF EXISTS uniq_chat_conversations_legacy_room_id;

ALTER TABLE IF EXISTS public.chat_participants
    DROP CONSTRAINT IF EXISTS fk_chat_participants_last_read_message,
    DROP CONSTRAINT IF EXISTS chk_chat_participants_role,
    DROP CONSTRAINT IF EXISTS chk_chat_participants_unread,
    DROP CONSTRAINT IF EXISTS unique_conversation_participant;

ALTER TABLE IF EXISTS public.chat_message_reads
    DROP CONSTRAINT IF EXISTS unique_message_user_read;

ALTER TABLE IF EXISTS public.chat_attachments
    DROP CONSTRAINT IF EXISTS uniq_chat_attachments_storage_path,
    DROP CONSTRAINT IF EXISTS chk_chat_attachments_size,
    DROP CONSTRAINT IF EXISTS chk_chat_attachments_scoped_path;

ALTER TABLE public.chat_messages
    DROP CONSTRAINT IF EXISTS fk_chat_messages_conversation_id,
    DROP CONSTRAINT IF EXISTS fk_chat_messages_reply_to_message_id,
    DROP CONSTRAINT IF EXISTS fk_chat_messages_deleted_by,
    DROP CONSTRAINT IF EXISTS chk_chat_messages_message_type;

-- Drop ALL Phase 2B indexes (including all 3 indexes added to public.chat_messages
-- and all 12 indexes on the 4 Phase 2B tables)
DROP INDEX IF EXISTS public.idx_chat_messages_conv_created;
DROP INDEX IF EXISTS public.idx_chat_messages_room_created;
DROP INDEX IF EXISTS public.idx_chat_messages_sender;

DROP INDEX IF EXISTS public.uniq_chat_conv_patient_dentist;
DROP INDEX IF EXISTS public.idx_chat_conv_patient;
DROP INDEX IF EXISTS public.idx_chat_conv_dentist;
DROP INDEX IF EXISTS public.idx_chat_conv_clinic;
DROP INDEX IF EXISTS public.idx_chat_conv_district;
DROP INDEX IF EXISTS public.idx_chat_conv_last_msg;
DROP INDEX IF EXISTS public.idx_chat_participants_user_active;
DROP INDEX IF EXISTS public.idx_chat_participants_conv_active;
DROP INDEX IF EXISTS public.idx_chat_reads_conv_user;
DROP INDEX IF EXISTS public.idx_chat_reads_message;
DROP INDEX IF EXISTS public.idx_chat_attachments_conv;
DROP INDEX IF EXISTS public.idx_chat_attachments_msg;

ALTER TABLE public.chat_messages
    DROP COLUMN IF EXISTS conversation_id,
    DROP COLUMN IF EXISTS sender_role,
    DROP COLUMN IF EXISTS message_type,
    DROP COLUMN IF EXISTS reply_to_message_id,
    DROP COLUMN IF EXISTS has_attachments,
    DROP COLUMN IF EXISTS metadata,
    DROP COLUMN IF EXISTS edited_at,
    DROP COLUMN IF EXISTS is_deleted,
    DROP COLUMN IF EXISTS deleted_at,
    DROP COLUMN IF EXISTS deleted_by;

-- Keep RLS enabled and anon/authenticated revoked on public.chat_messages so rollback
-- NEVER re-introduces the legacy "Allow All Chat Messages" anonymous leak;
-- Express backend (service_role) continues operating normally.
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.chat_messages FROM PUBLIC, anon, authenticated;
GRANT ALL ON TABLE public.chat_messages TO service_role;

-- =============================================================================
-- 6. DROP PHASE 2B TABLES IN REVERSE FOREIGN-KEY DEPENDENCY ORDER
-- =============================================================================
DROP TABLE IF EXISTS public.chat_attachments;
DROP TABLE IF EXISTS public.chat_message_reads;
DROP TABLE IF EXISTS public.chat_participants;
DROP TABLE IF EXISTS public.chat_conversations;

-- =============================================================================
-- 7. IN-TRANSACTION POST-ROLLBACK COMPLETENESS & SAFETY ASSERTIONS
-- =============================================================================
DO $$
BEGIN
    -- 1. Verify all 4 Phase 2B tables are removed
    IF to_regclass('public.chat_conversations') IS NOT NULL
       OR to_regclass('public.chat_participants') IS NOT NULL
       OR to_regclass('public.chat_message_reads') IS NOT NULL
       OR to_regclass('public.chat_attachments') IS NOT NULL THEN
        RAISE EXCEPTION 'Post-rollback check failed: one or more Phase 2B tables still exist.';
    END IF;

    -- 2. Verify all 10 Phase 2B extension columns on public.chat_messages are removed
    IF EXISTS (
        SELECT 1
        FROM information_schema.columns
        WHERE table_schema = 'public'
          AND table_name = 'chat_messages'
          AND column_name IN (
              'conversation_id', 'sender_role', 'message_type', 'reply_to_message_id',
              'has_attachments', 'metadata', 'edited_at', 'is_deleted', 'deleted_at', 'deleted_by'
          )
    ) THEN
        RAISE EXCEPTION 'Post-rollback check failed: Phase 2B columns remain on public.chat_messages.';
    END IF;

    -- 3. Verify all 3 Phase 2B indexes on public.chat_messages are removed
    IF to_regclass('public.idx_chat_messages_conv_created') IS NOT NULL
       OR to_regclass('public.idx_chat_messages_room_created') IS NOT NULL
       OR to_regclass('public.idx_chat_messages_sender') IS NOT NULL THEN
        RAISE EXCEPTION 'Post-rollback check failed: Phase 2B indexes remain on public.chat_messages.';
    END IF;

    -- 4. Verify public.chat_messages remains RLS-locked against anon & authenticated
    IF has_table_privilege('anon', 'public.chat_messages', 'SELECT')
       OR has_table_privilege('authenticated', 'public.chat_messages', 'SELECT') THEN
        RAISE EXCEPTION 'Post-rollback check failed: anon or authenticated still retains SELECT privilege on public.chat_messages.';
    END IF;
END $$;

COMMIT;
