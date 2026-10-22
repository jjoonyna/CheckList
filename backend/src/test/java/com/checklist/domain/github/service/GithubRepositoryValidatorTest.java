package com.checklist.domain.github.service;



import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class GithubRepositoryValidatorTest {
    @Test void acceptsOwnerAndRepoOnly() {
        assertEquals("owner/repo", GithubRepositoryValidator.validate("owner/repo"));
    }

    @Test void rejectsUrlsAndHostOverridesToPreventSsrF() {
        assertThrows(IllegalArgumentException.class, () -> GithubRepositoryValidator.validate("http://127.0.0.1/owner/repo"));
        assertThrows(IllegalArgumentException.class, () -> GithubRepositoryValidator.validate("evil.com/owner/repo"));
        assertThrows(IllegalArgumentException.class, () -> GithubRepositoryValidator.validate("owner/repo?host=localhost"));
    }
}
