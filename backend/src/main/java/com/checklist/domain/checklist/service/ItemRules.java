package com.checklist.domain.checklist.service;



public final class ItemRules {
    public static final long MAX_ATTACHMENT_BYTES = 500_000_000L;
    private ItemRules() {}

    public static int depthForParentDepth(int parentDepth) {
        if (parentDepth < 0 || parentDepth >= 3) throw new IllegalArgumentException("항목은 최대 3단계까지 만들 수 있습니다.");
        return parentDepth + 1;
    }

    public static void validateTitle(String title) {
        if (title == null || title.isBlank() || title.length() > 200) throw new IllegalArgumentException("제목은 1~200자로 입력해 주세요.");
    }

    public static void validateAttachmentTotal(long bytes) {
        if (bytes < 0 || bytes > MAX_ATTACHMENT_BYTES) throw new IllegalArgumentException("첨부 파일 합계는 500MB 이하여야 합니다.");
    }
}
