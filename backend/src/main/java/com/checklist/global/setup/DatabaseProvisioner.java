package com.checklist.global.setup;
import java.io.Reader;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.nio.file.*;
import java.sql.*;
import java.util.Properties;
public final class DatabaseProvisioner {
 private DatabaseProvisioner(){}
 public static void createIfMissing(Path configuration) throws Exception {
  Properties properties=new Properties();try(Reader reader=Files.newBufferedReader(configuration,StandardCharsets.UTF_8)){properties.load(reader);}
  String url=properties.getProperty("spring.datasource.url","");
  if(!url.startsWith("jdbc:postgresql://"))throw new IllegalArgumentException("PostgreSQL 접속 주소가 필요합니다.");
  URI uri=URI.create(url.substring(5));String database=uri.getPath().substring(1);
  if(uri.getUserInfo()!=null||!database.matches("[A-Za-z_][A-Za-z0-9_]{0,62}"))throw new IllegalArgumentException("데이터베이스 이름은 영문·숫자·밑줄로 입력해 주세요.");
  String user=properties.getProperty("spring.datasource.username"),password=properties.getProperty("spring.datasource.password");
  String adminUrl="jdbc:postgresql://"+uri.getRawAuthority()+"/postgres";
  try(Connection connection=DriverManager.getConnection(adminUrl,user,password)){
   boolean exists;try(PreparedStatement query=connection.prepareStatement("SELECT 1 FROM pg_database WHERE datname=?")){query.setString(1,database);try(ResultSet row=query.executeQuery()){exists=row.next();}}
   if(!exists)try(Statement command=connection.createStatement()){command.execute("CREATE DATABASE \""+database+"\" ENCODING 'UTF8'");}
  }
  try(Connection connection=DriverManager.getConnection(url,user,password)){if(!connection.isValid(5))throw new SQLException("DB 접속 확인 실패");}
  System.out.println("PostgreSQL 데이터베이스 준비 완료");
 }
}