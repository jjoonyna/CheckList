package com.checklist.domain.comment.repository;
import com.checklist.domain.comment.entity.CommentEntity;


import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;
public interface CommentRepository extends JpaRepository<CommentEntity,Long>{List<CommentEntity> findByItemIdOrderByImportantDescCreatedAtDescIdDesc(Long itemId);}
