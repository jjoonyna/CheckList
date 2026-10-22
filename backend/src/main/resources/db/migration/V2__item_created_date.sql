ALTER TABLE checklist_item ADD COLUMN created_date DATE NOT NULL DEFAULT CURRENT_DATE;
CREATE INDEX item_effective_date_idx ON checklist_item ((COALESCE(due_date, created_date)));
ALTER TABLE checklist_item ADD CONSTRAINT item_depth_check CHECK (depth BETWEEN 1 AND 3);
ALTER TABLE checklist_item ADD CONSTRAINT item_parent_check CHECK ((depth = 1 AND parent_id IS NULL) OR (depth > 1 AND parent_id IS NOT NULL));
ALTER TABLE checklist_item ADD CONSTRAINT item_status_check CHECK (status IN ('OPEN', 'DONE'));
ALTER TABLE comment_attachment ADD CONSTRAINT attachment_size_check CHECK (size >= 0 AND size <= 500000000);