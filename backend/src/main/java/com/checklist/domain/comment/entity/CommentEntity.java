package com.checklist.domain.comment.entity;
import com.checklist.domain.auth.entity.UserEntity;
import com.checklist.domain.checklist.entity.ItemEntity;


import jakarta.persistence.*;
import java.time.Instant;
import java.util.*;
@Entity @Table(name="item_comment") public class CommentEntity {
 @Id @GeneratedValue(strategy=GenerationType.IDENTITY) public Long id;
 @ManyToOne(fetch=FetchType.LAZY,optional=false) @JoinColumn(name="item_id") public ItemEntity item;
 @ManyToOne(fetch=FetchType.LAZY) @JoinColumn(name="parent_id") public CommentEntity parent;
 @ManyToOne(fetch=FetchType.LAZY,optional=false) @JoinColumn(name="author_id") public UserEntity author;
 @Column(nullable=false,length=10000) public String body;
 @Column(nullable=false) public boolean important=false;
 @Column(name="created_at",nullable=false) public Instant createdAt=Instant.now();
 @OneToMany(mappedBy="comment",cascade=CascadeType.ALL,orphanRemoval=true) public List<AttachmentEntity> attachments=new ArrayList<>();
 public Long getId(){return id;}
 public ItemEntity getItem(){return item;}
 public CommentEntity getParent(){return parent;}
 public UserEntity getAuthor(){return author;}
 public boolean isImportant(){return important;}
 public String getBody(){return body;}
 public Instant getCreatedAt(){return createdAt;}
 public List<AttachmentEntity> getAttachments(){return attachments;}
 public CommentEntity(){}
}
