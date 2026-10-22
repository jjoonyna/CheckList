package com.checklist.domain.checklist.service;



import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class ChecklistRulesTest {
    @Test void permitsThreeLevelsAndRejectsFourth() {
        assertEquals(3, ItemRules.depthForParentDepth(2));
        assertThrows(IllegalArgumentException.class, () -> ItemRules.depthForParentDepth(3));
    }

    @Test void attachmentAggregateLimitIsExactlyFiveHundredMillionBytes() {
        assertDoesNotThrow(() -> ItemRules.validateAttachmentTotal(499_999_999L));
        assertDoesNotThrow(() -> ItemRules.validateAttachmentTotal(500_000_000L));
        assertThrows(IllegalArgumentException.class, () -> ItemRules.validateAttachmentTotal(500_000_001L));
    }

    @Test void rejectsInvalidTitleAndNegativeAttachmentTotal() {
        assertThrows(IllegalArgumentException.class, () -> ItemRules.validateTitle(" "));
        assertThrows(IllegalArgumentException.class, () -> ItemRules.validateAttachmentTotal(-1));
    }
}
