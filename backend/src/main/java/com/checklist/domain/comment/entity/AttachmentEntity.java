package com.checklist.domain.comment.entity;



import jakarta.persistence.*;
import java.util.UUID;
@Entity @Table(name="comment_attachment") public class AttachmentEntity {
 @Id @GeneratedValue(strategy=GenerationType.IDENTITY) public Long id;
 @ManyToOne(fetch=FetchType.LAZY,optional=false) @JoinColumn(name="comment_id") public CommentEntity comment;
 @Column(nullable=false,length=255) public String filename;
 @Column(name="storage_key",nullable=false,unique=true) public UUID storageKey;
 @Column(nullable=false) public long size;
 public AttachmentEntity(){}
}
