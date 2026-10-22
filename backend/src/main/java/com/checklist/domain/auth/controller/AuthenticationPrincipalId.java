package com.checklist.domain.auth.controller;



import java.lang.annotation.*;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
@Target(ElementType.PARAMETER) @Retention(RetentionPolicy.RUNTIME) @AuthenticationPrincipal public @interface AuthenticationPrincipalId {}
