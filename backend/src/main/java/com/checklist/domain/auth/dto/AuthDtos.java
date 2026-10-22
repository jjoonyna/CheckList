package com.checklist.domain.auth.dto;
import com.checklist.domain.auth.entity.UserEntity;


public final class AuthDtos {
 private AuthDtos(){}
 public record User(Long id,String email,String name) { public static User from(UserEntity u){return new User(u.getId(),u.getEmail(),u.getName());} }
 public record RegisterRequest(@jakarta.validation.constraints.Email @jakarta.validation.constraints.NotBlank String email,@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(min=8,max=72) String password,@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max=100) String name){}
 public record LoginRequest(@jakarta.validation.constraints.Email @jakarta.validation.constraints.NotBlank String email,@jakarta.validation.constraints.NotBlank String password){}
 public record AuthResponse(User user,String accessToken){}
}
