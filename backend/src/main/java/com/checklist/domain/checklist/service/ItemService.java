package com.checklist.domain.checklist.service;
import com.checklist.domain.auth.entity.UserEntity;
import com.checklist.domain.auth.repository.UserRepository;
import com.checklist.domain.checklist.dto.ItemDtos;
import com.checklist.domain.checklist.entity.ItemEntity;
import com.checklist.domain.checklist.entity.ItemStatus;
import com.checklist.domain.checklist.repository.ItemRepository;
import com.checklist.global.api.ApiException;


import com.querydsl.jpa.impl.JPAQueryFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.*;
import java.util.*;
import static com.checklist.domain.checklist.entity.QItemEntity.itemEntity;

@Service public class ItemService {
 @jakarta.persistence.PersistenceContext private jakarta.persistence.EntityManager entityManager;
 private final ItemRepository items;private final UserRepository users;private final JPAQueryFactory query;
 public ItemService(ItemRepository i,UserRepository u,JPAQueryFactory q){items=i;users=u;query=q;}
 private UserEntity user(long id){return users.findById(id).orElseThrow(ApiException::unauthorized);}
 public boolean existsByGithubRepositoryAndGithubIssueNumber(String repository,Integer number){return items.existsByGithubRepositoryAndGithubIssueNumber(repository,number);}
 @Transactional(readOnly=true)
 public List<ItemDtos.Item> list(long viewer,String scope,String status,String period,String q,LocalDate from,LocalDate to) {
  if(!Set.of("all","mine").contains(scope)||!Set.of("all","open","done").contains(status))throw ApiException.bad("INVALID_FILTER","필터 값이 올바르지 않습니다.");
  var range=ItemPeriod.resolve(period,from,to,LocalDate.now(ZoneId.of("Asia/Seoul")));
  var effectiveDate=itemEntity.dueDate.coalesce(itemEntity.createdDate);
  var where=effectiveDate.goe(range.start()).and(effectiveDate.lt(range.endExclusive()));
  if("mine".equals(scope))where=where.and(itemEntity.assignee.id.eq(viewer));
  if("open".equals(status))where=where.and(itemEntity.status.eq(ItemStatus.OPEN));
  if("done".equals(status))where=where.and(itemEntity.status.eq(ItemStatus.DONE));
  if(q!=null&&!q.isBlank())where=where.and(itemEntity.title.containsIgnoreCase(q).or(itemEntity.description.containsIgnoreCase(q)));
  List<ItemEntity> matches=query.selectFrom(itemEntity).where(where).orderBy(itemEntity.id.asc()).fetch();
  Set<Long> matchIds=new HashSet<>();Map<Long,ItemEntity> rows=new LinkedHashMap<>();
  for(ItemEntity match:matches){matchIds.add(match.getId());ItemEntity current=match;while(current!=null){rows.put(current.getId(),current);current=current.getParent();}}
  return ItemOrder.sort(rows.values()).stream().map(item->ItemDtos.from(item,viewer,matchIds.contains(item.getId()))).toList();
 }
 @Transactional public ItemDtos.Item create(long actor,ItemDtos.Input in){validate(in);ItemEntity parent=in.parentId()==null?null:items.findById(in.parentId()).orElseThrow(ApiException::missing);ItemEntity root=parent==null?null:(parent.getDepth()==1?parent:parent.getRoot());if(root!=null)lockRoot(root);if(parent!=null&&!root.getEditorIds().contains(actor))throw ApiException.forbidden();int depth=parent==null?1:ItemRules.depthForParentDepth(parent.getDepth());ItemEntity x=new ItemEntity();x.parent=parent;x.depth=depth;x.root=root;x.title=in.title().trim();x.description=Optional.ofNullable(in.description()).orElse("");x.dueDate=in.dueDate();x.priority=in.priority()==null?com.checklist.domain.checklist.entity.ItemPriority.NORMAL:in.priority();x.assignee=in.assigneeId()==null?null:user(in.assigneeId());x.createdBy=user(actor);if(parent==null){x.root=x;x.editorIds.add(actor);if(in.editorIds()!=null)for(Long id:in.editorIds())x.editorIds.add(user(id).getId());}if(x.assignee!=null&&!(root==null?x.editorIds:root.getEditorIds()).contains(x.assignee.getId()))throw ApiException.bad("ASSIGNEE_NOT_EDITOR","담당자는 최상위 편집자 중에서 선택해 주세요.");x=items.saveAndFlush(x);if(x.root==x){x.root=x;items.save(x);}return ItemDtos.from(x,actor,true);}
 @Transactional public ItemDtos.Item update(long actor,long id,ItemDtos.Input in) {
  validate(in);
  ItemEntity x=items.findById(id).orElseThrow(ApiException::missing);
  ItemEntity root=x.getDepth()==1?x:x.getRoot();
  lockRoot(root);
  if(!root.getEditorIds().contains(actor))throw ApiException.forbidden();
  if(in.version()==null||in.version()!=x.version)throw new ApiException(org.springframework.http.HttpStatus.CONFLICT,"VERSION_CONFLICT","항목이 변경되었습니다. 새로고침해 주세요.");
  if(in.parentId()!=null&&!Objects.equals(in.parentId(),x.getParent()==null?null:x.getParent().getId()))throw ApiException.bad("MOVE_UNSUPPORTED","항목 이동은 지원하지 않습니다.");
  Set<Long> nextEditors=new HashSet<>(root.getEditorIds());
  if(x.getDepth()==1&&in.editorIds()!=null) {
   Set<Long> requested=new HashSet<>(in.editorIds());
   requested.add(x.getCreatedBy().getId());
   if(x.getCreatedBy().getId()!=actor&&!requested.equals(nextEditors))throw ApiException.forbidden();
   if(x.getCreatedBy().getId()==actor) {
    nextEditors.clear();
    for(Long editorId:requested)nextEditors.add(user(editorId).getId());
   }
  }
  UserEntity assignee=in.assigneeId()==null?null:user(in.assigneeId());
  if(assignee!=null&&!nextEditors.contains(assignee.getId()))throw ApiException.bad("ASSIGNEE_NOT_EDITOR","담당자는 최상위 편집자 중에서 선택해 주세요.");
  Set<Long> removedEditors=new HashSet<>(root.getEditorIds());
  removedEditors.removeAll(nextEditors);
  if(!removedEditors.isEmpty()&&query.selectOne().from(itemEntity)
      .where(itemEntity.root.id.eq(root.getId()),itemEntity.id.ne(root.getId()),itemEntity.assignee.id.in(removedEditors))
      .fetchFirst()!=null)throw ApiException.bad("EDITOR_STILL_ASSIGNED","하위 항목에 담당자로 지정된 계정은 편집자에서 제외할 수 없습니다. 담당자를 먼저 변경해 주세요.");
  x.title=in.title().trim();x.description=Optional.ofNullable(in.description()).orElse("");x.dueDate=in.dueDate();x.assignee=assignee;if(in.priority()!=null)x.priority=in.priority();
  if(x.getDepth()==1&&!nextEditors.equals(root.getEditorIds())) {x.editorIds.clear();x.editorIds.addAll(nextEditors);}
  return ItemDtos.from(items.saveAndFlush(x),actor,true);
 }
 @Transactional public ItemDtos.Item status(long actor,long id,ItemDtos.StatusInput in){if(in==null||in.status()==null||in.version()==null)throw ApiException.bad("INVALID_INPUT","상태와 version이 필요합니다.");ItemEntity x=items.findById(id).orElseThrow(ApiException::missing);ItemEntity root=x.depth==1?x:x.root;if(!root.getEditorIds().contains(actor))throw ApiException.forbidden();if(in.version()!=x.version)throw new ApiException(org.springframework.http.HttpStatus.CONFLICT,"VERSION_CONFLICT","항목이 변경되었습니다. 새로고침해 주세요.");x.status=in.status();return ItemDtos.from(items.saveAndFlush(x),actor,true);}
 // 담당자 배정과 편집자 제외가 동시에 실행돼도 같은 트리의 권한·배정 관계를 유지한다.
 private void lockRoot(ItemEntity root){entityManager.lock(root,jakarta.persistence.LockModeType.PESSIMISTIC_WRITE);}
 private void validate(ItemDtos.Input i){if(i==null)throw ApiException.bad("INVALID_INPUT","요청 내용이 필요합니다.");ItemRules.validateTitle(i.title());if(i.description()!=null&&i.description().length()>20000)throw ApiException.bad("INVALID_INPUT","상세내용은 20000자 이하여야 합니다.");}
 @Transactional public ItemDtos.Item importIssue(long actor,String repository,int number,String title,String body,String url,Long parentId){if(items.existsByGithubRepositoryAndGithubIssueNumber(repository,number))return null;ItemDtos.Item dto=create(actor,new ItemDtos.Input(title,body,null,actor,parentId,null,null));ItemEntity entity=items.findById(dto.id()).orElseThrow();entity.sourceUrl=url;entity.githubRepository=repository;entity.githubIssueNumber=number;return ItemDtos.from(items.saveAndFlush(entity),actor,true);}
}
