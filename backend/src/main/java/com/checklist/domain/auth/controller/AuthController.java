package com.checklist.domain.auth.controller;
import com.checklist.domain.auth.dto.AuthDtos;
import com.checklist.domain.auth.service.AuthService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/auth")
public class AuthController {
 private final AuthService service;
 public AuthController(AuthService service) { this.service=service; }
 @PostMapping("/register") public ResponseEntity<?> register(@Valid @RequestBody AuthDtos.RegisterRequest request) { return service.register(request); }
 @PostMapping("/login") public ResponseEntity<?> login(@Valid @RequestBody AuthDtos.LoginRequest request) { return service.login(request); }
 @PostMapping("/refresh") public ResponseEntity<?> refresh(HttpServletRequest request) { return service.refresh(request); }
 @PostMapping("/logout") public ResponseEntity<Void> logout(HttpServletRequest request) { return service.logout(request); }
 @GetMapping("/me") public AuthDtos.User me(@AuthenticationPrincipalId Long id) { return service.me(id); }
}
