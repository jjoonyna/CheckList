package com.checklist.domain.checklist.entity;
import com.checklist.domain.auth.entity.UserEntity;


import jakarta.persistence.*;
import java.time.LocalDate;
import java.util.*;

@Entity @Table(name="checklist_item")
public class ItemEntity {
    @Id @GeneratedValue(strategy=GenerationType.IDENTITY) public Long id;
    @ManyToOne(fetch=FetchType.LAZY) @JoinColumn(name="parent_id") public ItemEntity parent;
    @ManyToOne(fetch=FetchType.LAZY) @JoinColumn(name="root_id") public ItemEntity root;
    public int depth;
    @Column(name="created_date",nullable=false) public LocalDate createdDate=LocalDate.now(java.time.ZoneId.of("Asia/Seoul"));
    @Column(nullable=false, length=200) public String title;
    @Column(nullable=false, length=20000) public String description="";
    @Column(name="due_date") public LocalDate dueDate;
    @ManyToOne(fetch=FetchType.LAZY) @JoinColumn(name="assignee_id") public UserEntity assignee;
    @ManyToOne(fetch=FetchType.LAZY, optional=false) @JoinColumn(name="created_by") public UserEntity createdBy;
    @Enumerated(EnumType.STRING) @Column(nullable=false, length=10) public ItemStatus status=ItemStatus.OPEN;
    @Enumerated(EnumType.STRING) @Column(nullable=false,length=16) public ItemPriority priority=ItemPriority.NORMAL;
    @Version public long version;
    @Column(name="source_url", length=2048) public String sourceUrl;
    @Column(name="github_repository", length=300) public String githubRepository;
    @Column(name="github_issue_number") public Integer githubIssueNumber;
    @ElementCollection @CollectionTable(name="item_editor", joinColumns=@JoinColumn(name="item_id")) @Column(name="user_id")
    public Set<Long> editorIds=new HashSet<>();
    public Long getId() { return id; }
    public ItemEntity getParent() { return parent; }
    public ItemEntity getRoot() { return root; }
    public int getDepth() { return depth; }
    public String getTitle() { return title; }
    public String getDescription() { return description; }
    public LocalDate getDueDate() { return dueDate; }
    public UserEntity getAssignee() { return assignee; }
    public UserEntity getCreatedBy() { return createdBy; }
    public ItemStatus getStatus() { return status; }
    public ItemPriority getPriority() { return priority; }
    public long getVersion() { return version; }
    public String getSourceUrl() { return sourceUrl; }
    public Set<Long> getEditorIds() { return editorIds; }
    public ItemEntity() {}
}
