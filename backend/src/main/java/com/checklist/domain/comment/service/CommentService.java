package com.checklist.domain.comment.service;
import com.checklist.domain.auth.repository.UserRepository;
import com.checklist.domain.checklist.entity.ItemEntity;
import com.checklist.domain.checklist.repository.ItemRepository;
import com.checklist.domain.checklist.service.ItemRules;
import com.checklist.domain.comment.dto.CommentDtos;
import com.checklist.domain.comment.entity.AttachmentEntity;
import com.checklist.domain.comment.entity.CommentEntity;
import com.checklist.domain.comment.repository.AttachmentRepository;
import com.checklist.domain.comment.repository.CommentRepository;
import com.checklist.global.api.ApiException;


import org.springframework.beans.factory.annotation.Value;import org.springframework.stereotype.Service;import org.springframework.transaction.annotation.Transactional;import org.springframework.web.multipart.MultipartFile;
import java.nio.file.*;import java.util.*;

@Service public class CommentService {
 private final CommentRepository comments;private final AttachmentRepository attachments;private final ItemRepository items;private final UserRepository users;private final Path directory;
 public CommentService(CommentRepository c,AttachmentRepository a,ItemRepository i,UserRepository u,@Value("${app.file-directory:./data/attachments}")String dir){comments=c;attachments=a;items=i;users=u;directory=Path.of(dir).toAbsolutePath().normalize();}
 @Transactional(readOnly=true) public List<CommentDtos.Comment> list(long itemId){if(!items.existsById(itemId))throw ApiException.missing();return comments.findByItemIdOrderByImportantDescCreatedAtDescIdDesc(itemId).stream().map(CommentDtos::from).toList();}
 @Transactional public CommentDtos.Comment create(long actor,long itemId,String body,Long parentId,List<MultipartFile> files){return create(actor,itemId,body,parentId,files,false);}
 @Transactional public CommentDtos.Comment create(long actor,long itemId,String body,Long parentId,List<MultipartFile> files,boolean important){ItemEntity item=items.findById(itemId).orElseThrow(ApiException::missing);ItemEntity root=item.depth==1?item:item.root;if(!root.getEditorIds().contains(actor))throw ApiException.forbidden();List<MultipartFile> uploads=files==null?List.of():files;long total=uploads.stream().mapToLong(f->f.getSize()).sum();ItemRules.validateAttachmentTotal(total);String text=body==null?"":body;if(text.length()>10000||(text.isBlank()&&uploads.isEmpty()))throw ApiException.bad("INVALID_COMMENT","댓글은 10000자 이내이며 첨부 없이 비울 수 없습니다.");CommentEntity parent=parentId==null?null:comments.findById(parentId).orElseThrow(ApiException::missing);if(parent!=null&&(!parent.getItem().getId().equals(itemId)||parent.getParent()!=null))throw ApiException.bad("INVALID_REPLY","답글은 같은 항목의 원댓글에만 작성할 수 있습니다.");if(parent!=null&&important)throw ApiException.bad("IMPORTANT_REPLY_UNSUPPORTED","중요 표시는 원댓글에 적용해 주세요. 답글은 원댓글과 함께 이동합니다.");CommentEntity c=new CommentEntity();c.important=important;c.item=item;c.parent=parent;c.author=users.findById(actor).orElseThrow(ApiException::unauthorized);c.body=text;
  List<Path> written=new ArrayList<>();
  if(org.springframework.transaction.support.TransactionSynchronizationManager.isSynchronizationActive())org.springframework.transaction.support.TransactionSynchronizationManager.registerSynchronization(new org.springframework.transaction.support.TransactionSynchronization(){@Override public void afterCompletion(int status){if(status!=STATUS_COMMITTED)cleanup(written);}});
  try{Files.createDirectories(directory);for(MultipartFile f:uploads){String original=Path.of(Optional.ofNullable(f.getOriginalFilename()).orElse("파일").replace('\\','/')).getFileName().toString().replaceAll("[\\p{Cntrl}]","_");if(original.isBlank())original="파일";if(original.length()>255)original=original.substring(original.length()-255);UUID key=UUID.randomUUID();Path target=directory.resolve(key.toString()).normalize();if(!target.getParent().equals(directory))throw new IllegalStateException("저장 경로가 올바르지 않습니다.");written.add(target);f.transferTo(target);AttachmentEntity a=new AttachmentEntity();a.comment=c;a.filename=original;a.storageKey=key;a.size=f.getSize();c.attachments.add(a);}return CommentDtos.from(comments.saveAndFlush(c));}catch(Exception e){for(Path p:written)try{Files.deleteIfExists(p);}catch(Exception ignored){}throw new ApiException(org.springframework.http.HttpStatus.INTERNAL_SERVER_ERROR,"FILE_SAVE_FAILED","파일을 저장하지 못했습니다.");}}
 @Transactional public CommentDtos.Comment importance(long actor,long id,boolean important){
  CommentEntity comment=comments.findById(id).orElseThrow(ApiException::missing);
  ItemEntity item=comment.getItem();ItemEntity root=item.getDepth()==1?item:item.getRoot();
  if(!root.getEditorIds().contains(actor))throw ApiException.forbidden();
  if(comment.getParent()!=null)throw ApiException.bad("IMPORTANT_REPLY_UNSUPPORTED","중요 표시는 원댓글에 적용해 주세요. 답글은 원댓글과 함께 이동합니다.");
  comment.important=important;return CommentDtos.from(comments.saveAndFlush(comment));
 }
 private void cleanup(List<Path> paths){for(Path path:paths)try{Files.deleteIfExists(path);}catch(java.io.IOException error){org.slf4j.LoggerFactory.getLogger(CommentService.class).warn("실패한 첨부 파일 정리가 필요합니다: {}",path.getFileName());}}
 @Transactional(readOnly=true) public Download download(long id){AttachmentEntity a=attachments.findById(id).orElseThrow(ApiException::missing);Path p=directory.resolve(a.storageKey.toString()).normalize();if(!p.getParent().equals(directory)||!Files.isRegularFile(p))throw ApiException.missing();return new Download(a.filename,a.size,p);}
 public record Download(String filename,long size,Path path){}
}
