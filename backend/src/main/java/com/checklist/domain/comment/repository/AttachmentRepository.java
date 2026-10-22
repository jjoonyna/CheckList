package com.checklist.domain.comment.repository;
import com.checklist.domain.comment.entity.AttachmentEntity;


import org.springframework.data.jpa.repository.JpaRepository;
public interface AttachmentRepository extends JpaRepository<AttachmentEntity,Long>{}
