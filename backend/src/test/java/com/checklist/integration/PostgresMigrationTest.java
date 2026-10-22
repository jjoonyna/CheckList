package com.checklist.integration;



import io.zonky.test.db.postgres.embedded.EmbeddedPostgres;
import org.flywaydb.core.Flyway;
import org.junit.jupiter.api.Test;
import org.springframework.jdbc.core.JdbcTemplate;
import static org.junit.jupiter.api.Assertions.*;

class PostgresMigrationTest {
 @Test void migratesMvpSchemaOnRealPostgres18() throws Exception {
  try(EmbeddedPostgres postgres=EmbeddedPostgres.builder().start()){
   var dataSource=postgres.getPostgresDatabase();
   Flyway.configure().dataSource(dataSource).locations("classpath:db/migration").load().migrate();
   JdbcTemplate jdbc=new JdbcTemplate(dataSource);
   assertEquals(6,jdbc.queryForObject("select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE'",Integer.class));
   assertNotNull(jdbc.queryForObject("select data_type from information_schema.columns where table_name='checklist_item' and column_name='version'",String.class));
   assertEquals("uuid",jdbc.queryForObject("select data_type from information_schema.columns where table_name='comment_attachment' and column_name='storage_key'",String.class));
  }
 }
 @Test void existingItemsReceiveNormalPriorityWithoutLosingTheirData() throws Exception {
  try(EmbeddedPostgres postgres=EmbeddedPostgres.builder().start()){
   var dataSource=postgres.getPostgresDatabase();
   Flyway.configure().dataSource(dataSource).locations("classpath:db/migration").target("2").load().migrate();
   JdbcTemplate jdbc=new JdbcTemplate(dataSource);
   Long user=jdbc.queryForObject("insert into app_user(email,password_hash,name) values ('legacy@example.com','fixture','기존 사용자') returning id",Long.class);
   Long item=jdbc.queryForObject("insert into checklist_item(depth,title,description,created_by) values (1,'기존 항목','보존할 상세',?) returning id",Long.class,user);
   Long comment=jdbc.queryForObject("insert into item_comment(item_id,author_id,body) values (?,?,'기존 댓글') returning id",Long.class,item,user);
   Flyway.configure().dataSource(dataSource).locations("classpath:db/migration").load().migrate();
   assertFalse(jdbc.queryForObject("select important from item_comment where id=?",Boolean.class,comment));
   assertEquals("NORMAL",jdbc.queryForObject("select priority from checklist_item where id=?",String.class,item));
   assertEquals("보존할 상세",jdbc.queryForObject("select description from checklist_item where id=?",String.class,item));
   assertThrows(org.springframework.dao.DataIntegrityViolationException.class,()->jdbc.update("update checklist_item set priority='UNKNOWN' where id=?",item));
  }
 }
 @Test void installerCreatesDatabaseWithoutPsqlOrCreatedbUtilities() throws Exception {
  try(EmbeddedPostgres postgres=EmbeddedPostgres.builder().start()){
   var file=java.nio.file.Files.createTempFile("checklist-install-test-",".properties");
   try{
    var properties=new java.util.Properties();properties.setProperty("spring.datasource.url",postgres.getJdbcUrl("postgres","checklist_installer_test"));properties.setProperty("spring.datasource.username","postgres");properties.setProperty("spring.datasource.password","");
    try(var writer=java.nio.file.Files.newBufferedWriter(file,java.nio.charset.StandardCharsets.UTF_8)){properties.store(writer,"설치 검증");}
    com.checklist.global.setup.DatabaseProvisioner.createIfMissing(file);
    com.checklist.global.setup.DatabaseProvisioner.createIfMissing(file);
   }finally{java.nio.file.Files.deleteIfExists(file);}
  }
 }
}