-- =============================================================================
-- GS HEALTH / DENTAGURU SUPABASE POSTGRESQL MIGRATION: 03_realtime_chat_phase2b.sql
-- Target Environment: STAGING ONLY (ojinzcdldwugpnxrnjcq)
-- Module: Secure Multi-Role Clinical Chat, Explicit Participants, Read Receipts,
--         Private Attachments Bucket, Hardened RLS, Auto-Sync Legacy Triggers,
--         and Permissive + Restrictive Realtime/Storage Guards
-- Safety: Transactional (BEGIN ... COMMIT), Idempotent (Safe on fresh & partial
--         states), Non-Destructive (Zero DROP TABLE / TRUNCATE / DELETE on data),
--         Zero modifications to unrelated tables, buckets, or Realtime policies.
-- =============================================================================

BEGIN;

-- =============================================================================
-- 0A. EXPLICIT STAGING ENVIRONMENT CONFIRMATION GATE (Aborts by default!)
-- =============================================================================
-- IMPORTANT:
--   - Committed defaults MUST remain false / '' so accidental execution aborts.
--   - This manual check is an operator acknowledgement gate ONLY — SQL inside this
--     migration cannot automatically detect or verify the Supabase project ref
--     of the connected database.
--   - Before running, the operator MUST independently verify the target staging
--     project reference ('ojinzcdldwugpnxrnjcq') in the Supabase Dashboard
--     (Project Settings -> General), then edit a TEMPORARY execution copy to set:
--       v_confirm_staging_deployment  := true;
--       v_confirm_staging_project_ref := 'ojinzcdldwugpnxrnjcq';
-- =============================================================================
DO $$
DECLARE
    v_confirm_staging_deployment  CONSTANT BOOLEAN := false;
    v_confirm_staging_project_ref CONSTANT TEXT    := '';
    v_expected_project_ref        CONSTANT TEXT    := 'ojinzcdldwugpnxrnjcq';
BEGIN
    IF NOT v_confirm_staging_deployment
       OR v_confirm_staging_project_ref IS DISTINCT FROM v_expected_project_ref THEN
        RAISE EXCEPTION
            'MIGRATION BLOCKED BY STAGING SAFETY GATE: Independently verify your Supabase Dashboard project reference equals "%" before editing a temporary execution copy of 03_realtime_chat_phase2b.sql (set v_confirm_staging_deployment := true and v_confirm_staging_project_ref := ''ojinzcdldwugpnxrnjcq'').',
            v_expected_project_ref;
    END IF;
END $$;

-- =============================================================================
-- 0. PRE-FLIGHT INSPECTION LOG (Non-destructive catalog audit notices)
-- =============================================================================
DO $$
DECLARE
    pol RECORD;
BEGIN
    FOR pol IN
        SELECT policyname, permissive, roles, cmd
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'chat_messages'
    LOOP
        RAISE NOTICE '[Pre-Flight] Existing public.chat_messages policy: name=%, permissive=%, roles=%, cmd=%',
            pol.policyname, pol.permissive, pol.roles, pol.cmd;
    END LOOP;

    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'realtime'
          AND table_name = 'messages'
    ) THEN
        FOR pol IN
            SELECT policyname, permissive, roles, cmd
            FROM pg_policies
            WHERE schemaname = 'realtime'
              AND tablename = 'messages'
        LOOP
            RAISE NOTICE '[Pre-Flight] Existing realtime.messages policy preserved: name=%, permissive=%, roles=%, cmd=%',
                pol.policyname, pol.permissive, pol.roles, pol.cmd;
        END LOOP;
    END IF;
END $$;

-- =============================================================================
-- 1. CHAT CONVERSATIONS TABLE
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.chat_conversations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_type VARCHAR(40) NOT NULL DEFAULT 'PATIENT_DOCTOR',
    patient_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
    dentist_id UUID REFERENCES public.dentists(id) ON DELETE SET NULL,
    clinic_id UUID REFERENCES public.clinics(id) ON DELETE SET NULL,
    district_id UUID REFERENCES public.districts(id) ON DELETE SET NULL,
    appointment_id UUID REFERENCES public.appointments(id) ON DELETE SET NULL,
    problem_request_id UUID REFERENCES public.patient_problem_requests(id) ON DELETE SET NULL,
    referral_id UUID REFERENCES public.referrals(id) ON DELETE SET NULL,
    subject VARCHAR(255),
    status VARCHAR(30) NOT NULL DEFAULT 'ACTIVE',
    last_message_id UUID,
    last_message_preview TEXT,
    last_message_at TIMESTAMPTZ,
    legacy_room_id VARCHAR(255),
    created_by UUID REFERENCES public.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

