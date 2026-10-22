package com.checklist.domain.github.controller;
import com.checklist.domain.github.dto.GithubDtos.*;
import com.checklist.domain.github.service.GithubService;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.web.bind.annotation.*;
@RestController
@RequestMapping("/api/github")
public class GithubController {
 private final GithubService service;
 public GithubController(GithubService service) { this.service=service; }
 @PostMapping("/issues") public Page issues(@AuthenticationPrincipal Long actor,@RequestBody Request request) { return service.issues(actor,request); }
 @PostMapping("/import") public Imported importIssues(@AuthenticationPrincipal Long actor,@RequestBody ImportRequest request) { return service.importIssues(actor,request); }
}
