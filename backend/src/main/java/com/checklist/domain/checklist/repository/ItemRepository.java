package com.checklist.domain.checklist.repository;
import com.checklist.domain.checklist.entity.ItemEntity;


import org.springframework.data.jpa.repository.JpaRepository;
import java.util.*;
public interface ItemRepository extends JpaRepository<ItemEntity,Long> {
    List<ItemEntity> findAllByOrderByIdAsc();
    boolean existsByGithubRepositoryAndGithubIssueNumber(String repository, Integer number);
    java.util.Optional<ItemEntity> findByGithubRepositoryAndGithubIssueNumber(String repository, Integer number);
}
