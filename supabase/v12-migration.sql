-- REALITY MERGE v12 — Read receipts (ticks) for the Chats tab
-- Run this in the Supabase SQL editor after v11-migration.sql
-- ================================================================
--
-- v4 already added `read_at` on `messages`, but list_conversations()
-- never surfaced it, so the Chats list had no way to show "sent" vs
-- "read" for your own last message. This just adds that one column.

CREATE OR REPLACE FUNCTION public.list_conversations()
RETURNS TABLE (
  other_user_id uuid,
  other_username text,
  last_message text,
  last_message_at timestamptz,
  last_sender_id uuid,
  last_message_read_at timestamptz,
  unread_count bigint
)
LANGUAGE sql
STABLE
AS $$
  WITH mine AS (
    SELECT
      CASE WHEN sender_id = auth.uid() THEN recipient_id ELSE sender_id END AS other_user_id,
      sender_id,
      content,
      created_at,
      read_at
    FROM public.messages
    WHERE sender_id = auth.uid() OR recipient_id = auth.uid()
  ),
  ranked AS (
    SELECT
      other_user_id,
      sender_id,
      content,
      created_at,
      read_at,
      row_number() OVER (PARTITION BY other_user_id ORDER BY created_at DESC) AS rn
    FROM mine
  )
  SELECT
    r.other_user_id,
    p.username AS other_username,
    r.content AS last_message,
    r.created_at AS last_message_at,
    r.sender_id AS last_sender_id,
    r.read_at AS last_message_read_at,
    (
      SELECT count(*) FROM mine m
      WHERE m.other_user_id = r.other_user_id
        AND m.sender_id = r.other_user_id
        AND m.read_at IS NULL
    ) AS unread_count
  FROM ranked r
  JOIN public.profiles p ON p.id = r.other_user_id
  WHERE r.rn = 1
  ORDER BY r.created_at DESC;
$$;
