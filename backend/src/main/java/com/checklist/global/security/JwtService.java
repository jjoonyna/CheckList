package com.checklist.global.security;


import io.jsonwebtoken.*;
import io.jsonwebtoken.security.Keys;
import javax.crypto.SecretKey;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.*;
public class JwtService {
 private final SecretKey key;
 public JwtService(String secret){if(secret==null||secret.getBytes(StandardCharsets.UTF_8).length<32)throw new IllegalStateException("JWT_SECRET은 32바이트 이상이어야 합니다.");key=Keys.hmacShaKeyFor(secret.getBytes(StandardCharsets.UTF_8));}
 public String issue(long userId,String session){return Jwts.builder().subject(Long.toString(userId)).claim("sid",session).issuedAt(Date.from(Instant.now())).expiration(Date.from(Instant.now().plusSeconds(900))).signWith(key).compact();}
 public Jws<Claims> parse(String token){return Jwts.parser().verifyWith(key).build().parseSignedClaims(token);}
 public String newRefresh(){byte[] b=new byte[48];new java.security.SecureRandom().nextBytes(b);return Base64.getUrlEncoder().withoutPadding().encodeToString(b);}
 public String hash(String token){try{return HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256").digest(token.getBytes(StandardCharsets.UTF_8)));}catch(Exception e){throw new IllegalStateException(e);}}
}