-- Idempotent constraints on public.chat_conversations (handles partial states)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_chat_conversations_type'
          AND conrelid = 'public.chat_conversations'::regclass
    ) THEN
        ALTER TABLE public.chat_conversations
            ADD CONSTRAINT chk_chat_conversations_type
            CHECK (conversation_type IN ('PATIENT_DOCTOR', 'PATIENT_CLINIC', 'DOCTOR_CLINIC', 'PATIENT_SUPPORT', 'MULTI_PARTY_CARE'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_chat_conversations_status'
          AND conrelid = 'public.chat_conversations'::regclass
    ) THEN
        ALTER TABLE public.chat_conversations
            ADD CONSTRAINT chk_chat_conversations_status
            CHECK (status IN ('ACTIVE', 'ARCHIVED', 'CLOSED', 'BLOCKED'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uniq_chat_conversations_legacy_room_id'
          AND conrelid = 'public.chat_conversations'::regclass
    ) THEN
        ALTER TABLE public.chat_conversations
            ADD CONSTRAINT uniq_chat_conversations_legacy_room_id UNIQUE (legacy_room_id);
    END IF;
END $$;

CREATE UNIQUE INDEX IF NOT EXISTS uniq_chat_conv_patient_dentist
    ON public.chat_conversations (patient_id, dentist_id)
    WHERE conversation_type = 'PATIENT_DOCTOR'
      AND patient_id IS NOT NULL
      AND dentist_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_chat_conv_patient
    ON public.chat_conversations (patient_id, last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_chat_conv_dentist
    ON public.chat_conversations (dentist_id, last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_chat_conv_clinic
    ON public.chat_conversations (clinic_id, last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_chat_conv_district
    ON public.chat_conversations (district_id, last_message_at DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_chat_conv_last_msg
    ON public.chat_conversations (last_message_at DESC NULLS LAST);

-- =============================================================================
-- 2. CHAT PARTICIPANTS TABLE (Canonical user_id -> public.users.id)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.chat_participants (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    participant_role VARCHAR(30) NOT NULL,
    can_send BOOLEAN NOT NULL DEFAULT true,
    is_active BOOLEAN NOT NULL DEFAULT true,
    unread_count INTEGER NOT NULL DEFAULT 0,
    last_read_message_id UUID,
    last_read_at TIMESTAMPTZ,
    muted_until TIMESTAMPTZ,
    joined_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    left_at TIMESTAMPTZ
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_chat_participants_role'
          AND conrelid = 'public.chat_participants'::regclass
    ) THEN
        ALTER TABLE public.chat_participants
            ADD CONSTRAINT chk_chat_participants_role
            CHECK (participant_role IN ('PATIENT', 'DOCTOR', 'CLINIC', 'ADMIN', 'SUB_ADMIN'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_chat_participants_unread'
          AND conrelid = 'public.chat_participants'::regclass
    ) THEN
        ALTER TABLE public.chat_participants
            ADD CONSTRAINT chk_chat_participants_unread
            CHECK (unread_count >= 0);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'unique_conversation_participant'
          AND conrelid = 'public.chat_participants'::regclass
    ) THEN
        ALTER TABLE public.chat_participants
            ADD CONSTRAINT unique_conversation_participant
            UNIQUE (conversation_id, user_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_chat_participants_user_active
    ON public.chat_participants (user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_chat_participants_conv_active
    ON public.chat_participants (conversation_id, is_active);

-- =============================================================================
-- 3. NON-DESTRUCTIVE EXTENSION OF EXISTING public.chat_messages
-- =============================================================================
ALTER TABLE public.chat_messages
    ADD COLUMN IF NOT EXISTS conversation_id UUID,
    ADD COLUMN IF NOT EXISTS sender_role VARCHAR(30),
    ADD COLUMN IF NOT EXISTS message_type VARCHAR(30) NOT NULL DEFAULT 'TEXT',
    ADD COLUMN IF NOT EXISTS reply_to_message_id UUID,
    ADD COLUMN IF NOT EXISTS has_attachments BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN NOT NULL DEFAULT false,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deleted_by UUID;

ALTER TABLE public.chat_messages
    ALTER COLUMN room_id DROP NOT NULL;

-- Deterministic named foreign keys & check constraints on public.chat_messages
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_chat_messages_conversation_id'
          AND conrelid = 'public.chat_messages'::regclass
    ) THEN
        ALTER TABLE public.chat_messages
            ADD CONSTRAINT fk_chat_messages_conversation_id
            FOREIGN KEY (conversation_id) REFERENCES public.chat_conversations(id) ON DELETE CASCADE;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_chat_messages_reply_to_message_id'
          AND conrelid = 'public.chat_messages'::regclass
    ) THEN
        ALTER TABLE public.chat_messages
            ADD CONSTRAINT fk_chat_messages_reply_to_message_id
            FOREIGN KEY (reply_to_message_id) REFERENCES public.chat_messages(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_chat_messages_deleted_by'
          AND conrelid = 'public.chat_messages'::regclass
    ) THEN
        ALTER TABLE public.chat_messages
            ADD CONSTRAINT fk_chat_messages_deleted_by
            FOREIGN KEY (deleted_by) REFERENCES public.users(id) ON DELETE SET NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_chat_messages_message_type'
          AND conrelid = 'public.chat_messages'::regclass
    ) THEN
        ALTER TABLE public.chat_messages
            ADD CONSTRAINT chk_chat_messages_message_type
            CHECK (message_type IN ('TEXT', 'IMAGE', 'DOCUMENT', 'DICOM', 'PRESCRIPTION_LINK', 'SYSTEM'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_chat_participants_last_read_message'
          AND conrelid = 'public.chat_participants'::regclass
    ) THEN
        ALTER TABLE public.chat_participants
            ADD CONSTRAINT fk_chat_participants_last_read_message
            FOREIGN KEY (last_read_message_id) REFERENCES public.chat_messages(id) ON DELETE SET NULL;
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_chat_messages_conv_created
    ON public.chat_messages (conversation_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_room_created
    ON public.chat_messages (room_id, created_at ASC);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender
    ON public.chat_messages (sender_id);

-- =============================================================================
-- 3A. CORE IMMUTABLE ROLE & MESSAGE-TYPE NORMALIZATION HELPERS
--     - map_user_role_to_chat_role() strictly validates supported roles and
--       FAILS CLOSED (raises 42501) on NULL, empty, or unknown roles — never
--       defaulting unrecognized roles to 'PATIENT'.
--     - resolve_chat_message_type() preserves legacy image, document, DICOM,
--       prescription, and system types even when column DEFAULT 'TEXT' ran.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.map_user_role_to_chat_role(p_raw_role TEXT)
RETURNS VARCHAR(30)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_r TEXT := LOWER(BTRIM(COALESCE(p_raw_role, '')));
BEGIN
    IF v_r = '' THEN
        RAISE EXCEPTION 'Unsupported or empty chat user role: <EMPTY>'
            USING ERRCODE = '42501';
    ELSIF v_r = 'patient' THEN
        RETURN 'PATIENT';
    ELSIF v_r IN ('doctor', 'dentist') THEN
        RETURN 'DOCTOR';
    ELSIF v_r IN ('clinic', 'clinic_admin', 'clinic-admin', 'clinicadmin') THEN
        RETURN 'CLINIC';
    ELSIF v_r IN (
        'admin', 'primaryadmin', 'primary_admin', 'primary-admin',
        'superadmin', 'super_admin', 'super-admin', 'main_admin', 'main-admin'
    ) THEN
        RETURN 'ADMIN';
    ELSIF v_r IN ('sub-admin', 'subadmin', 'sub_admin') THEN
        RETURN 'SUB_ADMIN';
    ELSE
        RAISE EXCEPTION 'Unsupported chat user role: %', p_raw_role
            USING ERRCODE = '42501';
    END IF;
END;
$$;

-- Resolves canonical Phase 2B message_type even when PostgreSQL has already
-- populated NEW.message_type := 'TEXT' from the column DEFAULT before BEFORE INSERT.
CREATE OR REPLACE FUNCTION public.resolve_chat_message_type(
    p_message_type TEXT,
    p_legacy_type TEXT
)
RETURNS VARCHAR(30)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_msg_upper TEXT := UPPER(BTRIM(COALESCE(p_message_type, '')));
    v_msg_lower TEXT := LOWER(BTRIM(COALESCE(p_message_type, '')));
    v_leg_lower TEXT := LOWER(BTRIM(COALESCE(p_legacy_type, '')));
BEGIN
    -- 1. Preserve explicit non-default Phase 2B message_type values
    IF v_msg_upper IN ('IMAGE', 'DOCUMENT', 'DICOM', 'PRESCRIPTION_LINK', 'SYSTEM') THEN
        RETURN v_msg_upper;
    END IF;

    -- 2. When message_type is NULL, blank, or column-default 'TEXT', inspect legacy `type`
    IF v_leg_lower IN (
        'image', 'photo', 'jpg', 'jpeg', 'png', 'webp', 'xray', 'x-ray',
        'image/jpeg', 'image/jpg', 'image/png', 'image/webp'
    ) THEN
        RETURN 'IMAGE';
    ELSIF v_leg_lower IN (
        'document', 'doc', 'pdf', 'file', 'attachment', 'report', 'lab_report',
        'application/pdf'
    ) THEN
        RETURN 'DOCUMENT';
    ELSIF v_leg_lower IN ('dicom', 'dcm', 'application/dicom', 'image/dicom') THEN
        RETURN 'DICOM';
    ELSIF v_leg_lower IN (
        'prescription', 'prescription_link', 'rx', 'eprescription', 'e-prescription'
    ) THEN
        RETURN 'PRESCRIPTION_LINK';
    ELSIF v_leg_lower IN ('system', 'notice', 'alert') THEN
        RETURN 'SYSTEM';
    END IF;

    -- 3. Also normalize lowercase/alias values passed directly in message_type
    IF v_msg_lower IN ('image', 'photo', 'jpg', 'jpeg', 'png', 'webp', 'xray', 'x-ray') THEN
        RETURN 'IMAGE';
    ELSIF v_msg_lower IN ('document', 'doc', 'pdf', 'file', 'attachment', 'report', 'lab_report') THEN
        RETURN 'DOCUMENT';
    ELSIF v_msg_lower IN ('dicom', 'dcm', 'application/dicom', 'image/dicom') THEN
        RETURN 'DICOM';
    ELSIF v_msg_lower IN ('prescription', 'prescription_link', 'rx', 'eprescription', 'e-prescription') THEN
        RETURN 'PRESCRIPTION_LINK';
    ELSIF v_msg_lower IN ('system', 'notice', 'alert') THEN
        RETURN 'SYSTEM';
    END IF;

    RETURN 'TEXT';
END;
$$;

-- Non-destructive backfill for any pre-existing legacy rows in public.chat_messages
DO $$
DECLARE
    rec RECORD;
    v_conv_id UUID;
    v_norm_room VARCHAR(255);
BEGIN
    -- Backfill accurate message_type from legacy `type` on all pre-existing rows
    -- (where ADD COLUMN ... DEFAULT 'TEXT' initialized message_type to 'TEXT')
    UPDATE public.chat_messages
    SET message_type = public.resolve_chat_message_type(message_type, type)
    WHERE message_type IS DISTINCT FROM public.resolve_chat_message_type(message_type, type);

    FOR rec IN
        SELECT DISTINCT
            COALESCE(NULLIF(UPPER(REPLACE(BTRIM(room_id), '-', '_')), ''), 'PATIENT_GENERAL') AS norm_room
        FROM public.chat_messages
        WHERE conversation_id IS NULL
    LOOP
        v_norm_room := rec.norm_room;

        INSERT INTO public.chat_conversations (
            conversation_type,
            legacy_room_id,
            status
        ) VALUES (
            'PATIENT_DOCTOR',
            v_norm_room,
            'ACTIVE'
        )
        ON CONFLICT (legacy_room_id) DO UPDATE
            SET updated_at = CURRENT_TIMESTAMP
        RETURNING id INTO v_conv_id;

        UPDATE public.chat_messages
        SET conversation_id = v_conv_id,
            room_id = COALESCE(NULLIF(UPPER(REPLACE(BTRIM(room_id), '-', '_')), ''), v_norm_room),
            message_type = public.resolve_chat_message_type(message_type, type)
        WHERE conversation_id IS NULL
          AND COALESCE(NULLIF(UPPER(REPLACE(BTRIM(room_id), '-', '_')), ''), 'PATIENT_GENERAL') = v_norm_room;

        -- Backfill active participants ONLY from explicitly ACTIVE users holding a valid supported role
        INSERT INTO public.chat_participants (conversation_id, user_id, participant_role, can_send, is_active)
        SELECT DISTINCT
            v_conv_id,
            u.id,
            public.map_user_role_to_chat_role(u.role),
            true,
            true
        FROM public.chat_messages cm
        JOIN public.users u ON u.id IN (cm.sender_id, cm.receiver_id)
        WHERE cm.conversation_id = v_conv_id
          AND UPPER(BTRIM(u.status)) = 'ACTIVE'
          AND LOWER(BTRIM(COALESCE(u.role, ''))) IN (
              'patient',
              'doctor', 'dentist',
              'clinic', 'clinic_admin', 'clinic-admin', 'clinicadmin',
              'admin', 'primaryadmin', 'primary_admin', 'primary-admin',
              'superadmin', 'super_admin', 'super-admin', 'main_admin', 'main-admin'
          )
        ON CONFLICT (conversation_id, user_id) DO NOTHING;
    END LOOP;
END $$;

-- Add deferred FK from chat_conversations.last_message_id -> chat_messages.id
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'fk_chat_conversations_last_message'
          AND conrelid = 'public.chat_conversations'::regclass
    ) THEN
        ALTER TABLE public.chat_conversations
            ADD CONSTRAINT fk_chat_conversations_last_message
            FOREIGN KEY (last_message_id) REFERENCES public.chat_messages(id) ON DELETE SET NULL;
    END IF;
END $$;

-- =============================================================================
-- 4. CHAT MESSAGE READS TABLE (Granular Per-User Read Receipts)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.chat_message_reads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
    message_id UUID NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'unique_message_user_read'
          AND conrelid = 'public.chat_message_reads'::regclass
    ) THEN
        ALTER TABLE public.chat_message_reads
            ADD CONSTRAINT unique_message_user_read
            UNIQUE (message_id, user_id);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_chat_reads_conv_user
    ON public.chat_message_reads (conversation_id, user_id, read_at DESC);
CREATE INDEX IF NOT EXISTS idx_chat_reads_message
    ON public.chat_message_reads (message_id);

-- =============================================================================
-- 5. CHAT ATTACHMENTS TABLE (Backed by Private Storage Bucket)
-- =============================================================================
CREATE TABLE IF NOT EXISTS public.chat_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    conversation_id UUID NOT NULL REFERENCES public.chat_conversations(id) ON DELETE CASCADE,
    message_id UUID NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
    uploaded_by UUID NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
    storage_bucket VARCHAR(100) NOT NULL DEFAULT 'chat-attachments',
    storage_path TEXT NOT NULL,
    file_name VARCHAR(255) NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    file_size_bytes BIGINT NOT NULL,
    sha256_checksum VARCHAR(64),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'uniq_chat_attachments_storage_path'
          AND conrelid = 'public.chat_attachments'::regclass
    ) THEN
        ALTER TABLE public.chat_attachments
            ADD CONSTRAINT uniq_chat_attachments_storage_path UNIQUE (storage_path);
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_chat_attachments_size'
          AND conrelid = 'public.chat_attachments'::regclass
    ) THEN
        ALTER TABLE public.chat_attachments
            ADD CONSTRAINT chk_chat_attachments_size
            CHECK (file_size_bytes > 0 AND file_size_bytes <= 20971520);
    END IF;

    -- Enforce conversation-scoped storage path: <conversation_id>/<uploader_or_msg_uuid>/<filename>
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'chk_chat_attachments_scoped_path'
          AND conrelid = 'public.chat_attachments'::regclass
    ) THEN
        ALTER TABLE public.chat_attachments
            ADD CONSTRAINT chk_chat_attachments_scoped_path
            CHECK (
                storage_bucket = 'chat-attachments'
                AND LEFT(storage_path, 1) <> '/'
                AND POSITION('..' IN storage_path) = 0
                AND POSITION('//' IN storage_path) = 0
                AND split_part(storage_path, '/', 1) = conversation_id::TEXT
                AND BTRIM(split_part(storage_path, '/', 2)) <> ''
                AND BTRIM(split_part(storage_path, '/', 3)) <> ''
            );
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_chat_attachments_conv
    ON public.chat_attachments (conversation_id);
CREATE INDEX IF NOT EXISTS idx_chat_attachments_msg
    ON public.chat_attachments (message_id);

-- =============================================================================
-- 6. PRIVATE STORAGE BUCKET: chat-attachments (20 MB max, Clinical MIME Allowlist)
-- =============================================================================
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'chat-attachments',
    'chat-attachments',
    false,
    20971520,
    ARRAY[
        'image/jpeg',
        'image/jpg',
        'image/png',
        'image/webp',
        'application/pdf',
        'application/dicom',
        'image/dicom'
    ]
)
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 20971520,
    allowed_mime_types = EXCLUDED.allowed_mime_types;

-- =============================================================================
-- 7. HARDENED SECURITY DEFINER HELPER FUNCTIONS
--    - NEVER accept client-supplied user IDs for caller identity (strictly uses auth.uid())
--    - Fixed search_path = public, pg_temp
--    - Direct client RLS is restricted to active Patient, Doctor & Clinic participants;
--      Main Admin & Sub-Admin MUST use audited Express endpoints (service_role) so
--      public.audit_logs can never be bypassed.
-- =============================================================================

-- Distinguishes trusted backend/admin execution ('service_role' or 'postgres')
-- from untrusted client execution ('authenticated', 'anon', 'unknown'), even when
-- invoked inside a SECURITY DEFINER function where current_user is 'postgres'.
CREATE OR REPLACE FUNCTION public.caller_jwt_role()
RETURNS TEXT
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
    v_claims_raw TEXT;
    v_jwt_role   TEXT;
BEGIN
    v_claims_raw := NULLIF(BTRIM(current_setting('request.jwt.claims', true)), '');
    IF v_claims_raw IS NOT NULL THEN
        BEGIN
            v_jwt_role := NULLIF(BTRIM(v_claims_raw::jsonb ->> 'role'), '');
        EXCEPTION
            WHEN others THEN
                v_jwt_role := NULL;
        END;
    END IF;

    IF v_jwt_role IS NULL THEN
        v_jwt_role := NULLIF(BTRIM(current_setting('request.jwt.claim.role', true)), '');
    END IF;

    IF v_jwt_role IS NOT NULL THEN
        RETURN v_jwt_role;
    END IF;

    IF session_user IN ('postgres', 'supabase_admin', 'supabase_storage_admin')
       AND auth.uid() IS NULL THEN
        RETURN 'postgres';
    END IF;

    RETURN 'unknown';
END;
$$;

CREATE OR REPLACE FUNCTION public.try_parse_uuid(p_text TEXT)
RETURNS UUID
LANGUAGE plpgsql
IMMUTABLE
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_text IS NULL OR BTRIM(p_text) = '' THEN
        RETURN NULL;
    END IF;
    RETURN BTRIM(p_text)::UUID;
EXCEPTION
    WHEN others THEN
        RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_authorized_chat_reader(p_conversation_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_status TEXT;
    v_raw_role TEXT;
    v_chat_role VARCHAR(30);
    v_conv_status TEXT;
BEGIN
    IF v_uid IS NULL OR p_conversation_id IS NULL THEN
        RETURN false;
    END IF;

    -- Fail closed: user MUST exist and have explicit status = 'ACTIVE' (NULL/missing status rejected)
    SELECT UPPER(BTRIM(u.status)), u.role
    INTO v_status, v_raw_role
    FROM public.users u
    WHERE u.id = v_uid;

    IF NOT FOUND OR v_status IS DISTINCT FROM 'ACTIVE' THEN
        RETURN false;
    END IF;

    BEGIN
        v_chat_role := public.map_user_role_to_chat_role(v_raw_role);
    EXCEPTION
        WHEN others THEN
            RETURN false;
    END;

    IF v_chat_role NOT IN ('PATIENT', 'DOCTOR', 'CLINIC') THEN
        RETURN false;
    END IF;

    -- Reject non-existent, BLOCKED, NULL, or unknown-status conversations
    SELECT UPPER(BTRIM(cc.status))
    INTO v_conv_status
    FROM public.chat_conversations cc
    WHERE cc.id = p_conversation_id;

    IF NOT FOUND OR v_conv_status IS NULL OR v_conv_status NOT IN ('ACTIVE', 'ARCHIVED', 'CLOSED') THEN
        RETURN false;
    END IF;

    -- 1. Active direct participant (Patient, Doctor, or Clinic — never Admin/Sub-Admin direct RLS bypass)
    IF EXISTS (
        SELECT 1
        FROM public.chat_participants cp
        WHERE cp.conversation_id = p_conversation_id
          AND cp.user_id = v_uid
          AND cp.is_active = true
          AND cp.participant_role = v_chat_role
    ) THEN
        RETURN true;
    END IF;

    -- 2. Clinic owner accessing conversations explicitly belonging to their clinic
    IF v_chat_role = 'CLINIC' AND EXISTS (
        SELECT 1
        FROM public.chat_conversations cc
        JOIN public.clinics cl ON cl.id = cc.clinic_id
        WHERE cc.id = p_conversation_id
          AND cl.user_id = v_uid
    ) THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_authorized_chat_sender(p_conversation_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_status TEXT;
    v_raw_role TEXT;
    v_chat_role VARCHAR(30);
    v_conv_status TEXT;
    v_conv_type TEXT;
    v_clinic_id UUID;
BEGIN
    IF v_uid IS NULL OR p_conversation_id IS NULL THEN
        RETURN false;
    END IF;

    -- Fail closed: user MUST exist and have explicit status = 'ACTIVE' (NULL/missing status rejected)
    SELECT UPPER(BTRIM(u.status)), u.role
    INTO v_status, v_raw_role
    FROM public.users u
    WHERE u.id = v_uid;

    IF NOT FOUND OR v_status IS DISTINCT FROM 'ACTIVE' THEN
        RETURN false;
    END IF;

    BEGIN
        v_chat_role := public.map_user_role_to_chat_role(v_raw_role);
    EXCEPTION
        WHEN others THEN
            RETURN false;
    END;

    IF v_chat_role NOT IN ('PATIENT', 'DOCTOR', 'CLINIC') THEN
        RETURN false;
    END IF;

    -- Sender requires an explicitly ACTIVE conversation (rejects ARCHIVED, CLOSED, BLOCKED, INACTIVE, NULL)
    SELECT UPPER(BTRIM(cc.status)), cc.conversation_type, cc.clinic_id
    INTO v_conv_status, v_conv_type, v_clinic_id
    FROM public.chat_conversations cc
    WHERE cc.id = p_conversation_id;

    IF NOT FOUND OR v_conv_status IS DISTINCT FROM 'ACTIVE' THEN
        RETURN false;
    END IF;

    -- 1. Active direct participant with can_send = true (Patient, Doctor, or Clinic)
    IF EXISTS (
        SELECT 1
        FROM public.chat_participants cp
        WHERE cp.conversation_id = p_conversation_id
          AND cp.user_id = v_uid
          AND cp.is_active = true
          AND cp.can_send = true
          AND cp.participant_role = v_chat_role
    ) THEN
        RETURN true;
    END IF;

    -- 2. Clinic owner on active clinic-scoped conversation types
    IF v_chat_role = 'CLINIC'
       AND v_clinic_id IS NOT NULL
       AND v_conv_type IN ('PATIENT_CLINIC', 'DOCTOR_CLINIC', 'MULTI_PARTY_CARE')
       AND EXISTS (
           SELECT 1
           FROM public.clinics cl
           WHERE cl.id = v_clinic_id
             AND cl.user_id = v_uid
       ) THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$$;

-- Verifies a message exists, is not soft-deleted, and belongs to the exact conversation.
CREATE OR REPLACE FUNCTION public.is_message_in_conversation(
    p_message_id UUID,
    p_conversation_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF p_message_id IS NULL OR p_conversation_id IS NULL THEN
        RETURN false;
    END IF;

    RETURN EXISTS (
        SELECT 1
        FROM public.chat_messages cm
        WHERE cm.id = p_message_id
          AND cm.conversation_id = p_conversation_id
          AND cm.is_deleted = false
    );
END;
$$;

-- Validates that a message's receiver_id belongs to the intended ACTIVE conversation participants.
-- Consistent with sender validation: rejects inactive/archived/closed/blocked/missing conversations,
-- inactive/NULL-status users, unknown roles, and any third-party user outside the conversation.
CREATE OR REPLACE FUNCTION public.is_valid_conversation_receiver(
    p_conversation_id UUID,
    p_receiver_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_conv_status TEXT;
    v_receiver_status TEXT;
    v_receiver_role VARCHAR(30);
BEGIN
    IF p_conversation_id IS NULL OR p_receiver_id IS NULL THEN
        RETURN false;
    END IF;

    -- Authenticated callers cannot address a message to themselves as receiver
    IF v_uid IS NOT NULL AND p_receiver_id = v_uid THEN
        RETURN false;
    END IF;

    -- Conversation MUST exist and be explicitly ACTIVE (rejects ARCHIVED, CLOSED, BLOCKED, INACTIVE, NULL)
    SELECT UPPER(BTRIM(cc.status))
    INTO v_conv_status
    FROM public.chat_conversations cc
    WHERE cc.id = p_conversation_id;

    IF NOT FOUND OR v_conv_status IS DISTINCT FROM 'ACTIVE' THEN
        RETURN false;
    END IF;

    -- Receiver MUST have explicit status = 'ACTIVE' (NULL/missing rejected) and valid clinical/patient role
    BEGIN
        SELECT
            UPPER(BTRIM(u.status)),
            public.map_user_role_to_chat_role(u.role)
        INTO v_receiver_status, v_receiver_role
        FROM public.users u
        WHERE u.id = p_receiver_id;
    EXCEPTION
        WHEN others THEN
            RETURN false;
    END;

    IF NOT FOUND
       OR v_receiver_status IS DISTINCT FROM 'ACTIVE'
       OR v_receiver_role NOT IN ('PATIENT', 'DOCTOR', 'CLINIC') THEN
        RETURN false;
    END IF;

    -- Explicitly revoked/removed participants (is_active = false) are never valid receivers
    IF EXISTS (
        SELECT 1
        FROM public.chat_participants cp
        WHERE cp.conversation_id = p_conversation_id
          AND cp.user_id = p_receiver_id
          AND cp.is_active = false
    ) THEN
        RETURN false;
    END IF;

    -- 1. Existing active participant of this ACTIVE conversation
    IF EXISTS (
        SELECT 1
        FROM public.chat_participants cp
        WHERE cp.conversation_id = p_conversation_id
          AND cp.user_id = p_receiver_id
          AND cp.is_active = true
          AND cp.participant_role IN ('PATIENT', 'DOCTOR', 'CLINIC')
    ) THEN
        RETURN true;
    END IF;

    -- 2. Bound clinical party on public.chat_conversations (patient, assigned dentist, or clinic owner)
    IF EXISTS (
        SELECT 1
        FROM public.chat_conversations cc
        LEFT JOIN public.dentists d ON d.id = cc.dentist_id
        LEFT JOIN public.clinics cl ON cl.id = cc.clinic_id
        WHERE cc.id = p_conversation_id
          AND UPPER(BTRIM(cc.status)) = 'ACTIVE'
          AND (
              cc.patient_id = p_receiver_id
              OR d.user_id = p_receiver_id
              OR cl.user_id = p_receiver_id
          )
    ) THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$$;

-- Validates read-receipt writes against caller identity, active conversation access,
-- and exact message-to-conversation membership.
CREATE OR REPLACE FUNCTION public.is_valid_chat_read_receipt(
    p_conversation_id UUID,
    p_message_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF auth.uid() IS NULL OR p_conversation_id IS NULL OR p_message_id IS NULL THEN
        RETURN false;
    END IF;

    IF NOT public.is_authorized_chat_reader(p_conversation_id) THEN
        RETURN false;
    END IF;

    RETURN public.is_message_in_conversation(p_message_id, p_conversation_id);
END;
$$;

-- Trusted internal helper to recompute public.chat_participants.unread_count
-- from non-deleted counterparty messages not yet marked read via legacy `read = true`,
-- `chat_message_reads`, or the participant's validated `last_read_message_id` watermark.
CREATE OR REPLACE FUNCTION public.recompute_participant_unread_count(
    p_conversation_id UUID,
    p_user_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_last_read_msg_id UUID;
    v_watermark_at TIMESTAMPTZ;
    v_unread INTEGER := 0;
BEGIN
    IF p_conversation_id IS NULL OR p_user_id IS NULL THEN
        RETURN 0;
    END IF;

    SELECT cp.last_read_message_id
    INTO v_last_read_msg_id
    FROM public.chat_participants cp
    WHERE cp.conversation_id = p_conversation_id
      AND cp.user_id = p_user_id;

    IF NOT FOUND THEN
        RETURN 0;
    END IF;

    IF v_last_read_msg_id IS NOT NULL THEN
        SELECT cm.created_at
        INTO v_watermark_at
        FROM public.chat_messages cm
        WHERE cm.id = v_last_read_msg_id
          AND cm.conversation_id = p_conversation_id;
    END IF;

    SELECT COUNT(*)::INTEGER
    INTO v_unread
    FROM public.chat_messages cm
    WHERE cm.conversation_id = p_conversation_id
      AND cm.is_deleted = false
      AND (cm.sender_id IS NULL OR cm.sender_id <> p_user_id)
      AND COALESCE(cm.read, false) = false
      AND (v_watermark_at IS NULL OR cm.created_at > v_watermark_at)
      AND (v_last_read_msg_id IS NULL OR cm.id <> v_last_read_msg_id)
      AND NOT EXISTS (
          SELECT 1
          FROM public.chat_message_reads cmr
          WHERE cmr.conversation_id = p_conversation_id
            AND cmr.message_id = cm.id
            AND cmr.user_id = p_user_id
      );

    UPDATE public.chat_participants
    SET unread_count = GREATEST(v_unread, 0)
    WHERE conversation_id = p_conversation_id
      AND user_id = p_user_id;

    RETURN GREATEST(v_unread, 0);
END;
$$;

-- Hardened Storage object read authorizer for bucket 'chat-attachments'
-- Enforces:
--   1. Exact bucket_id = 'chat-attachments' & zero path traversal ('..', '//', leading '/')
--   2. First folder segment is a valid conversation UUID authorized for auth.uid()
--   3. Blocks any attachment whose parent chat_messages row is soft-deleted (is_deleted = true)
--   4. Allows read either when registered in public.chat_attachments on a non-deleted message
--      in THAT conversation OR when the authorized sender is reading back their own in-flight
--      upload (<conv_id>/<auth.uid()>/<filename>) during INSERT ... RETURNING / TUS upload.
CREATE OR REPLACE FUNCTION public.can_read_chat_storage_object(
    p_bucket_id TEXT,
    p_object_name TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_conv_id UUID;
    v_folder_uid UUID;
    v_filename TEXT;
    v_extra_seg TEXT;
BEGIN
    IF v_uid IS NULL
       OR p_bucket_id IS DISTINCT FROM 'chat-attachments'
       OR p_object_name IS NULL
       OR LEFT(p_object_name, 1) = '/'
       OR POSITION('..' IN p_object_name) > 0
       OR POSITION('//' IN p_object_name) > 0 THEN
        RETURN false;
    END IF;

    v_conv_id := public.try_parse_uuid(split_part(p_object_name, '/', 1));
    IF v_conv_id IS NULL THEN
        RETURN false;
    END IF;

    IF NOT public.is_authorized_chat_reader(v_conv_id) THEN
        RETURN false;
    END IF;

    -- Never allow reading an attachment tied to a soft-deleted/moderated message
    IF EXISTS (
        SELECT 1
        FROM public.chat_attachments ca
        JOIN public.chat_messages cm ON cm.id = ca.message_id
        WHERE ca.storage_bucket = 'chat-attachments'
          AND ca.storage_path = p_object_name
          AND cm.is_deleted = true
    ) THEN
        RETURN false;
    END IF;

    -- 1. Registered attachment on an active message in this conversation
    IF EXISTS (
        SELECT 1
        FROM public.chat_attachments ca
        JOIN public.chat_messages cm ON cm.id = ca.message_id
        WHERE ca.conversation_id = v_conv_id
          AND ca.storage_bucket = 'chat-attachments'
          AND ca.storage_path = p_object_name
          AND cm.is_deleted = false
    ) THEN
        RETURN true;
    END IF;

    -- 2. Uploader's own in-flight upload (<conversation_id>/<auth.uid()>/<filename>)
    --    Required so PostgreSQL INSERT ... RETURNING * succeeds before chat_attachments is inserted
    v_folder_uid := public.try_parse_uuid(split_part(p_object_name, '/', 2));
    v_filename := BTRIM(split_part(p_object_name, '/', 3));
    v_extra_seg := split_part(p_object_name, '/', 4);

    IF v_folder_uid IS NOT NULL
       AND v_folder_uid = v_uid
       AND v_filename <> ''
       AND v_extra_seg = ''
       AND public.is_authorized_chat_sender(v_conv_id) THEN
        RETURN true;
    END IF;

    RETURN false;
END;
$$;

-- Hardened Storage object upload authorizer for bucket 'chat-attachments'
-- Enforces strict 3-segment folder layout: <conversation_id>/<auth.uid()>/<filename>
CREATE OR REPLACE FUNCTION public.can_upload_chat_storage_object(
    p_bucket_id TEXT,
    p_object_name TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_conv_id UUID;
    v_folder_uid UUID;
    v_filename TEXT;
    v_extra_seg TEXT;
BEGIN
    IF v_uid IS NULL
       OR p_bucket_id IS DISTINCT FROM 'chat-attachments'
       OR p_object_name IS NULL
       OR LEFT(p_object_name, 1) = '/'
       OR POSITION('..' IN p_object_name) > 0
       OR POSITION('//' IN p_object_name) > 0 THEN
        RETURN false;
    END IF;

    v_conv_id := public.try_parse_uuid(split_part(p_object_name, '/', 1));
    v_folder_uid := public.try_parse_uuid(split_part(p_object_name, '/', 2));
    v_filename := BTRIM(split_part(p_object_name, '/', 3));
    v_extra_seg := split_part(p_object_name, '/', 4);

    IF v_conv_id IS NULL
       OR v_folder_uid IS NULL
       OR v_folder_uid <> v_uid
       OR v_filename = ''
       OR v_extra_seg <> '' THEN
        RETURN false;
    END IF;

    RETURN public.is_authorized_chat_sender(v_conv_id);
END;
$$;

-- Hardened Storage object update authorizer for bucket 'chat-attachments'
-- Permits Supabase Storage two-phase / TUS upload metadata finalization ONLY by the
-- original authorized sender on their own in-flight object BEFORE it is committed to
-- public.chat_attachments; blocks all overwrites once attached to a clinical message.
CREATE OR REPLACE FUNCTION public.can_update_chat_storage_object(
    p_bucket_id TEXT,
    p_object_name TEXT
)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    IF NOT public.can_upload_chat_storage_object(p_bucket_id, p_object_name) THEN
        RETURN false;
    END IF;

    RETURN NOT EXISTS (
        SELECT 1
        FROM public.chat_attachments ca
        WHERE ca.storage_bucket = 'chat-attachments'
          AND ca.storage_path = p_object_name
    );
END;
$$;

-- Realtime private channel topic authorizer (`chat:conv:<uuid>` & `chat:user:<uuid>`)
CREATE OR REPLACE FUNCTION public.can_subscribe_chat_realtime_topic(p_topic TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_uid UUID := auth.uid();
    v_status TEXT;
    v_raw_role TEXT;
    v_chat_role VARCHAR(30);
    v_conv_id UUID;
    v_user_topic_id UUID;
BEGIN
    IF v_uid IS NULL OR p_topic IS NULL THEN
        RETURN false;
    END IF;

    SELECT UPPER(BTRIM(u.status)), u.role
    INTO v_status, v_raw_role
    FROM public.users u
    WHERE u.id = v_uid;

    IF NOT FOUND OR v_status IS DISTINCT FROM 'ACTIVE' THEN
        RETURN false;
    END IF;

    BEGIN
        v_chat_role := public.map_user_role_to_chat_role(v_raw_role);
    EXCEPTION
        WHEN others THEN
            RETURN false;
    END;

    -- Sub-Admins are strictly prohibited from all chat Realtime topics
    IF v_chat_role = 'SUB_ADMIN' THEN
        RETURN false;
    END IF;

    -- Personal inbox notification channel: chat:user:<public.users.id>
    IF p_topic LIKE 'chat:user:%' AND split_part(p_topic, ':', 4) = '' THEN
        IF v_chat_role NOT IN ('PATIENT', 'DOCTOR', 'CLINIC', 'ADMIN') THEN
            RETURN false;
        END IF;
        v_user_topic_id := public.try_parse_uuid(split_part(p_topic, ':', 3));
        RETURN v_user_topic_id IS NOT NULL AND v_user_topic_id = v_uid;
    END IF;

    -- Conversation channel: chat:conv:<conversation_id>
    IF p_topic LIKE 'chat:conv:%' AND split_part(p_topic, ':', 4) = '' THEN
        v_conv_id := public.try_parse_uuid(split_part(p_topic, ':', 3));
        IF v_conv_id IS NULL THEN
            RETURN false;
        END IF;

        IF public.is_authorized_chat_reader(v_conv_id) THEN
            RETURN true;
        END IF;

        -- Main Admin may subscribe to live push updates ONLY after an audited
        -- thread open has been recorded in public.audit_logs for (v_uid, v_conv_id::text)
        -- and only when the conversation itself is not BLOCKED/NULL
        IF v_chat_role = 'ADMIN' THEN
            RETURN EXISTS (
                SELECT 1
                FROM public.chat_conversations cc
                JOIN public.audit_logs al
                  ON al.user_id = v_uid
                 AND al.target_resource = v_conv_id::TEXT
                 AND al.action IN ('ADMIN_CHAT_THREAD_OPEN', 'ADMIN_CHAT_MESSAGES_VIEW')
                 AND al.created_at >= (NOW() - INTERVAL '12 hours')
                WHERE cc.id = v_conv_id
                  AND UPPER(BTRIM(cc.status)) IN ('ACTIVE', 'ARCHIVED', 'CLOSED')
            );
        END IF;
    END IF;

    RETURN false;
END;
$$;

-- =============================================================================
-- 7B. HARDENED CHAT MESSAGE, PARTICIPANT & READ-RECEIPT TRIGGERS
--     - Enforces trusted participant creation ONLY via service_role / postgres
--       (authenticated direct inserts NEVER create conversations or participants).
--     - Validates receiver_id against intended conversation participants on BOTH
--       direct authenticated inserts and legacy Express service_role inserts.
--     - Preserves legacy image, document, DICOM, prescription & system types even
--       when column DEFAULT 'TEXT' pre-populates NEW.message_type.
--     - Maintains unread_count exclusively inside trusted SECURITY DEFINER triggers.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.fn_chat_messages_before_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_caller_role TEXT := public.caller_jwt_role();
    v_is_trusted_backend BOOLEAN := v_caller_role IN ('service_role', 'postgres');
    v_norm_room VARCHAR(255);
    v_existing_room VARCHAR(255);
    v_existing_conv_status TEXT;
    v_conv_id UUID;
    v_created_new_conv BOOLEAN := false;
    v_sender_found BOOLEAN := false;
    v_sender_status TEXT;
    v_sender_role VARCHAR(30);
    v_receiver_found BOOLEAN := false;
    v_receiver_status TEXT;
    v_receiver_role VARCHAR(30);
    v_resolved_receiver_uid UUID;
    v_patient_id UUID;
    v_dentist_id UUID;
    v_clinic_id UUID;
    v_district_id UUID;
    v_tmp_dentist_id UUID;
    v_tmp_clinic_id UUID;
    v_tmp_district_id UUID;
BEGIN
    IF NEW.id IS NULL THEN
        NEW.id := gen_random_uuid();
    END IF;
    IF NEW.created_at IS NULL THEN
        NEW.created_at := CURRENT_TIMESTAMP;
    END IF;
    IF NEW.updated_at IS NULL THEN
        NEW.updated_at := CURRENT_TIMESTAMP;
    END IF;

    -- Normalize legacy room_id if supplied
    IF NEW.room_id IS NOT NULL AND BTRIM(NEW.room_id) <> '' THEN
        v_norm_room := UPPER(REPLACE(BTRIM(NEW.room_id), '-', '_'));
        NEW.room_id := v_norm_room;
    END IF;

    -- Always resolve canonical message_type from (NEW.message_type, NEW.type) so
    -- column DEFAULT 'TEXT' never masks legacy image/document/DICOM/prescription types
    NEW.message_type := public.resolve_chat_message_type(NEW.message_type, NEW.type);

    -- Inspect sender identity from public.users / dentists / clinics (fail closed on invalid/inactive/NULL status/unknown sender)
    IF NEW.sender_id IS NOT NULL THEN
        SELECT
            UPPER(BTRIM(u.status)),
            public.map_user_role_to_chat_role(u.role),
            d.id,
            COALESCE(d.clinic_id, cl.id),
            COALESCE(u.district_id, d.district_id)
        INTO v_sender_status, v_sender_role, v_tmp_dentist_id, v_tmp_clinic_id, v_tmp_district_id
        FROM public.users u
        LEFT JOIN public.dentists d ON d.user_id = u.id
        LEFT JOIN public.clinics cl ON cl.user_id = u.id
        WHERE u.id = NEW.sender_id;

        v_sender_found := FOUND;

        IF NOT v_sender_found OR v_sender_status IS DISTINCT FROM 'ACTIVE' THEN
            RAISE EXCEPTION 'Chat message sender % does not exist or is not ACTIVE.', NEW.sender_id
                USING ERRCODE = '42501';
        END IF;

        IF v_sender_role = 'PATIENT' THEN
            v_patient_id := NEW.sender_id;
            v_district_id := COALESCE(v_district_id, v_tmp_district_id);
        ELSIF v_sender_role = 'DOCTOR' THEN
            v_dentist_id := v_tmp_dentist_id;
            v_clinic_id := COALESCE(v_clinic_id, v_tmp_clinic_id);
            v_district_id := COALESCE(v_district_id, v_tmp_district_id);
        ELSIF v_sender_role = 'CLINIC' THEN
            v_clinic_id := COALESCE(v_clinic_id, v_tmp_clinic_id);
        END IF;
    END IF;

    IF v_sender_role IS NOT NULL THEN
        NEW.sender_role := v_sender_role;
    END IF;

    -- =========================================================================
    -- UNTRUSTED DIRECT CLIENT PATH (`authenticated`):
    --   - Cannot auto-create conversations (must pass existing conversation_id)
    --   - Must be an active authorized sender with sender_id = auth.uid()
    --   - Any non-null receiver_id MUST already belong to the conversation
    -- =========================================================================
    IF NOT v_is_trusted_backend THEN
        NEW.created_at := CURRENT_TIMESTAMP;
        NEW.updated_at := CURRENT_TIMESTAMP;

        IF NEW.conversation_id IS NULL THEN
            RAISE EXCEPTION 'Direct client message insert requires an existing authorized conversation_id.'
                USING ERRCODE = '42501';
        END IF;

        IF auth.uid() IS NULL
           OR NEW.sender_id IS DISTINCT FROM auth.uid()
           OR NOT public.is_authorized_chat_sender(NEW.conversation_id) THEN
            RAISE EXCEPTION 'Caller is not an authorized active sender for conversation %.', NEW.conversation_id
                USING ERRCODE = '42501';
        END IF;

        IF NEW.receiver_id IS NOT NULL
           AND NOT public.is_valid_conversation_receiver(NEW.conversation_id, NEW.receiver_id) THEN
            RAISE EXCEPTION 'Unauthorized receiver_id %: receiver is not an active participant of conversation %.',
                NEW.receiver_id, NEW.conversation_id
                USING ERRCODE = '42501';
        END IF;

        SELECT cc.legacy_room_id
        INTO v_existing_room
        FROM public.chat_conversations cc
        WHERE cc.id = NEW.conversation_id;

        IF NEW.room_id IS NULL OR BTRIM(NEW.room_id) = '' THEN
            NEW.room_id := COALESCE(
                v_existing_room,
                'CONV_' || UPPER(REPLACE(NEW.conversation_id::TEXT, '-', '_'))
            );
        END IF;

        RETURN NEW;
    END IF;

    -- =========================================================================
    -- TRUSTED BACKEND / ADMIN PATH (`service_role` / `postgres`):
    --   Preserves legacy Express compatibility while validating receiver_id
    --   against the conversation's intended clinical participants.
    -- =========================================================================
    IF NEW.receiver_id IS NOT NULL AND NEW.receiver_id = NEW.sender_id THEN
        NEW.receiver_id := NULL;
    END IF;

    IF NEW.receiver_id IS NOT NULL THEN
        -- Support legacy callers that passed dentists.id or clinics.id instead of users.id
        IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = NEW.receiver_id) THEN
            SELECT COALESCE(d.user_id, cl.user_id)
            INTO v_resolved_receiver_uid
            FROM (SELECT 1) AS dummy
            LEFT JOIN public.dentists d ON d.id = NEW.receiver_id
            LEFT JOIN public.clinics cl ON cl.id = NEW.receiver_id;

            IF v_resolved_receiver_uid IS NOT NULL THEN
                NEW.receiver_id := v_resolved_receiver_uid;
            END IF;
        END IF;

        SELECT
            UPPER(BTRIM(u.status)),
            public.map_user_role_to_chat_role(u.role),
            d.id,
            COALESCE(d.clinic_id, cl.id),
            COALESCE(u.district_id, d.district_id)
        INTO v_receiver_status, v_receiver_role, v_tmp_dentist_id, v_tmp_clinic_id, v_tmp_district_id
        FROM public.users u
        LEFT JOIN public.dentists d ON d.user_id = u.id
        LEFT JOIN public.clinics cl ON cl.user_id = u.id
        WHERE u.id = NEW.receiver_id;

        v_receiver_found := FOUND;

        IF NOT v_receiver_found OR v_receiver_status IS DISTINCT FROM 'ACTIVE' THEN
            RAISE EXCEPTION 'Chat message receiver % does not exist or is not ACTIVE.', NEW.receiver_id
                USING ERRCODE = '42501';
        END IF;

        -- Only bind complementary clinical party slots (never same-role or Admin/Sub-Admin)
        IF v_receiver_found
           AND v_receiver_status = 'ACTIVE'
           AND v_receiver_role IN ('PATIENT', 'DOCTOR', 'CLINIC')
           AND v_receiver_role IS DISTINCT FROM v_sender_role THEN
            IF v_receiver_role = 'PATIENT' AND v_patient_id IS NULL THEN
                v_patient_id := NEW.receiver_id;
                v_district_id := COALESCE(v_district_id, v_tmp_district_id);
            ELSIF v_receiver_role = 'DOCTOR' AND v_dentist_id IS NULL THEN
                v_dentist_id := v_tmp_dentist_id;
                v_clinic_id := COALESCE(v_clinic_id, v_tmp_clinic_id);
                v_district_id := COALESCE(v_district_id, v_tmp_district_id);
            ELSIF v_receiver_role = 'CLINIC' AND v_clinic_id IS NULL THEN
                v_clinic_id := v_tmp_clinic_id;
            END IF;
        END IF;
    END IF;

    IF NEW.conversation_id IS NOT NULL THEN
        SELECT cc.legacy_room_id, UPPER(BTRIM(cc.status))
        INTO v_existing_room, v_existing_conv_status
        FROM public.chat_conversations cc
        WHERE cc.id = NEW.conversation_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Target conversation % does not exist.', NEW.conversation_id
                USING ERRCODE = '23503';
        END IF;

        IF v_existing_conv_status IS DISTINCT FROM 'ACTIVE' THEN
            RAISE EXCEPTION 'Target conversation % is not active (status=%).',
                NEW.conversation_id, COALESCE(v_existing_conv_status, '<NULL>')
                USING ERRCODE = '42501';
        END IF;

        IF NEW.room_id IS NULL OR BTRIM(NEW.room_id) = '' THEN
            NEW.room_id := COALESCE(
                v_existing_room,
                'CONV_' || UPPER(REPLACE(NEW.conversation_id::TEXT, '-', '_'))
            );
        END IF;
    ELSE
        v_norm_room := COALESCE(v_norm_room, 'PATIENT_GENERAL');
        NEW.room_id := v_norm_room;

        -- 1. Match by legacy_room_id first
        SELECT cc.id, UPPER(BTRIM(cc.status))
        INTO v_conv_id, v_existing_conv_status
        FROM public.chat_conversations cc
        WHERE cc.legacy_room_id = v_norm_room
        LIMIT 1;

        -- 2. Match existing canonical (patient_id, dentist_id) pair if present
        IF v_conv_id IS NULL AND v_patient_id IS NOT NULL AND v_dentist_id IS NOT NULL THEN
            SELECT cc.id, UPPER(BTRIM(cc.status))
            INTO v_conv_id, v_existing_conv_status
            FROM public.chat_conversations cc
            WHERE cc.conversation_type = 'PATIENT_DOCTOR'
              AND cc.patient_id = v_patient_id
              AND cc.dentist_id = v_dentist_id
            LIMIT 1;
        END IF;

        IF v_conv_id IS NOT NULL AND v_existing_conv_status IS DISTINCT FROM 'ACTIVE' THEN
            RAISE EXCEPTION 'Target conversation % is not active (status=%).',
                v_conv_id, COALESCE(v_existing_conv_status, '<NULL>')
                USING ERRCODE = '42501';
        END IF;

        -- 3. Create conversation atomically ONLY on trusted backend path if still not found
        IF v_conv_id IS NULL THEN
            INSERT INTO public.chat_conversations (
                conversation_type,
                patient_id,
                dentist_id,
                clinic_id,
                district_id,
                legacy_room_id,
                status,
                created_by
            ) VALUES (
                CASE
                    WHEN v_patient_id IS NOT NULL AND v_clinic_id IS NOT NULL AND v_dentist_id IS NULL THEN 'PATIENT_CLINIC'
                    WHEN v_dentist_id IS NOT NULL AND v_clinic_id IS NOT NULL AND v_patient_id IS NULL THEN 'DOCTOR_CLINIC'
                    ELSE 'PATIENT_DOCTOR'
                END,
                v_patient_id,
                v_dentist_id,
                v_clinic_id,
                v_district_id,
                v_norm_room,
                'ACTIVE',
                NEW.sender_id
            )
            ON CONFLICT (legacy_room_id) DO NOTHING
            RETURNING id INTO v_conv_id;

            IF v_conv_id IS NOT NULL THEN
                v_created_new_conv := true;
            ELSE
                SELECT cc.id
                INTO v_conv_id
                FROM public.chat_conversations cc
                WHERE cc.legacy_room_id = v_norm_room
                LIMIT 1;
            END IF;
        END IF;

        NEW.conversation_id := v_conv_id;

        -- On brand-new legacy room creation by trusted backend, enroll ONLY an active,
        -- complementary clinical counterparty (e.g. Patient <-> Doctor/Clinic) before
        -- running strict receiver validation below.
        IF v_created_new_conv
           AND NEW.receiver_id IS NOT NULL
           AND v_receiver_found
           AND v_receiver_status = 'ACTIVE'
           AND v_sender_found
           AND v_sender_status = 'ACTIVE'
           AND v_sender_role IN ('PATIENT', 'DOCTOR', 'CLINIC')
           AND v_receiver_role IN ('PATIENT', 'DOCTOR', 'CLINIC')
           AND v_receiver_role IS DISTINCT FROM v_sender_role THEN
            INSERT INTO public.chat_participants (
                conversation_id,
                user_id,
                participant_role,
                can_send,
                is_active,
                unread_count
            ) VALUES (
                NEW.conversation_id,
                NEW.receiver_id,
                v_receiver_role,
                true,
                true,
                0
            )
            ON CONFLICT (conversation_id, user_id) DO NOTHING;
        END IF;
    END IF;

    -- Validate receiver_id against intended conversation participants even on backend inserts
    -- so a client calling legacy POST /api/v1/chat/send cannot inject an arbitrary receiver_id
    IF NEW.receiver_id IS NOT NULL
       AND NOT public.is_valid_conversation_receiver(NEW.conversation_id, NEW.receiver_id) THEN
        RAISE EXCEPTION 'Unauthorized receiver_id %: receiver is not an intended participant of conversation %.',
            NEW.receiver_id, NEW.conversation_id
            USING ERRCODE = '42501';
    END IF;

    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.fn_chat_messages_after_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_trusted_backend BOOLEAN := public.caller_jwt_role() IN ('service_role', 'postgres');
    v_sender_status TEXT;
    v_sender_role VARCHAR(30);
    v_receiver_status TEXT;
    v_receiver_role VARCHAR(30);
    v_patient_id UUID;
    v_dentist_id UUID;
    v_clinic_id UUID;
    v_district_id UUID;
    v_tmp_dentist_id UUID;
    v_tmp_clinic_id UUID;
    v_tmp_district_id UUID;
BEGIN
    IF NEW.conversation_id IS NULL THEN
        RETURN NEW;
    END IF;

    IF v_is_trusted_backend THEN
        -- 1. Trusted backend path: register active sender if needed (NEVER reactivating is_active = false or NULL-status user)
        IF NEW.sender_id IS NOT NULL THEN
            SELECT
                UPPER(BTRIM(u.status)),
                public.map_user_role_to_chat_role(u.role),
                d.id,
                COALESCE(d.clinic_id, cl.id),
                COALESCE(u.district_id, d.district_id)
            INTO v_sender_status, v_sender_role, v_tmp_dentist_id, v_tmp_clinic_id, v_tmp_district_id
            FROM public.users u
            LEFT JOIN public.dentists d ON d.user_id = u.id
            LEFT JOIN public.clinics cl ON cl.user_id = u.id
            WHERE u.id = NEW.sender_id;

            IF FOUND AND v_sender_status = 'ACTIVE' THEN
                IF v_sender_role = 'PATIENT' THEN
                    v_patient_id := NEW.sender_id;
                    v_district_id := COALESCE(v_district_id, v_tmp_district_id);
                ELSIF v_sender_role = 'DOCTOR' THEN
                    v_dentist_id := v_tmp_dentist_id;
                    v_clinic_id := COALESCE(v_clinic_id, v_tmp_clinic_id);
                    v_district_id := COALESCE(v_district_id, v_tmp_district_id);
                ELSIF v_sender_role = 'CLINIC' THEN
                    v_clinic_id := COALESCE(v_clinic_id, v_tmp_clinic_id);
                END IF;

                INSERT INTO public.chat_participants (
                    conversation_id,
                    user_id,
                    participant_role,
                    can_send,
                    is_active,
                    unread_count,
                    last_read_message_id,
                    last_read_at
                ) VALUES (
                    NEW.conversation_id,
                    NEW.sender_id,
                    v_sender_role,
                    true,
                    true,
                    0,
                    NEW.id,
                    NEW.created_at
                )
                ON CONFLICT (conversation_id, user_id) DO UPDATE
                    SET last_read_message_id = EXCLUDED.last_read_message_id,
                        last_read_at = EXCLUDED.last_read_at
                    WHERE public.chat_participants.is_active = true;
            END IF;
        END IF;

        -- 2. Trusted backend path: register receiver ONLY when validated against the conversation
        --    and NEVER reactivate a revoked participant (ON CONFLICT DO NOTHING)
        IF NEW.receiver_id IS NOT NULL
           AND NEW.receiver_id IS DISTINCT FROM NEW.sender_id
           AND public.is_valid_conversation_receiver(NEW.conversation_id, NEW.receiver_id) THEN
            SELECT
                UPPER(BTRIM(u.status)),
                public.map_user_role_to_chat_role(u.role),
                d.id,
                COALESCE(d.clinic_id, cl.id),
                COALESCE(u.district_id, d.district_id)
            INTO v_receiver_status, v_receiver_role, v_tmp_dentist_id, v_tmp_clinic_id, v_tmp_district_id
            FROM public.users u
            LEFT JOIN public.dentists d ON d.user_id = u.id
            LEFT JOIN public.clinics cl ON cl.user_id = u.id
            WHERE u.id = NEW.receiver_id;

            IF FOUND
               AND v_receiver_status = 'ACTIVE'
               AND v_receiver_role IN ('PATIENT', 'DOCTOR', 'CLINIC') THEN
                IF v_receiver_role = 'PATIENT' AND v_patient_id IS NULL THEN
                    v_patient_id := NEW.receiver_id;
                    v_district_id := COALESCE(v_district_id, v_tmp_district_id);
                ELSIF v_receiver_role = 'DOCTOR' AND v_dentist_id IS NULL THEN
                    v_dentist_id := v_tmp_dentist_id;
                    v_clinic_id := COALESCE(v_clinic_id, v_tmp_clinic_id);
                    v_district_id := COALESCE(v_district_id, v_tmp_district_id);
                ELSIF v_receiver_role = 'CLINIC' AND v_clinic_id IS NULL THEN
                    v_clinic_id := v_tmp_clinic_id;
                END IF;

                INSERT INTO public.chat_participants (
                    conversation_id,
                    user_id,
                    participant_role,
                    can_send,
                    is_active,
                    unread_count
                ) VALUES (
                    NEW.conversation_id,
                    NEW.receiver_id,
                    v_receiver_role,
                    true,
                    true,
                    0
                )
                ON CONFLICT (conversation_id, user_id) DO NOTHING;
            END IF;
        END IF;
    ELSE
        -- Untrusted direct client path (`authenticated`): NEVER insert into chat_participants;
        -- only advance the sender's own existing active participant read watermark.
        IF NEW.sender_id IS NOT NULL THEN
            UPDATE public.chat_participants
            SET last_read_message_id = NEW.id,
                last_read_at = NEW.created_at
            WHERE conversation_id = NEW.conversation_id
              AND user_id = NEW.sender_id
              AND is_active = true;
        END IF;
    END IF;

    -- 3. Increment unread_count for all active participants except the sender
    IF COALESCE(NEW.read, false) = false AND COALESCE(NEW.is_deleted, false) = false THEN
        UPDATE public.chat_participants
        SET unread_count = unread_count + 1
        WHERE conversation_id = NEW.conversation_id
          AND is_active = true
          AND (NEW.sender_id IS NULL OR user_id <> NEW.sender_id);
    END IF;

    -- 4. Update conversation summary (only trusted backend may populate unbound party links)
    IF v_is_trusted_backend THEN
        UPDATE public.chat_conversations
        SET last_message_id = NEW.id,
            last_message_preview = CASE
                WHEN COALESCE(NEW.is_deleted, false) THEN '[Message deleted]'
                ELSE LEFT(NEW.message, 250)
            END,
            last_message_at = COALESCE(NEW.created_at, CURRENT_TIMESTAMP),
            patient_id = COALESCE(patient_id, v_patient_id),
            dentist_id = COALESCE(dentist_id, v_dentist_id),
            clinic_id = COALESCE(clinic_id, v_clinic_id),
            district_id = COALESCE(district_id, v_district_id),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.conversation_id;
    ELSE
        UPDATE public.chat_conversations
        SET last_message_id = NEW.id,
            last_message_preview = CASE
                WHEN COALESCE(NEW.is_deleted, false) THEN '[Message deleted]'
                ELSE LEFT(NEW.message, 250)
            END,
            last_message_at = COALESCE(NEW.created_at, CURRENT_TIMESTAMP),
            updated_at = CURRENT_TIMESTAMP
        WHERE id = NEW.conversation_id;
    END IF;

    RETURN NEW;
END;
$$;

-- Keeps chat_participants.unread_count accurate when legacy ChatMessage.markAsRead
-- updates `read = true` or when moderation sets `is_deleted = true`.
CREATE OR REPLACE FUNCTION public.fn_chat_messages_after_update_unread()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    rec RECORD;
BEGIN
    IF NEW.conversation_id IS NOT NULL
       AND (
           COALESCE(NEW.read, false) IS DISTINCT FROM COALESCE(OLD.read, false)
           OR COALESCE(NEW.is_deleted, false) IS DISTINCT FROM COALESCE(OLD.is_deleted, false)
       ) THEN
        FOR rec IN
            SELECT cp.user_id
            FROM public.chat_participants cp
            WHERE cp.conversation_id = NEW.conversation_id
              AND cp.is_active = true
        LOOP
            PERFORM public.recompute_participant_unread_count(NEW.conversation_id, rec.user_id);
        END LOOP;
    END IF;

    RETURN NEW;
END;
$$;

-- Validates direct participant read-watermark updates together with `last_read_at`,
-- preventing independent read-timestamp modifications without active conversation
-- membership and valid non-deleted message checks, and computing `unread_count` securely.
CREATE OR REPLACE FUNCTION public.fn_chat_participants_before_update_read()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_trusted_backend BOOLEAN := public.caller_jwt_role() IN ('service_role', 'postgres');
    v_new_msg_created_at TIMESTAMPTZ;
    v_old_msg_created_at TIMESTAMPTZ;
    v_unread INTEGER := 0;
BEGIN
    IF NOT v_is_trusted_backend THEN
        -- Enforce active conversation membership for any direct client UPDATE
        IF auth.uid() IS NULL
           OR NEW.user_id IS DISTINCT FROM auth.uid()
           OR OLD.user_id IS DISTINCT FROM auth.uid()
           OR NEW.conversation_id IS DISTINCT FROM OLD.conversation_id
           OR NEW.is_active IS DISTINCT FROM true
           OR NOT public.is_authorized_chat_reader(NEW.conversation_id) THEN
            RAISE EXCEPTION 'Unauthorized participant read-state update for conversation %.', NEW.conversation_id
                USING ERRCODE = '42501';
        END IF;

        -- Prevent modifying `last_read_at` independently without advancing `last_read_message_id`
        IF NEW.last_read_at IS DISTINCT FROM OLD.last_read_at
           AND NEW.last_read_message_id IS NOT DISTINCT FROM OLD.last_read_message_id THEN
            RAISE EXCEPTION 'Cannot modify last_read_at independently without updating last_read_message_id to a valid message in conversation %.',
                NEW.conversation_id
                USING ERRCODE = '42501';
        END IF;
    ELSE
        IF NEW.last_read_at IS NOT NULL AND NEW.last_read_message_id IS NULL THEN
            RAISE EXCEPTION 'last_read_at cannot be non-null when last_read_message_id is NULL.'
                USING ERRCODE = '23514';
        END IF;
    END IF;

    IF NEW.last_read_message_id IS DISTINCT FROM OLD.last_read_message_id THEN
        IF NEW.last_read_message_id IS NULL THEN
            IF NOT v_is_trusted_backend THEN
                RAISE EXCEPTION 'Authenticated clients cannot clear last_read_message_id.'
                    USING ERRCODE = '42501';
            END IF;
            NEW.last_read_at := NULL;
        ELSE
            SELECT cm.created_at
            INTO v_new_msg_created_at
            FROM public.chat_messages cm
            WHERE cm.id = NEW.last_read_message_id
              AND cm.conversation_id = NEW.conversation_id
              AND cm.is_deleted = false;

            IF NOT FOUND THEN
                RAISE EXCEPTION 'Invalid last_read_message_id % for conversation %.',
                    NEW.last_read_message_id, NEW.conversation_id
                    USING ERRCODE = '23514';
            END IF;

            IF NOT v_is_trusted_backend THEN
                IF OLD.last_read_message_id IS NOT NULL THEN
                    SELECT cm.created_at
                    INTO v_old_msg_created_at
                    FROM public.chat_messages cm
                    WHERE cm.id = OLD.last_read_message_id
                      AND cm.conversation_id = NEW.conversation_id;

                    IF v_old_msg_created_at IS NOT NULL AND v_new_msg_created_at < v_old_msg_created_at THEN
                        RAISE EXCEPTION 'last_read_message_id cannot move backwards to an older message.'
                            USING ERRCODE = '23514';
                    END IF;
                END IF;

                -- Couple and validate last_read_at with the verified message & server clock
                IF NEW.last_read_at IS NULL OR NEW.last_read_at IS NOT DISTINCT FROM OLD.last_read_at THEN
                    NEW.last_read_at := GREATEST(CURRENT_TIMESTAMP, v_new_msg_created_at);
                ELSE
                    IF NEW.last_read_at < v_new_msg_created_at
                       OR (OLD.last_read_at IS NOT NULL AND NEW.last_read_at < OLD.last_read_at)
                       OR NEW.last_read_at > (CURRENT_TIMESTAMP + INTERVAL '5 seconds') THEN
                        RAISE EXCEPTION 'Invalid last_read_at timestamp % for message % in conversation %.',
                            NEW.last_read_at, NEW.last_read_message_id, NEW.conversation_id
                            USING ERRCODE = '23514';
                    END IF;
                END IF;
            ELSE
                IF NEW.last_read_at IS NULL THEN
                    NEW.last_read_at := GREATEST(CURRENT_TIMESTAMP, v_new_msg_created_at);
                END IF;
            END IF;

            SELECT COUNT(*)::INTEGER
            INTO v_unread
            FROM public.chat_messages cm
            WHERE cm.conversation_id = NEW.conversation_id
              AND cm.is_deleted = false
              AND (cm.sender_id IS NULL OR cm.sender_id <> NEW.user_id)
              AND COALESCE(cm.read, false) = false
              AND cm.created_at > v_new_msg_created_at
              AND cm.id <> NEW.last_read_message_id
              AND NOT EXISTS (
                  SELECT 1
                  FROM public.chat_message_reads cmr
                  WHERE cmr.conversation_id = NEW.conversation_id
                    AND cmr.message_id = cm.id
                    AND cmr.user_id = NEW.user_id
              );

            NEW.unread_count := GREATEST(v_unread, 0);
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

-- Validates chat_message_reads rows against exact conversation membership, message checks,
-- and prevents users from independently tampering with read_at timestamps.
CREATE OR REPLACE FUNCTION public.fn_chat_message_reads_before_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_is_trusted_backend BOOLEAN := public.caller_jwt_role() IN ('service_role', 'postgres');
    v_msg_created_at TIMESTAMPTZ;
BEGIN
    IF TG_OP = 'UPDATE' THEN
        IF NEW.conversation_id IS DISTINCT FROM OLD.conversation_id
           OR NEW.message_id IS DISTINCT FROM OLD.message_id
           OR NEW.user_id IS DISTINCT FROM OLD.user_id THEN
            RAISE EXCEPTION 'chat_message_reads identity columns (conversation_id, message_id, user_id) are immutable.'
                USING ERRCODE = '42501';
        END IF;

        IF NOT v_is_trusted_backend AND NEW.read_at IS DISTINCT FROM OLD.read_at THEN
            RAISE EXCEPTION 'Authenticated users cannot modify an existing read receipt timestamp.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    SELECT cm.created_at
    INTO v_msg_created_at
    FROM public.chat_messages cm
    WHERE cm.id = NEW.message_id
      AND cm.conversation_id = NEW.conversation_id
      AND cm.is_deleted = false;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Read receipt message_id % does not belong to active messages in conversation %.',
            NEW.message_id, NEW.conversation_id
            USING ERRCODE = '23514';
    END IF;

    IF NOT v_is_trusted_backend THEN
        IF auth.uid() IS NULL
           OR NEW.user_id IS DISTINCT FROM auth.uid()
           OR NOT public.is_authorized_chat_reader(NEW.conversation_id) THEN
            RAISE EXCEPTION 'Unauthorized read receipt write for conversation %.', NEW.conversation_id
                USING ERRCODE = '42501';
        END IF;

        IF TG_OP = 'INSERT' THEN
            IF NEW.read_at IS NULL THEN
                NEW.read_at := GREATEST(CURRENT_TIMESTAMP, v_msg_created_at);
            ELSIF NEW.read_at < v_msg_created_at
               OR NEW.read_at > (CURRENT_TIMESTAMP + INTERVAL '5 seconds') THEN
                RAISE EXCEPTION 'Invalid read_at timestamp % for message % in conversation %.',
                    NEW.read_at, NEW.message_id, NEW.conversation_id
                    USING ERRCODE = '23514';
            END IF;
        END IF;
    ELSIF NEW.read_at IS NULL THEN
        NEW.read_at := GREATEST(CURRENT_TIMESTAMP, v_msg_created_at);
    END IF;

    RETURN NEW;
END;
$$;

-- Synchronizes participant read watermark & unread_count via trusted SECURITY DEFINER trigger
CREATE OR REPLACE FUNCTION public.fn_chat_message_reads_after_write()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_msg_created_at TIMESTAMPTZ;
    v_cur_last_read_msg_id UUID;
    v_cur_watermark_at TIMESTAMPTZ;
BEGIN
    SELECT cm.created_at
    INTO v_msg_created_at
    FROM public.chat_messages cm
    WHERE cm.id = NEW.message_id
      AND cm.conversation_id = NEW.conversation_id;

    SELECT cp.last_read_message_id, cm.created_at
    INTO v_cur_last_read_msg_id, v_cur_watermark_at
    FROM public.chat_participants cp
    LEFT JOIN public.chat_messages cm
           ON cm.id = cp.last_read_message_id
          AND cm.conversation_id = cp.conversation_id
    WHERE cp.conversation_id = NEW.conversation_id
      AND cp.user_id = NEW.user_id;

    IF FOUND THEN
        IF NEW.message_id IS DISTINCT FROM v_cur_last_read_msg_id
           AND (
               v_cur_watermark_at IS NULL
               OR (v_msg_created_at IS NOT NULL AND v_msg_created_at >= v_cur_watermark_at)
           ) THEN
            UPDATE public.chat_participants
            SET last_read_message_id = NEW.message_id,
                last_read_at = COALESCE(NEW.read_at, CURRENT_TIMESTAMP)
            WHERE conversation_id = NEW.conversation_id
              AND user_id = NEW.user_id
              AND is_active = true;
        END IF;

        PERFORM public.recompute_participant_unread_count(NEW.conversation_id, NEW.user_id);
    END IF;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_chat_messages_before_insert ON public.chat_messages;
CREATE TRIGGER trg_chat_messages_before_insert
    BEFORE INSERT ON public.chat_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_chat_messages_before_insert();

DROP TRIGGER IF EXISTS trg_chat_messages_after_insert ON public.chat_messages;
CREATE TRIGGER trg_chat_messages_after_insert
    AFTER INSERT ON public.chat_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_chat_messages_after_insert();

DROP TRIGGER IF EXISTS trg_chat_messages_after_update_unread ON public.chat_messages;
CREATE TRIGGER trg_chat_messages_after_update_unread
    AFTER UPDATE OF read, is_deleted ON public.chat_messages
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_chat_messages_after_update_unread();

DROP TRIGGER IF EXISTS trg_chat_participants_before_update_read ON public.chat_participants;
CREATE TRIGGER trg_chat_participants_before_update_read
    BEFORE UPDATE ON public.chat_participants
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_chat_participants_before_update_read();

DROP TRIGGER IF EXISTS trg_chat_message_reads_before_write ON public.chat_message_reads;
CREATE TRIGGER trg_chat_message_reads_before_write
    BEFORE INSERT OR UPDATE ON public.chat_message_reads
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_chat_message_reads_before_write();

DROP TRIGGER IF EXISTS trg_chat_message_reads_after_write ON public.chat_message_reads;
CREATE TRIGGER trg_chat_message_reads_after_write
    AFTER INSERT OR UPDATE ON public.chat_message_reads
    FOR EACH ROW
    EXECUTE FUNCTION public.fn_chat_message_reads_after_write();

-- Restrict EXECUTE permissions strictly (no PUBLIC or anon execution; internal unread
-- recomputation helper is additionally revoked from authenticated)
REVOKE ALL ON FUNCTION public.caller_jwt_role() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.map_user_role_to_chat_role(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.resolve_chat_message_type(TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.try_parse_uuid(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_authorized_chat_reader(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_authorized_chat_sender(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_message_in_conversation(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_valid_conversation_receiver(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.is_valid_chat_read_receipt(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.recompute_participant_unread_count(UUID, UUID) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.fn_chat_messages_before_insert() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_chat_messages_after_insert() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_chat_messages_after_update_unread() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_chat_participants_before_update_read() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_chat_message_reads_before_write() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.fn_chat_message_reads_after_write() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_read_chat_storage_object(TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_upload_chat_storage_object(TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_update_chat_storage_object(TEXT, TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.can_subscribe_chat_realtime_topic(TEXT) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.caller_jwt_role() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.map_user_role_to_chat_role(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.resolve_chat_message_type(TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.try_parse_uuid(TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_authorized_chat_reader(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_authorized_chat_sender(UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_message_in_conversation(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_valid_conversation_receiver(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_valid_chat_read_receipt(UUID, UUID) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.recompute_participant_unread_count(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.fn_chat_messages_before_insert() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_chat_messages_after_insert() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_chat_messages_after_update_unread() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_chat_participants_before_update_read() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_chat_message_reads_before_write() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_chat_message_reads_after_write() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_read_chat_storage_object(TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_upload_chat_storage_object(TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_update_chat_storage_object(TEXT, TEXT) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.can_subscribe_chat_realtime_topic(TEXT) TO authenticated, service_role;

-- =============================================================================
-- 8. PRIVILEGE LOCKDOWN & ROW LEVEL SECURITY POLICIES
-- =============================================================================
ALTER TABLE public.chat_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_reads ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_attachments ENABLE ROW LEVEL SECURITY;

-- Revoke all anonymous & PUBLIC table privileges on ONLY the 5 chat tables
REVOKE ALL ON TABLE public.chat_conversations FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.chat_participants FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.chat_messages FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.chat_message_reads FROM PUBLIC, anon;
REVOKE ALL ON TABLE public.chat_attachments FROM PUBLIC, anon;

-- Revoke excessive privileges (UPDATE/DELETE/TRUNCATE) from authenticated before granting least-privilege
REVOKE ALL ON TABLE public.chat_conversations FROM authenticated;
REVOKE ALL ON TABLE public.chat_participants FROM authenticated;
REVOKE ALL ON TABLE public.chat_messages FROM authenticated;
REVOKE ALL ON TABLE public.chat_message_reads FROM authenticated;
REVOKE ALL ON TABLE public.chat_attachments FROM authenticated;

-- Grant full access to service_role (Express backend) and least-privilege RLS-governed access to authenticated
-- NOTE: `unread_count` is intentionally EXCLUDED from authenticated UPDATE privileges so unread counts
--       remain exclusively controlled by trusted database triggers / service_role backend logic.
GRANT ALL ON TABLE public.chat_conversations TO service_role;
GRANT ALL ON TABLE public.chat_participants TO service_role;
GRANT ALL ON TABLE public.chat_messages TO service_role;
GRANT ALL ON TABLE public.chat_message_reads TO service_role;
GRANT ALL ON TABLE public.chat_attachments TO service_role;

GRANT SELECT ON TABLE public.chat_conversations TO authenticated;
GRANT SELECT, UPDATE (muted_until, last_read_message_id, last_read_at) ON TABLE public.chat_participants TO authenticated;
GRANT SELECT, INSERT ON TABLE public.chat_messages TO authenticated;
GRANT SELECT, INSERT, UPDATE (read_at) ON TABLE public.chat_message_reads TO authenticated;
GRANT SELECT ON TABLE public.chat_attachments TO authenticated;

-- Explicitly drop the documented legacy permissive policy on public.chat_messages
-- (from backend/supabase_schema.sql line 441) plus our own named Phase 2B policies for idempotency
DROP POLICY IF EXISTS "Allow All Chat Messages" ON public.chat_messages;

DROP POLICY IF EXISTS chat_conversations_select_authorized ON public.chat_conversations;
DROP POLICY IF EXISTS chat_participants_select_authorized ON public.chat_participants;
DROP POLICY IF EXISTS chat_participants_update_self_read_state ON public.chat_participants;
DROP POLICY IF EXISTS chat_messages_select_authorized ON public.chat_messages;
DROP POLICY IF EXISTS chat_messages_insert_authorized ON public.chat_messages;
DROP POLICY IF EXISTS chat_message_reads_select_authorized ON public.chat_message_reads;
DROP POLICY IF EXISTS chat_message_reads_insert_self ON public.chat_message_reads;
DROP POLICY IF EXISTS chat_message_reads_update_self ON public.chat_message_reads;
DROP POLICY IF EXISTS chat_attachments_select_authorized ON public.chat_attachments;

-- Fail-safe check: abort if any undocumented third-party policy exists on public.chat_messages
DO $$
DECLARE
    v_unexpected_policies TEXT;
BEGIN
    SELECT string_agg(policyname, ', ')
    INTO v_unexpected_policies
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'chat_messages';

    IF v_unexpected_policies IS NOT NULL THEN
        RAISE EXCEPTION
            'Migration halted for safety: unexpected policy/policies still present on public.chat_messages (%). Inspect before dropping.',
            v_unexpected_policies;
    END IF;
END $$;

-- 8A. chat_conversations policies
CREATE POLICY chat_conversations_select_authorized
    ON public.chat_conversations
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING (public.is_authorized_chat_reader(id));

-- 8B. chat_participants policies
CREATE POLICY chat_participants_select_authorized
    ON public.chat_participants
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING (public.is_authorized_chat_reader(conversation_id));

CREATE POLICY chat_participants_update_self_read_state
    ON public.chat_participants
    AS PERMISSIVE
    FOR UPDATE
    TO authenticated
    USING (
        user_id = auth.uid()
        AND is_active = true
        AND public.is_authorized_chat_reader(conversation_id)
    )
    WITH CHECK (
        user_id = auth.uid()
        AND is_active = true
        AND public.is_authorized_chat_reader(conversation_id)
        AND (
            (last_read_message_id IS NULL AND last_read_at IS NULL)
            OR (
                last_read_message_id IS NOT NULL
                AND last_read_at IS NOT NULL
                AND public.is_valid_chat_read_receipt(conversation_id, last_read_message_id)
            )
        )
    );

-- 8C. chat_messages policies (Requires non-null conversation_id, active sender check,
--     and validated receiver_id; blocks soft-deleted messages)
CREATE POLICY chat_messages_select_authorized
    ON public.chat_messages
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING (
        is_deleted = false
        AND conversation_id IS NOT NULL
        AND public.is_authorized_chat_reader(conversation_id)
    );

CREATE POLICY chat_messages_insert_authorized
    ON public.chat_messages
    AS PERMISSIVE
    FOR INSERT
    TO authenticated
    WITH CHECK (
        sender_id = auth.uid()
        AND is_deleted = false
        AND conversation_id IS NOT NULL
        AND public.is_authorized_chat_sender(conversation_id)
        AND (
            receiver_id IS NULL
            OR public.is_valid_conversation_receiver(conversation_id, receiver_id)
        )
    );

-- 8D. chat_message_reads policies (Validates user_id = auth.uid(), active reader access,
--     and exact message_id membership in conversation_id on both INSERT and UPDATE)
CREATE POLICY chat_message_reads_select_authorized
    ON public.chat_message_reads
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING (public.is_authorized_chat_reader(conversation_id));

CREATE POLICY chat_message_reads_insert_self
    ON public.chat_message_reads
    AS PERMISSIVE
    FOR INSERT
    TO authenticated
    WITH CHECK (
        user_id = auth.uid()
        AND public.is_valid_chat_read_receipt(conversation_id, message_id)
    );

CREATE POLICY chat_message_reads_update_self
    ON public.chat_message_reads
    AS PERMISSIVE
    FOR UPDATE
    TO authenticated
    USING (
        user_id = auth.uid()
        AND public.is_valid_chat_read_receipt(conversation_id, message_id)
    )
    WITH CHECK (
        user_id = auth.uid()
        AND public.is_valid_chat_read_receipt(conversation_id, message_id)
    );

-- 8E. chat_attachments metadata policies
CREATE POLICY chat_attachments_select_authorized
    ON public.chat_attachments
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING (public.is_authorized_chat_reader(conversation_id));

-- =============================================================================
-- 8F. PRIVATE STORAGE BUCKET POLICIES (storage.objects)
--     - Zero existing storage.objects policies (e.g. dentaguru-storage) are dropped or altered.
--     - Uses 3 AS PERMISSIVE grants (SELECT, INSERT, in-flight UPDATE) for `authenticated`
--       paired with 5 AS RESTRICTIVE guards:
--         * `anon`: blocked unconditionally when bucket_id = 'chat-attachments'; TRUE for all other buckets.
--         * `authenticated` SELECT: TRUE for other buckets OR can_read_chat_storage_object(bucket_id, name).
--         * `authenticated` INSERT: TRUE for other buckets OR can_upload_chat_storage_object(bucket_id, name).
--         * `authenticated` UPDATE: TRUE for other buckets OR can_update_chat_storage_object(bucket_id, name)
--           (allows upload finalization before attachment commit; blocks overwriting committed clinical files).
--         * `authenticated` DELETE: TRUE for other buckets; FALSE for 'chat-attachments' (immutable retention).
-- =============================================================================
DROP POLICY IF EXISTS chat_storage_objects_select_authorized ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_insert_authorized ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_update_authorized ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_anon_deny_all ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_restrict_select ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_restrict_insert ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_restrict_update ON storage.objects;
DROP POLICY IF EXISTS chat_storage_objects_restrict_delete ON storage.objects;

-- Permissive Grants (authenticated only, chat-attachments only)
CREATE POLICY chat_storage_objects_select_authorized
    ON storage.objects
    AS PERMISSIVE
    FOR SELECT
    TO authenticated
    USING (
        bucket_id = 'chat-attachments'
        AND public.can_read_chat_storage_object(bucket_id, name)
    );

CREATE POLICY chat_storage_objects_insert_authorized
    ON storage.objects
    AS PERMISSIVE
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id = 'chat-attachments'
        AND public.can_upload_chat_storage_object(bucket_id, name)
    );

CREATE POLICY chat_storage_objects_update_authorized
    ON storage.objects
    AS PERMISSIVE
    FOR UPDATE
    TO authenticated
    USING (
        bucket_id = 'chat-attachments'
        AND public.can_update_chat_storage_object(bucket_id, name)
    )
    WITH CHECK (
        bucket_id = 'chat-attachments'
        AND public.can_update_chat_storage_object(bucket_id, name)
    );

-- Restrictive Guards (neutralize any broad permissive policy on storage.objects for chat-attachments
-- while always evaluating TRUE for dentaguru-storage and any other non-chat bucket)
CREATE POLICY chat_storage_objects_anon_deny_all
    ON storage.objects
    AS RESTRICTIVE
    FOR ALL
    TO anon
    USING (bucket_id IS DISTINCT FROM 'chat-attachments')
    WITH CHECK (bucket_id IS DISTINCT FROM 'chat-attachments');

CREATE POLICY chat_storage_objects_restrict_select
    ON storage.objects
    AS RESTRICTIVE
    FOR SELECT
    TO authenticated
    USING (
        bucket_id IS DISTINCT FROM 'chat-attachments'
        OR public.can_read_chat_storage_object(bucket_id, name)
    );

CREATE POLICY chat_storage_objects_restrict_insert
    ON storage.objects
    AS RESTRICTIVE
    FOR INSERT
    TO authenticated
    WITH CHECK (
        bucket_id IS DISTINCT FROM 'chat-attachments'
        OR public.can_upload_chat_storage_object(bucket_id, name)
    );

CREATE POLICY chat_storage_objects_restrict_update
    ON storage.objects
    AS RESTRICTIVE
    FOR UPDATE
    TO authenticated
    USING (
        bucket_id IS DISTINCT FROM 'chat-attachments'
        OR public.can_update_chat_storage_object(bucket_id, name)
    )
    WITH CHECK (
        bucket_id IS DISTINCT FROM 'chat-attachments'
        OR public.can_update_chat_storage_object(bucket_id, name)
    );

CREATE POLICY chat_storage_objects_restrict_delete
    ON storage.objects
    AS RESTRICTIVE
    FOR DELETE
    TO authenticated
    USING (bucket_id IS DISTINCT FROM 'chat-attachments');

-- =============================================================================
-- 8G. SUPABASE REALTIME PRIVATE BROADCAST AUTHORIZATION (realtime.messages)
--     - Preserves EVERY unrelated policy on realtime.messages untouched.
--     - Separates anon vs authenticated restrictive guards without deprecated auth.role().
-- =============================================================================
DO $$
BEGIN
    IF EXISTS (
        SELECT 1
        FROM information_schema.tables
        WHERE table_schema = 'realtime'
          AND table_name = 'messages'
    ) THEN
        IF NOT EXISTS (
            SELECT 1
            FROM pg_class c
            JOIN pg_namespace n ON n.oid = c.relnamespace
            WHERE n.nspname = 'realtime'
              AND c.relname = 'messages'
              AND c.relrowsecurity = true
        ) THEN
            ALTER TABLE realtime.messages ENABLE ROW LEVEL SECURITY;
        END IF;

        DROP POLICY IF EXISTS chat_realtime_broadcast_select ON realtime.messages;
        DROP POLICY IF EXISTS chat_realtime_broadcast_insert ON realtime.messages;
        DROP POLICY IF EXISTS chat_realtime_anon_deny_chat_topics ON realtime.messages;
        DROP POLICY IF EXISTS chat_realtime_restrict_topic_select ON realtime.messages;
        DROP POLICY IF EXISTS chat_realtime_restrict_topic_insert ON realtime.messages;

        -- 1. Permissive grant: receive private broadcasts / presence on authorized chat topics
        CREATE POLICY chat_realtime_broadcast_select
            ON realtime.messages
            AS PERMISSIVE
            FOR SELECT
            TO authenticated
            USING (
                realtime.topic() LIKE 'chat:%'
                AND public.can_subscribe_chat_realtime_topic(realtime.topic())
            );

        -- 2. Permissive grant: publish client typing / presence on active conversation topics where caller can send
        CREATE POLICY chat_realtime_broadcast_insert
            ON realtime.messages
            AS PERMISSIVE
            FOR INSERT
            TO authenticated
            WITH CHECK (
                realtime.topic() LIKE 'chat:conv:%'
                AND split_part(realtime.topic(), ':', 4) = ''
                AND realtime.messages.extension IN ('broadcast', 'presence')
                AND public.is_authorized_chat_sender(
                    public.try_parse_uuid(split_part(realtime.topic(), ':', 3))
                )
            );

        -- 3. Restrictive guard for anon: deny all 'chat:%' topics; pass non-'chat:%' topics
        CREATE POLICY chat_realtime_anon_deny_chat_topics
            ON realtime.messages
            AS RESTRICTIVE
            FOR ALL
            TO anon
            USING (COALESCE(realtime.topic(), '') NOT LIKE 'chat:%')
            WITH CHECK (COALESCE(realtime.topic(), '') NOT LIKE 'chat:%');

        -- 4. Restrictive guard for authenticated SELECT
        CREATE POLICY chat_realtime_restrict_topic_select
            ON realtime.messages
            AS RESTRICTIVE
            FOR SELECT
            TO authenticated
            USING (
                COALESCE(realtime.topic(), '') NOT LIKE 'chat:%'
                OR public.can_subscribe_chat_realtime_topic(realtime.topic())
            );

        -- 5. Restrictive guard for authenticated INSERT
        CREATE POLICY chat_realtime_restrict_topic_insert
            ON realtime.messages
            AS RESTRICTIVE
            FOR INSERT
            TO authenticated
            WITH CHECK (
                COALESCE(realtime.topic(), '') NOT LIKE 'chat:%'
                OR (
                    realtime.topic() LIKE 'chat:conv:%'
                    AND split_part(realtime.topic(), ':', 4) = ''
                    AND realtime.messages.extension IN ('broadcast', 'presence')
                    AND public.is_authorized_chat_sender(
                        public.try_parse_uuid(split_part(realtime.topic(), ':', 3))
                    )
                )
            );
    END IF;
END $$;

-- =============================================================================
-- 9. IN-TRANSACTION POST-MIGRATION INTEGRITY ASSERTIONS
--    Automatically aborts & rolls back the entire transaction if any security
--    invariant fails before COMMIT.
-- =============================================================================
DO $$
DECLARE
    v_null_conv_rows BIGINT;
    v_storage_perm_count INTEGER;
    v_storage_rest_count INTEGER;
BEGIN
    -- 1. Verify all 4 new tables exist
    IF to_regclass('public.chat_conversations') IS NULL
       OR to_regclass('public.chat_participants') IS NULL
       OR to_regclass('public.chat_message_reads') IS NULL
       OR to_regclass('public.chat_attachments') IS NULL THEN
        RAISE EXCEPTION 'Post-migration check failed: one or more Phase 2B chat tables missing.';
    END IF;

    -- 2. Verify zero orphan chat_messages without conversation_id
    SELECT COUNT(*) INTO v_null_conv_rows
    FROM public.chat_messages
    WHERE conversation_id IS NULL;

    IF v_null_conv_rows > 0 THEN
        RAISE EXCEPTION 'Post-migration check failed: % chat_messages rows still have conversation_id IS NULL.', v_null_conv_rows;
    END IF;

    -- 3. Verify anon has ZERO SELECT or INSERT privilege on all 5 chat tables
    IF has_table_privilege('anon', 'public.chat_conversations', 'SELECT')
       OR has_table_privilege('anon', 'public.chat_participants', 'SELECT')
       OR has_table_privilege('anon', 'public.chat_messages', 'SELECT')
       OR has_table_privilege('anon', 'public.chat_messages', 'INSERT')
       OR has_table_privilege('anon', 'public.chat_message_reads', 'SELECT')
       OR has_table_privilege('anon', 'public.chat_attachments', 'SELECT') THEN
        RAISE EXCEPTION 'Post-migration check failed: anon role still retains table privileges on chat tables.';
    END IF;

    -- 4. Verify anon has ZERO EXECUTE privilege on Storage & Chat authorizer/helper functions
    IF has_function_privilege('anon', 'public.is_authorized_chat_reader(uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.is_authorized_chat_sender(uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.is_message_in_conversation(uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.is_valid_conversation_receiver(uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.is_valid_chat_read_receipt(uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.recompute_participant_unread_count(uuid, uuid)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.can_read_chat_storage_object(text, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.can_upload_chat_storage_object(text, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.can_update_chat_storage_object(text, text)', 'EXECUTE')
       OR has_function_privilege('anon', 'public.can_subscribe_chat_realtime_topic(text)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Post-migration check failed: anon role still retains EXECUTE privilege on chat SECURITY DEFINER functions.';
    END IF;

    -- 5. Verify legacy permissive policy is gone
    IF EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'chat_messages'
          AND policyname = 'Allow All Chat Messages'
    ) THEN
        RAISE EXCEPTION 'Post-migration check failed: legacy "Allow All Chat Messages" policy still exists.';
    END IF;

    -- 6. Verify private storage bucket exists and is strictly non-public
    IF NOT EXISTS (
        SELECT 1
        FROM storage.buckets
        WHERE id = 'chat-attachments'
          AND public = false
    ) THEN
        RAISE EXCEPTION 'Post-migration check failed: storage bucket chat-attachments is missing or marked public.';
    END IF;

    -- 7. Verify exact 3 PERMISSIVE + 5 RESTRICTIVE Phase 2B policies exist on storage.objects
    SELECT
        COUNT(*) FILTER (WHERE permissive = 'PERMISSIVE'),
        COUNT(*) FILTER (WHERE permissive = 'RESTRICTIVE')
    INTO v_storage_perm_count, v_storage_rest_count
    FROM pg_policies
    WHERE schemaname = 'storage'
      AND tablename = 'objects'
      AND policyname IN (
          'chat_storage_objects_select_authorized',
          'chat_storage_objects_insert_authorized',
          'chat_storage_objects_update_authorized',
          'chat_storage_objects_anon_deny_all',
          'chat_storage_objects_restrict_select',
          'chat_storage_objects_restrict_insert',
          'chat_storage_objects_restrict_update',
          'chat_storage_objects_restrict_delete'
      );

    IF v_storage_perm_count <> 3 OR v_storage_rest_count <> 5 THEN
        RAISE EXCEPTION
            'Post-migration check failed: expected 3 PERMISSIVE and 5 RESTRICTIVE storage.objects policies, found % and %.',
            v_storage_perm_count, v_storage_rest_count;
    END IF;

    -- 8. Verify authenticated clients CANNOT directly UPDATE unread_count or call recompute_participant_unread_count
    IF has_column_privilege('authenticated', 'public.chat_participants', 'unread_count', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.chat_participants', 'is_active', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.chat_participants', 'can_send', 'UPDATE')
       OR has_column_privilege('authenticated', 'public.chat_participants', 'participant_role', 'UPDATE')
       OR has_function_privilege('authenticated', 'public.recompute_participant_unread_count(uuid, uuid)', 'EXECUTE') THEN
        RAISE EXCEPTION 'Post-migration check failed: authenticated role retains forbidden UPDATE/EXECUTE privileges on participant unread/role controls.';
    END IF;
END $$;

COMMIT;
