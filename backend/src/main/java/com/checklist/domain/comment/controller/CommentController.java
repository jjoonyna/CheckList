package com.checklist.domain.comment.controller;
import com.checklist.domain.comment.dto.CommentDtos;
import com.checklist.domain.comment.service.CommentService;
import com.checklist.global.api.ApiException;


import org.springframework.security.core.annotation.AuthenticationPrincipal;import org.springframework.web.bind.annotation.*;import org.springframework.web.multipart.MultipartFile;import java.util.*;
@RestController public class CommentController {
 private final CommentService service;public CommentController(CommentService s){service=s;}
 @GetMapping("/api/items/{id}/comments") public List<CommentDtos.Comment> list(@PathVariable long id){return service.list(id);}
 @PostMapping(value="/api/items/{id}/comments",consumes="multipart/form-data") public CommentDtos.Comment create(@AuthenticationPrincipal Long uid,@PathVariable long id,@RequestParam(required=false)String body,@RequestParam(required=false)Long parentId,@RequestPart(required=false)List<MultipartFile> files,@RequestParam(defaultValue="false")boolean important){return service.create(uid,id,body,parentId,files,important);}
 @PatchMapping("/api/comments/{id}/importance") public CommentDtos.Comment importance(@AuthenticationPrincipal Long uid,@PathVariable long id,@jakarta.validation.Valid @RequestBody CommentDtos.ImportanceInput input){return service.importance(uid,id,input.important());}
 @GetMapping("/api/attachments/{id}/download") public org.springframework.http.ResponseEntity<?> download(@PathVariable long id){var d=service.download(id);try{var resource=new org.springframework.core.io.InputStreamResource(java.nio.file.Files.newInputStream(d.path()));return org.springframework.http.ResponseEntity.ok().contentType(org.springframework.http.MediaType.APPLICATION_OCTET_STREAM).contentLength(d.size()).header("X-Content-Type-Options","nosniff").header("Content-Disposition",org.springframework.http.ContentDisposition.attachment().filename(d.filename(),java.nio.charset.StandardCharsets.UTF_8).build().toString()).body(resource);}catch(java.io.IOException e){throw new com.checklist.global.api.ApiException(org.springframework.http.HttpStatus.INTERNAL_SERVER_ERROR,"FILE_READ_FAILED","첨부 파일을 읽지 못했습니다.");}}
}
