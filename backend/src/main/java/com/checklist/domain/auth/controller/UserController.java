package com.checklist.domain.auth.controller;
import com.checklist.domain.auth.dto.AuthDtos;
import com.checklist.domain.auth.repository.UserRepository;
import com.checklist.global.api.ApiException;


import org.springframework.web.bind.annotation.*;
import java.util.*;
@RestController @RequestMapping("/api/users") public class UserController {
 private final UserRepository users;public UserController(UserRepository users){this.users=users;}
 @GetMapping public List<AuthDtos.User> list(){return users.findAll().stream().map(AuthDtos.User::from).toList();}
}
