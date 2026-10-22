package com.checklist.integration;



import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import jakarta.servlet.http.Cookie;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.DynamicPropertyRegistry;
import org.springframework.test.context.DynamicPropertySource;
import org.springframework.test.web.servlet.*;
import java.time.*;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc
class MvpApiTest {
    static EmbeddedPostgres postgres;
    static TestRedis redis;
    @DynamicPropertySource static void properties(DynamicPropertyRegistry r) throws Exception {
        redis=TestRedis.start();
        postgres = EmbeddedPostgres.builder().setPGStartupWait(Duration.ofSeconds(45)).start();
        r.add("spring.datasource.url", () -> postgres.getJdbcUrl("postgres", "postgres"));
        r.add("spring.datasource.username", () -> "postgres");
        r.add("spring.datasource.password", () -> "");
        r.add("spring.data.redis.host", () -> "127.0.0.1");
        r.add("spring.data.redis.port", () -> redis.port);
        r.add("app.jwt-secret", () -> "integration-only-" + UUID.randomUUID() + UUID.randomUUID());
        r.add("app.file-directory", () -> System.getProperty("java.io.tmpdir") + "/checklist-api-test-" + UUID.randomUUID());
    }
    @Autowired MockMvc http;
    @Autowired ObjectMapper json;
    @Autowired com.checklist.domain.checklist.service.ItemService itemService;
    @Autowired org.springframework.transaction.PlatformTransactionManager transactionManager;
    @Autowired org.springframework.jdbc.core.JdbcTemplate jdbc;
    @jakarta.persistence.PersistenceContext jakarta.persistence.EntityManager entityManager;
    record Session(long id, String token, Cookie refresh) {}
    @AfterAll static void close() throws Exception { if(postgres != null) postgres.close(); if(redis != null) redis.close(); }
    Session signup(String label) throws Exception {
        MvcResult response=http.perform(post("/api/auth/register").contentType("application/json").content(json.writeValueAsString(Map.of("email",label+UUID.randomUUID()+"@example.com","password","safe-password-123","name",label))))
            .andExpect(status().isOk()).andReturn();
        JsonNode body=json.readTree(response.getResponse().getContentAsString());
        Cookie cookie=response.getResponse().getCookie("checklist_refresh");
        assertNotNull(cookie); assertTrue(cookie.isHttpOnly()); assertEquals("Strict",cookie.getAttribute("SameSite"));
        return new Session(body.path("user").path("id").asLong(),body.path("accessToken").asText(),cookie);
    }
    JsonNode create(Session actor,Long parent,List<Long> editors,Long assignee,String title) throws Exception {
        Map<String,Object> input=new HashMap<>(); input.put("title",title);input.put("description","상세 설명");input.put("dueDate",LocalDate.now(ZoneId.of("Asia/Seoul")).toString());input.put("parentId",parent);input.put("editorIds",editors);input.put("assigneeId",assignee);
        return json.readTree(http.perform(post("/api/items").header("Authorization","Bearer "+actor.token()).contentType("application/json").content(json.writeValueAsString(input))).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
    }
    @Test void rootPermissionControlsAllThreeLevelsAndRevocationIsImmediate() throws Exception {
        Session owner=signup("생성자"), editor=signup("편집자"), viewer=signup("열람자");
        JsonNode root=create(owner,null,List.of(editor.id()),owner.id(),"최상위");
        JsonNode child=create(editor,root.path("id").asLong(),null,editor.id(),"중간");
        JsonNode leaf=create(editor,child.path("id").asLong(),null,owner.id(),"최하위");
        assertEquals(1,root.path("depth").asInt()); assertEquals(2,child.path("depth").asInt());assertEquals(3,leaf.path("depth").asInt());
        long leafId=leaf.path("id").asLong();
        http.perform(post("/api/items").header("Authorization","Bearer "+editor.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title","4단계","parentId",leafId)))).andExpect(status().isBadRequest());
        http.perform(get("/api/items").header("Authorization","Bearer "+viewer.token())).andExpect(status().isOk());
        http.perform(get("/api/items")).andExpect(status().isUnauthorized());
        http.perform(patch("/api/items/"+leafId+"/status").header("Authorization","Bearer "+viewer.token()).contentType("application/json").content("{\"status\":\"DONE\",\"version\":0}")).andExpect(status().isForbidden());
        http.perform(patch("/api/items/"+leafId+"/status").header("Authorization","Bearer "+editor.token()).contentType("application/json").content("{\"status\":\"DONE\",\"version\":0}")).andExpect(status().isOk()).andExpect(jsonPath("$.version").value(1));
        http.perform(patch("/api/items/"+leafId+"/status").header("Authorization","Bearer "+editor.token()).contentType("application/json").content("{\"status\":\"OPEN\",\"version\":0}")).andExpect(status().isConflict());
        // 담당자를 먼저 인계한 다음 편집 권한을 제외한다.
        http.perform(patch("/api/items/"+child.path("id").asLong()).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title","담당 인계","assigneeId",owner.id(),"version",child.path("version").asLong())))).andExpect(status().isOk());
        http.perform(patch("/api/items/"+root.path("id").asLong()).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title","최상위 수정","description","권한 갱신","assigneeId",owner.id(),"editorIds",List.of(owner.id()),"version",root.path("version").asLong())))).andExpect(status().isOk());
        http.perform(patch("/api/items/"+leafId+"/status").header("Authorization","Bearer "+editor.token()).contentType("application/json").content("{\"status\":\"OPEN\",\"version\":1}")).andExpect(status().isForbidden());
        http.perform(multipart("/api/items/"+leafId+"/comments").param("body","차단 확인").header("Authorization","Bearer "+editor.token())).andExpect(status().isForbidden());
        http.perform(get("/api/items").param("scope","mine").header("Authorization","Bearer "+owner.token())).andExpect(status().isOk());
    }
    @org.junit.jupiter.params.ParameterizedTest
    @org.junit.jupiter.params.provider.ValueSource(ints={2,3})
    void assignedDescendantMustBeReassignedBeforeRemovingEditor(int depth) throws Exception {
        Session owner=signup("인계생성자"), editor=signup("제외담당자");
        JsonNode root=create(owner,null,List.of(editor.id()),owner.id(),"인계 전 최상위");
        long parent=root.path("id").asLong();
        if(depth==3)parent=create(owner,parent,null,owner.id(),"중간 항목").path("id").asLong();
        String title="검사 대상 "+UUID.randomUUID();
        JsonNode assigned=create(owner,parent,null,editor.id(),title);
        long target=assigned.path("id").asLong();
        JsonNode dated=json.readTree(http.perform(patch("/api/items/"+target).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title",title,"dueDate","2000-01-01","assigneeId",editor.id(),"version",assigned.path("version").asLong())))).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        JsonNode done=json.readTree(http.perform(patch("/api/items/"+target+"/status").header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("status","DONE","version",dated.path("version").asLong())))).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        String remove=json.writeValueAsString(Map.of("title","실패 시 저장되면 안 됨","assigneeId",owner.id(),"editorIds",List.of(owner.id()),"version",root.path("version").asLong()));
        http.perform(patch("/api/items/"+root.path("id").asLong()).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(remove)).andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("EDITOR_STILL_ASSIGNED"));
        JsonNode rows=json.readTree(http.perform(get("/api/items").param("period","custom").param("from","2000-01-01").param("to","2000-12-31").param("q",title).header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        JsonNode storedRoot=null,storedTarget=null;
        for(JsonNode row:rows){if(row.path("id").asLong()==root.path("id").asLong())storedRoot=row;if(row.path("id").asLong()==target)storedTarget=row;}
        assertNotNull(storedRoot);assertEquals("인계 전 최상위",storedRoot.path("title").asText());assertEquals(root.path("version").asLong(),storedRoot.path("version").asLong());
        assertNotNull(storedTarget);assertEquals(editor.id(),storedTarget.path("assigneeId").asLong());
        assertTrue(storedTarget.path("editable").asBoolean());
        http.perform(patch("/api/items/"+target).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title",title,"assigneeId",owner.id(),"version",done.path("version").asLong())))).andExpect(status().isOk());
        http.perform(patch("/api/items/"+root.path("id").asLong()).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(remove)).andExpect(status().isOk());
        http.perform(patch("/api/items/"+target+"/status").header("Authorization","Bearer "+editor.token()).contentType("application/json").content(json.writeValueAsString(Map.of("status","OPEN","version",done.path("version").asLong()+1)))).andExpect(status().isForbidden());
    }
    @Test void assignmentsInAnotherTreeDoNotPreventEditorRemoval() throws Exception {
        Session owner=signup("범위생성자"), editor=signup("다른트리담당자");
        JsonNode root=create(owner,null,List.of(editor.id()),editor.id(),"제외 대상 트리");
        JsonNode other=create(owner,null,List.of(editor.id()),owner.id(),"다른 트리");
        create(owner,other.path("id").asLong(),null,editor.id(),"다른 트리 담당");
        http.perform(patch("/api/items/"+root.path("id").asLong()).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title","최상위 담당도 함께 인계","assigneeId",owner.id(),"editorIds",List.of(owner.id()),"version",root.path("version").asLong())))).andExpect(status().isOk()).andExpect(jsonPath("$.assigneeId").value(owner.id()));
    }
    @Test void concurrentChildAssignmentIsVisibleBeforeRemovingEditor() throws Exception {
        Session owner=signup("동시인계생성자"), editor=signup("동시배정담당자");
        JsonNode root=create(owner,null,List.of(editor.id()),owner.id(),"동시 변경 트리");
        long rootId=root.path("id").asLong();
        var attempt=new java.util.concurrent.atomic.AtomicReference<java.util.concurrent.Future<MvcResult>>();
        try(var executor=java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor()){
            new org.springframework.transaction.support.TransactionTemplate(transactionManager).executeWithoutResult(transaction->{
                var locked=entityManager.find(com.checklist.domain.checklist.entity.ItemEntity.class,rootId);
                entityManager.lock(locked,jakarta.persistence.LockModeType.PESSIMISTIC_WRITE);
                itemService.create(owner.id(),new com.checklist.domain.checklist.dto.ItemDtos.Input("동시에 배정되는 항목","",null,editor.id(),rootId,null,null));
                attempt.set(executor.submit(()->http.perform(patch("/api/items/"+rootId).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title","권한 제외 시도","assigneeId",owner.id(),"editorIds",List.of(owner.id()),"version",root.path("version").asLong())))).andReturn()));
                long deadline=System.nanoTime()+Duration.ofSeconds(8).toNanos();boolean waiting=false;
                while(System.nanoTime()<deadline){
                    jdbc.execute("select pg_stat_clear_snapshot()");
                    Integer count=jdbc.queryForObject("select count(*) from pg_stat_activity where wait_event_type='Lock' and query like '%checklist_item%' and pid <> pg_backend_pid()",Integer.class);
                    if(count!=null&&count>0){waiting=true;break;}
                    try{Thread.sleep(20);}catch(InterruptedException interrupted){Thread.currentThread().interrupt();throw new IllegalStateException(interrupted);}
                }
                assertTrue(waiting,"권한 제외 요청이 먼저 진행 중인 배정 트랜잭션을 기다려야 합니다.");
            });
            MvcResult response=attempt.get().get(10,java.util.concurrent.TimeUnit.SECONDS);
            assertEquals(400,response.getResponse().getStatus());
            assertEquals("EDITOR_STILL_ASSIGNED",json.readTree(response.getResponse().getContentAsString()).path("code").asText());
        }
    }
    @Test void prioritiesCanBeCreatedChangedAndReadAtAllThreeLevels() throws Exception {
        Session owner=signup("우선순위생성자");
        JsonNode root=create(owner,null,null,owner.id(),"우선순위 기본값");
        assertEquals("NORMAL",root.path("priority").asText());
        long parent=root.path("id").asLong();
        for(String priority:List.of("URGENT","HIGH","NORMAL","LOW","CONSIDER")){
            http.perform(post("/api/items").header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title","우선순위 "+priority,"priority",priority)))).andExpect(status().isOk()).andExpect(jsonPath("$.priority").value(priority));
        }
        List<JsonNode> levels=new ArrayList<>();levels.add(root);
        for(int depth=2;depth<=3;depth++){JsonNode child=create(owner,parent,null,owner.id(),"우선순위 단계 "+depth);levels.add(child);parent=child.path("id").asLong();}
        for(JsonNode row:levels){
            long id=row.path("id").asLong();
            JsonNode updated=json.readTree(http.perform(patch("/api/items/"+id).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title","긴급 변경 "+id,"priority","URGENT","version",row.path("version").asLong())))).andExpect(status().isOk()).andExpect(jsonPath("$.priority").value("URGENT")).andReturn().getResponse().getContentAsString());
            http.perform(patch("/api/items/"+id).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title","기존 요청 유지 "+id,"version",updated.path("version").asLong())))).andExpect(status().isOk()).andExpect(jsonPath("$.priority").value("URGENT"));
        }
        http.perform(post("/api/items").header("Authorization","Bearer "+owner.token()).contentType("application/json").content("{\"title\":\"잘못된 우선순위\",\"priority\":\"UNKNOWN\"}")).andExpect(status().isBadRequest());
    }
    @Test void commentsAndRepliesAreNewestFirstWithStableIdTieBreaking() throws Exception {
        Session owner=signup("댓글정렬자");JsonNode root=create(owner,null,null,owner.id(),"댓글 최신순");long id=root.path("id").asLong();
        JsonNode first=json.readTree(http.perform(multipart("/api/items/"+id+"/comments").param("body","먼저 등록").header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        JsonNode second=json.readTree(http.perform(multipart("/api/items/"+id+"/comments").param("body","나중 등록").header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        JsonNode reply=json.readTree(http.perform(multipart("/api/items/"+id+"/comments").param("body","답글").param("parentId",first.path("id").asText()).header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        jdbc.update("update item_comment set created_at='2026-01-02T00:00:00Z' where id in (?,?)",first.path("id").asLong(),reply.path("id").asLong());
        jdbc.update("update item_comment set created_at='2026-01-01T00:00:00Z' where id=?",second.path("id").asLong());
        JsonNode rows=json.readTree(http.perform(get("/api/items/"+id+"/comments").header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        assertEquals(List.of(reply.path("id").asLong(),first.path("id").asLong(),second.path("id").asLong()),java.util.stream.StreamSupport.stream(rows.spliterator(),false).map(row->row.path("id").asLong()).toList());
        assertEquals(first.path("id").asLong(),rows.get(0).path("parentId").asLong());
    }
    JsonNode ranked(Session actor,Long parent,String title,String priority,LocalDate due) throws Exception {
        Map<String,Object> input=new HashMap<>();input.put("title",title);input.put("priority",priority);input.put("parentId",parent);input.put("dueDate",due==null?null:due.toString());
        return json.readTree(http.perform(post("/api/items").header("Authorization","Bearer "+actor.token()).contentType("application/json").content(json.writeValueAsString(input))).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
    }
    @Test void ordersSiblingsByPriorityThenDeadlineWhileKeepingEveryHierarchyLevel() throws Exception {
        Session owner=signup("계층정렬자");String prefix="정렬 "+UUID.randomUUID()+" ";LocalDate today=LocalDate.now(ZoneId.of("Asia/Seoul"));
        JsonNode low=ranked(owner,null,prefix+"낮은 최상위","LOW",today.minusDays(10));
        JsonNode noDue=ranked(owner,null,prefix+"긴급 미지정","URGENT",null);
        JsonNode high=ranked(owner,null,prefix+"높음 임박","HIGH",today.plusDays(1));
        JsonNode late=ranked(owner,null,prefix+"긴급 나중","URGENT",today.plusDays(10));
        JsonNode overdue=ranked(owner,null,prefix+"긴급 지남","URGENT",today.minusDays(2));
        JsonNode soon=ranked(owner,null,prefix+"긴급 임박","URGENT",today.plusDays(1));
        JsonNode tie=ranked(owner,null,prefix+"긴급 같은날","URGENT",today.plusDays(1));
        JsonNode normal=ranked(owner,null,prefix+"보통","NORMAL",null);
        JsonNode consider=ranked(owner,null,prefix+"고려 오래지남","CONSIDER",today.minusDays(20));
        long rootId=low.path("id").asLong();
        JsonNode childNormal=ranked(owner,rootId,prefix+"보통 자식","NORMAL",today.minusDays(20));
        JsonNode childNoDue=ranked(owner,rootId,prefix+"긴급 자식 미지정","URGENT",null);
        JsonNode childSoon=ranked(owner,rootId,prefix+"긴급 자식 임박","URGENT",today.plusDays(1));
        JsonNode childOld=ranked(owner,rootId,prefix+"긴급 자식 지남","URGENT",today.minusDays(2));
        JsonNode leafLow=ranked(owner,childNormal.path("id").asLong(),prefix+"낮은 최하위","LOW",today.minusDays(20));
        JsonNode leafHigh=ranked(owner,childNormal.path("id").asLong(),prefix+"높은 최하위","HIGH",today.plusDays(1));
        JsonNode rows=json.readTree(http.perform(get("/api/items").param("q",prefix).param("period","custom").param("from",today.minusDays(30).toString()).param("to",today.plusDays(30).toString()).header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        assertEquals(java.util.stream.Stream.of(overdue,soon,tie,late,noDue,high,normal,low,childOld,childSoon,childNoDue,childNormal,leafHigh,leafLow,consider).map(row->row.path("id").asLong()).toList(),java.util.stream.StreamSupport.stream(rows.spliterator(),false).map(row->row.path("id").asLong()).toList());
        JsonNode context=json.readTree(http.perform(get("/api/items").param("q",leafHigh.path("title").asText()).param("period","custom").param("from",today.minusDays(30).toString()).param("to",today.plusDays(30).toString()).header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        assertEquals(List.of(low.path("id").asLong(),childNormal.path("id").asLong(),leafHigh.path("id").asLong()),java.util.stream.StreamSupport.stream(context.spliterator(),false).map(row->row.path("id").asLong()).toList());
        assertFalse(context.get(0).path("matchesFilter").asBoolean());assertFalse(context.get(1).path("matchesFilter").asBoolean());assertTrue(context.get(2).path("matchesFilter").asBoolean());
    }
    @Test void importantOriginalCommentsAreFirstAndNewestWithinEachGroup() throws Exception {
        Session owner=signup("중요정렬자");JsonNode root=create(owner,null,null,owner.id(),"중요 댓글 정렬");long id=root.path("id").asLong();
        List<Long> ids=new ArrayList<>();
        for(int i=0;i<4;i++){
            JsonNode comment=json.readTree(http.perform(multipart("/api/items/"+id+"/comments").param("body","정렬 댓글 "+i).param("important",String.valueOf(i<2)).header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andExpect(jsonPath("$.important").value(i<2)).andReturn().getResponse().getContentAsString());
            ids.add(comment.path("id").asLong());jdbc.update("update item_comment set created_at=?::timestamptz where id=?","2026-01-0"+(i+1)+"T00:00:00Z",ids.get(i));
        }
        JsonNode reply=json.readTree(http.perform(multipart("/api/items/"+id+"/comments").param("body","중요 원댓글의 답글").param("parentId",ids.get(0).toString()).header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        JsonNode rows=json.readTree(http.perform(get("/api/items/"+id+"/comments").header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        assertEquals(List.of(ids.get(1),ids.get(0),reply.path("id").asLong(),ids.get(3),ids.get(2)),java.util.stream.StreamSupport.stream(rows.spliterator(),false).map(row->row.path("id").asLong()).toList());
        assertEquals(ids.get(0).longValue(),rows.get(2).path("parentId").asLong());
    }
    @Test void importanceUsesTreeEditorsAtEveryDepthAndNeverPinsRepliesSeparately() throws Exception {
        Session owner=signup("중요작성자"),editor=signup("중요편집자"),viewer=signup("중요열람자");
        JsonNode root=create(owner,null,List.of(editor.id()),owner.id(),"중요 권한");
        List<JsonNode> levels=new ArrayList<>();levels.add(root);long parent=root.path("id").asLong();
        for(int depth=2;depth<=3;depth++){JsonNode next=create(owner,parent,null,owner.id(),"중요 단계 "+depth);levels.add(next);parent=next.path("id").asLong();}
        for(JsonNode item:levels){
            long itemId=item.path("id").asLong();
            JsonNode comment=json.readTree(http.perform(multipart("/api/items/"+itemId+"/comments").param("body","중요 전환").header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
            long commentId=comment.path("id").asLong();
            JsonNode before=json.readTree(http.perform(get("/api/items/"+itemId+"/comments").header("Authorization","Bearer "+viewer.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString()).get(0);
            http.perform(patch("/api/comments/"+commentId+"/importance").header("Authorization","Bearer "+viewer.token()).contentType("application/json").content("{\"important\":true}")).andExpect(status().isForbidden());
            http.perform(patch("/api/comments/"+commentId+"/importance").header("Authorization","Bearer "+editor.token()).contentType("application/json").content("{\"important\":true}")).andExpect(status().isOk()).andExpect(jsonPath("$.important").value(true)).andExpect(jsonPath("$.author.id").value(owner.id())).andExpect(jsonPath("$.createdAt").value(before.path("createdAt").asText()));
            http.perform(patch("/api/comments/"+commentId+"/importance").header("Authorization","Bearer "+owner.token()).contentType("application/json").content("{\"important\":false}")).andExpect(status().isOk()).andExpect(jsonPath("$.important").value(false));
            http.perform(patch("/api/comments/"+commentId+"/importance").header("Authorization","Bearer "+owner.token()).contentType("application/json").content("{}")).andExpect(status().isBadRequest());
            JsonNode reply=json.readTree(http.perform(multipart("/api/items/"+itemId+"/comments").param("body","그대로 붙는 답글").param("parentId",String.valueOf(commentId)).header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
            http.perform(patch("/api/comments/"+reply.path("id").asLong()+"/importance").header("Authorization","Bearer "+owner.token()).contentType("application/json").content("{\"important\":true}")).andExpect(status().isBadRequest());
            http.perform(multipart("/api/items/"+itemId+"/comments").param("body","별도 고정 불가").param("parentId",String.valueOf(commentId)).param("important","true").header("Authorization","Bearer "+owner.token())).andExpect(status().isBadRequest());
        }
    }
    @Test void rootCanAddEditorAndAssignThemInTheSameUpdate() throws Exception {
        Session owner=signup("권한추가자"), editor=signup("신규담당자");
        JsonNode root=create(owner,null,null,owner.id(),"권한 추가");
        http.perform(patch("/api/items/"+root.path("id").asLong()).header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title","동시 권한 추가와 담당 지정","assigneeId",editor.id(),"editorIds",List.of(owner.id(),editor.id()),"version",root.path("version").asLong())))).andExpect(status().isOk()).andExpect(jsonPath("$.assigneeId").value(editor.id()));
    }
    @Test void editorCannotChangeRootEditors() throws Exception {
        Session owner=signup("권한소유자"), editor=signup("일반편집자"), other=signup("추가대상");
        JsonNode root=create(owner,null,List.of(editor.id()),owner.id(),"권한 보호");
        http.perform(patch("/api/items/"+root.path("id").asLong()).header("Authorization","Bearer "+editor.token()).contentType("application/json").content(json.writeValueAsString(Map.of("title","권한 변경 시도","editorIds",List.of(owner.id(),editor.id(),other.id()),"version",root.path("version").asLong())))).andExpect(status().isForbidden());
    }
    @Test void importedIssueReturnsTheVersionNeededForImmediateEditing() throws Exception {
        Session owner=signup("가져오기버전");
        var imported=itemService.importIssue(owner.id(),"test/version-"+UUID.randomUUID(),7,"가져온 업무","본문","https://github.com/test/example/issues/7",null);
        http.perform(patch("/api/items/"+imported.id()+"/status").header("Authorization","Bearer "+owner.token()).contentType("application/json").content(json.writeValueAsString(Map.of("status","DONE","version",imported.version())))).andExpect(status().isOk());
    }
    @Test void githubImportRejectsAnEmptySelectionBeforeCallingGithub() throws Exception {
        Session owner=signup("빈선택");
        http.perform(post("/api/github/import").header("Authorization","Bearer "+owner.token()).contentType("application/json").content("{\"repository\":\"test/example\",\"issueNumbers\":[]}")).andExpect(status().isBadRequest()).andExpect(jsonPath("$.code").value("INVALID_SELECTION"));
    }
    @Test void commentsRepliesAndFilesRemainReadableByOtherAccounts() throws Exception {
        Session owner=signup("파일작성자"), viewer=signup("파일열람자");
        JsonNode root=create(owner,null,null,owner.id(),"댓글 업무"); long id=root.path("id").asLong();
        byte[] data="첨부 파일 내용".getBytes(java.nio.charset.StandardCharsets.UTF_8);
        JsonNode comment=json.readTree(http.perform(multipart("/api/items/"+id+"/comments").file(new MockMultipartFile("files","../자료.txt","text/plain",data)).param("body","확인 부탁드립니다").header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        long fileId=comment.path("attachments").get(0).path("id").asLong();
        http.perform(get("/api/attachments/"+fileId+"/download").header("Authorization","Bearer "+viewer.token())).andExpect(status().isOk()).andExpect(header().string("X-Content-Type-Options","nosniff")).andExpect(content().bytes(data));
        http.perform(get("/api/attachments/"+fileId+"/download")).andExpect(status().isUnauthorized());
        JsonNode reply=json.readTree(http.perform(multipart("/api/items/"+id+"/comments").param("body","답글").param("parentId",comment.path("id").asText()).header("Authorization","Bearer "+owner.token())).andExpect(status().isOk()).andReturn().getResponse().getContentAsString());
        http.perform(multipart("/api/items/"+id+"/comments").param("body","답글의 답글").param("parentId",reply.path("id").asText()).header("Authorization","Bearer "+owner.token())).andExpect(status().isBadRequest());
        JsonNode other=create(owner,null,null,null,"다른 업무");
        http.perform(multipart("/api/items/"+other.path("id").asLong()+"/comments").param("body","다른 항목의 댓글").param("parentId",comment.path("id").asText()).header("Authorization","Bearer "+owner.token())).andExpect(status().isBadRequest());
    }
    @RepeatedTest(3) void concurrentRefreshConsumesTheOldTokenOnlyOnce() throws Exception {
        Session owner=signup("동시갱신");
        try(var executor=java.util.concurrent.Executors.newVirtualThreadPerTaskExecutor()){
            var start=new java.util.concurrent.CountDownLatch(1);
            java.util.concurrent.Callable<Integer> request=()->{start.await();return http.perform(post("/api/auth/refresh").cookie(owner.refresh()).header("X-Requested-With","XMLHttpRequest")).andReturn().getResponse().getStatus();};
            var first=executor.submit(request);var second=executor.submit(request);start.countDown();
            var statuses=new ArrayList<>(List.of(first.get(),second.get()));Collections.sort(statuses);
            assertEquals(List.of(200,401),statuses);
        }
    }
    @Test void refreshRotatesAndLogoutImmediatelyRevokesAccess() throws Exception {
        Session owner=signup("인증검증");
        http.perform(post("/api/auth/refresh").cookie(owner.refresh())).andExpect(status().isBadRequest());
        MvcResult rotated=http.perform(post("/api/auth/refresh").cookie(owner.refresh()).header("X-Requested-With","XMLHttpRequest")).andExpect(status().isOk()).andReturn();
        http.perform(post("/api/auth/refresh").cookie(owner.refresh()).header("X-Requested-With","XMLHttpRequest")).andExpect(status().isUnauthorized());
        Cookie fresh=rotated.getResponse().getCookie("checklist_refresh");
        http.perform(post("/api/auth/logout").cookie(fresh).header("X-Requested-With","XMLHttpRequest")).andExpect(status().isNoContent());
        http.perform(get("/api/auth/me").header("Authorization","Bearer "+owner.token())).andExpect(status().isUnauthorized());
    }
}