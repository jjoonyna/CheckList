package com.checklist.domain.comment.dto;
import com.checklist.domain.auth.dto.AuthDtos;
import com.checklist.domain.comment.entity.CommentEntity;


import java.time.Instant;import java.util.*;
public final class CommentDtos {private CommentDtos(){} public record Attachment(Long id,String filename,long size){} public record Comment(Long id,Long itemId,Long parentId,AuthDtos.User author,String body,Instant createdAt,List<Attachment> attachments,boolean important){} public record ImportanceInput(@jakarta.validation.constraints.NotNull Boolean important){} public static Comment from(CommentEntity c){return new Comment(c.getId(),c.getItem().getId(),c.getParent()==null?null:c.getParent().getId(),AuthDtos.User.from(c.getAuthor()),c.getBody(),c.getCreatedAt(),c.getAttachments().stream().map(a->new Attachment(a.id,a.filename,a.size)).toList(),c.isImportant());}}
