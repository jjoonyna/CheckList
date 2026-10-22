package com.checklist.domain.auth.service;
import com.checklist.domain.auth.dto.AuthDtos;
import com.checklist.domain.auth.entity.UserEntity;
import com.checklist.domain.auth.repository.UserRepository;
import com.checklist.global.api.ApiException;
import com.checklist.global.security.JwtService;


import jakarta.servlet.http.*;
import jakarta.validation.Valid;
import jakarta.validation.constraints.*;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.*;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.bind.annotation.*;
import java.time.Duration;
import java.util.*;
import java.nio.charset.StandardCharsets;

@org.springframework.stereotype.Service public class AuthService {
 private static final String COOKIE="checklist_refresh";
 private final UserRepository users;private final PasswordEncoder passwords;private final JwtService jwt;private final StringRedisTemplate redis;private final boolean secure;
 public AuthService(UserRepository u,PasswordEncoder p,JwtService j,StringRedisTemplate r,@Value("${app.secure-cookie:false}")boolean s){users=u;passwords=p;jwt=j;redis=r;secure=s;}
 @org.springframework.transaction.annotation.Transactional public ResponseEntity<?> register(AuthDtos.RegisterRequest r){validatePasswordBytes(r.password());String email=r.email().trim().toLowerCase(Locale.ROOT);if(users.findByEmailIgnoreCase(email).isPresent())throw ApiException.bad("EMAIL_EXISTS","이미 사용 중인 이메일입니다.");UserEntity u=users.save(new UserEntity(email,passwords.encode(r.password()),r.name().trim()));return issue(u,null);}
 public ResponseEntity<?> login(AuthDtos.LoginRequest r){validatePasswordBytes(r.password());UserEntity u=users.findByEmailIgnoreCase(r.email().trim()).orElseThrow(ApiException::unauthorized);if(!passwords.matches(r.password(),u.passwordHash))throw ApiException.unauthorized();return issue(u,null);}
 private static final org.springframework.data.redis.core.script.DefaultRedisScript<Long> CREATE_SESSION = new org.springframework.data.redis.core.script.DefaultRedisScript<>("redis.call('set',KEYS[1],ARGV[1],'EX',ARGV[3]); redis.call('set',KEYS[2],ARGV[2],'EX',ARGV[3]); return 1",Long.class);
 private static final org.springframework.data.redis.core.script.DefaultRedisScript<String> ROTATE_SESSION = new org.springframework.data.redis.core.script.DefaultRedisScript<>("local uid=redis.call('get',KEYS[1]); local old=redis.call('get',KEYS[2]); if not uid or old~=ARGV[1] then return nil end; redis.call('set',KEYS[1],uid,'EX',ARGV[3]); redis.call('set',KEYS[2],ARGV[2],'EX',ARGV[3]); return uid",String.class);
 private List<String> keys(String sid){return List.of("checklist:session:"+sid,"checklist:refresh:"+sid);}
 private ResponseEntity<?> issue(UserEntity user,String ignored){
  String sid=UUID.randomUUID().toString(),refresh=jwt.newRefresh();
  try{redis.execute(CREATE_SESSION,keys(sid),user.getId().toString(),jwt.hash(refresh),"604800");return response(user,sid,refresh);}
  catch(org.springframework.dao.DataAccessException e){throw unavailable();}
 }
 private ResponseEntity<?> response(UserEntity user,String sid,String refresh){return ResponseEntity.ok().header(HttpHeaders.SET_COOKIE,cookie(sid+"."+refresh,Duration.ofDays(7)).toString()).body(new AuthDtos.AuthResponse(AuthDtos.User.from(user),jwt.issue(user.getId(),sid)));}
 private ApiException unavailable(){return new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"AUTH_UNAVAILABLE","인증 서비스를 사용할 수 없습니다.");}
 public ResponseEntity<?> refresh(HttpServletRequest request){
  requireAjax(request);String raw=cookieValue(request);
  if(raw==null||!raw.contains("."))throw ApiException.unauthorized();
  String[] parts=raw.split("\\.",2);String next=jwt.newRefresh();
  try{String uid=redis.execute(ROTATE_SESSION,keys(parts[0]),jwt.hash(parts[1]),jwt.hash(next),"604800");
   if(uid==null)throw ApiException.unauthorized();
   return response(users.findById(Long.valueOf(uid)).orElseThrow(ApiException::unauthorized),parts[0],next);
  }catch(org.springframework.dao.DataAccessException e){throw unavailable();}
 }
 public ResponseEntity<Void> logout(HttpServletRequest req){requireAjax(req);String raw=cookieValue(req);if(raw!=null&&raw.contains(".")){String sid=raw.substring(0,raw.indexOf('.'));try{redis.delete(List.of("checklist:session:"+sid,"checklist:refresh:"+sid));}catch(org.springframework.dao.DataAccessException e){throw new ApiException(HttpStatus.SERVICE_UNAVAILABLE,"AUTH_UNAVAILABLE","인증 서비스를 사용할 수 없습니다.");}}return ResponseEntity.noContent().header(HttpHeaders.SET_COOKIE,cookie("",Duration.ZERO).toString()).build();}
 public AuthDtos.User me(Long id){return AuthDtos.User.from(users.findById(id).orElseThrow(ApiException::unauthorized));}
 private void requireAjax(HttpServletRequest req){if(!"XMLHttpRequest".equals(req.getHeader("X-Requested-With")))throw ApiException.bad("REQUEST_HEADER_REQUIRED","X-Requested-With 헤더가 필요합니다.");}
 private void validatePasswordBytes(String value){int bytes=value.getBytes(StandardCharsets.UTF_8).length;if(bytes<8||bytes>72)throw ApiException.bad("INVALID_PASSWORD","비밀번호는 UTF-8 기준 8~72바이트여야 합니다.");}
 private String cookieValue(HttpServletRequest req){if(req.getCookies()==null)return null;for(Cookie c:req.getCookies())if(COOKIE.equals(c.getName()))return c.getValue();return null;}
 private ResponseCookie cookie(String value,Duration age){return ResponseCookie.from(COOKIE,value).httpOnly(true).secure(secure).sameSite("Strict").path("/api/auth").maxAge(age).build();}
}
