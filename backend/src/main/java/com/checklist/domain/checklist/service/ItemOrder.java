package com.checklist.domain.checklist.service;

import com.checklist.domain.checklist.entity.ItemEntity;
import java.util.*;

public final class ItemOrder {
 private ItemOrder() {}
 private static final Comparator<ItemEntity> SIBLING_ORDER=Comparator.comparing(ItemEntity::getPriority)
     .thenComparing(ItemEntity::getDueDate,Comparator.nullsLast(Comparator.naturalOrder()))
     .thenComparing(ItemEntity::getId);
 public static List<ItemEntity> sort(Collection<ItemEntity> items) {return sort(items,Map.of());}
 // 저장된 position이 있는 형제를 먼저 두고, 없는 형제는 자동 정렬로 뒤에 붙인다.
 public static void sortSiblings(List<ItemEntity> siblings,Map<Long,Integer> positions) {
  siblings.sort(Comparator.<ItemEntity,Boolean>comparing(item->!positions.containsKey(item.getId()))
      .thenComparing(item->positions.getOrDefault(item.getId(),0)).thenComparing(SIBLING_ORDER));
 }
 public static List<ItemEntity> sort(Collection<ItemEntity> items,Map<Long,Integer> positions) {
  Map<Long,List<ItemEntity>> children=new HashMap<>();
  for(ItemEntity item:items){Long parent=item.getParent()==null?null:item.getParent().getId();children.computeIfAbsent(parent,key->new ArrayList<>()).add(item);}
  children.values().forEach(siblings->sortSiblings(siblings,positions));
  List<ItemEntity> ordered=new ArrayList<>();append(null,children,ordered);return ordered;
 }
 private static void append(Long parent,Map<Long,List<ItemEntity>> children,List<ItemEntity> ordered) {
  for(ItemEntity child:children.getOrDefault(parent,List.of())){ordered.add(child);append(child.getId(),children,ordered);}
 }
}