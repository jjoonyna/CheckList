package com.checklist.domain.checklist.dto;
import com.checklist.domain.checklist.entity.ItemEntity;
import com.checklist.domain.checklist.entity.ItemStatus;
import com.checklist.domain.checklist.entity.ItemPriority;


import java.time.LocalDate;
import java.util.*;
public final class ItemDtos {
 private ItemDtos(){}
 public record Input(String title,String description,LocalDate dueDate,Long assigneeId,Long parentId,List<Long> editorIds,Long version,ItemPriority priority){
  public Input(String title,String description,LocalDate dueDate,Long assigneeId,Long parentId,List<Long> editorIds,Long version){this(title,description,dueDate,assigneeId,parentId,editorIds,version,null);}
 }
 public record StatusInput(ItemStatus status,Long version){}
 public record Item(Long id,Long parentId,Long rootId,int depth,String title,String description,LocalDate dueDate,Long assigneeId,List<Long> editorIds,Long createdBy,ItemStatus status,long version,boolean editable,boolean matchesFilter,String sourceUrl,ItemPriority priority){}
 public static Item from(ItemEntity item,long viewer,boolean match){
  ItemEntity root=item.getDepth()==1?item:item.getRoot();
  return new Item(item.getId(),item.getParent()==null?null:item.getParent().getId(),root.getId(),item.getDepth(),item.getTitle(),item.getDescription(),item.getDueDate(),item.getAssignee()==null?null:item.getAssignee().getId(),root.getEditorIds().stream().sorted().toList(),item.getCreatedBy().getId(),item.getStatus(),item.getVersion(),root.getEditorIds().contains(viewer),match,item.getSourceUrl(),item.getPriority());
 }
}