package com.checklist.domain.comment.service;
import com.checklist.domain.auth.entity.UserEntity;
import com.checklist.domain.auth.repository.UserRepository;
import com.checklist.domain.checklist.entity.ItemEntity;
import com.checklist.domain.checklist.repository.ItemRepository;
import com.checklist.domain.comment.entity.CommentEntity;
import com.checklist.domain.comment.repository.*;
import com.checklist.global.api.ApiException;
import java.nio.file.*;
import java.util.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.web.multipart.MultipartFile;
import org.springframework.transaction.support.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;
class CommentStorageTest {
 @TempDir Path directory;
 CommentRepository comments;CommentService service;
 @BeforeEach void setup(){
  comments=mock(CommentRepository.class);var items=mock(ItemRepository.class);var users=mock(UserRepository.class);
  var root=new ItemEntity();root.id=1L;root.depth=1;root.editorIds.add(7L);root.root=root;
  var user=new UserEntity("test@example.com","hash","작성자");user.id=7L;
  when(items.findById(1L)).thenReturn(Optional.of(root));when(users.findById(7L)).thenReturn(Optional.of(user));
  when(comments.saveAndFlush(any(CommentEntity.class))).thenAnswer(call->{CommentEntity comment=call.getArgument(0);comment.id=1L;return comment;});
  service=new CommentService(comments,mock(AttachmentRepository.class),items,users,directory.toString());
 }
 MultipartFile file(boolean fail) throws Exception {
  MultipartFile file=mock(MultipartFile.class);when(file.getSize()).thenReturn(3L);when(file.getOriginalFilename()).thenReturn("자료.txt");
  doAnswer(call->{Files.write(call.getArgument(0,Path.class),new byte[]{1,2,3});if(fail)throw new java.io.IOException("전송 중단");return null;}).when(file).transferTo(any(Path.class));return file;
 }
 long count() throws Exception {try(var files=Files.list(directory)){return files.count();}}
 @Test void removesPartiallyWrittenFileWhenTransferFails() throws Exception {
  assertThrows(ApiException.class,()->service.create(7L,1L,"본문",null,List.of(file(true))));assertEquals(0,count());
 }
 @Test void removesFilesIfDatabaseTransactionRollsBackAfterFlush() throws Exception {
  TransactionSynchronizationManager.initSynchronization();
  try {service.create(7L,1L,"본문",null,List.of(file(false)));assertEquals(1,count());
   TransactionSynchronizationManager.getSynchronizations().forEach(callback->callback.afterCompletion(TransactionSynchronization.STATUS_ROLLED_BACK));assertEquals(0,count());
  } finally {TransactionSynchronizationManager.clearSynchronization();}
 }
 @Test void rejectsAggregateOversizeBeforeWriting() throws Exception {
  var first=mock(MultipartFile.class);var second=mock(MultipartFile.class);when(first.getSize()).thenReturn(300_000_000L);when(second.getSize()).thenReturn(300_000_000L);
  assertThrows(IllegalArgumentException.class,()->service.create(7L,1L,"본문",null,List.of(first,second)));assertEquals(0,count());verifyNoInteractions(comments);
 }
}