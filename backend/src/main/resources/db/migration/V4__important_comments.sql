ALTER TABLE item_comment ADD COLUMN important BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE item_comment ADD CONSTRAINT comment_important_original_check CHECK (NOT important OR parent_id IS NULL);
CREATE INDEX comment_display_order_idx ON item_comment(item_id, important DESC, created_at DESC, id DESC);