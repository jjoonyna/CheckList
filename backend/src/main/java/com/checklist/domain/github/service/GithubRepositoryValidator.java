package com.checklist.domain.github.service;



import java.util.regex.Pattern;

public final class GithubRepositoryValidator {
    private static final Pattern REPOSITORY = Pattern.compile("[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+");
    private GithubRepositoryValidator() {}
    public static String validate(String value) {
        if (value == null || !REPOSITORY.matcher(value).matches() || value.contains("..")) {
            throw new IllegalArgumentException("GitHub 저장소는 owner/repo 형식이어야 합니다.");
        }
        return value;
    }
}
