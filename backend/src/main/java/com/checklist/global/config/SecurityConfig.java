package com.checklist.global.config;
import com.checklist.domain.auth.repository.UserRepository;
import com.checklist.global.api.ApiException;
import com.checklist.global.security.JwtService;


import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.*;
import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.MediaType;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.web.filter.OncePerRequestFilter;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.web.cors.*;
import java.time.Duration;
import java.util.*;
import jakarta.servlet.*;
import jakarta.servlet.http.*;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;

@Configuration public class SecurityConfig {
 @Bean PasswordEncoder passwordEncoder(){return new BCryptPasswordEncoder();}
 @Bean JwtService jwtService(@Value("${app.jwt-secret:}") String secret){return new JwtService(secret);}
 @Bean SecurityFilterChain security(HttpSecurity http,StringRedisTemplate redis,JwtService jwt,UserRepository users,ObjectMapper mapper) throws Exception {
  http.csrf(c->c.disable()).cors(c->c.configurationSource(cors())).sessionManagement(s->s.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
   .exceptionHandling(e->e.authenticationEntryPoint((req,res,ex)->write(res,mapper,401,"UNAUTHORIZED","로그인이 필요합니다.")))
   .authorizeHttpRequests(a->a.requestMatchers("/api/health","/api/auth/register","/api/auth/login","/api/auth/refresh","/api/auth/logout").permitAll().requestMatchers("/api/**").authenticated().anyRequest().permitAll())
   .addFilterBefore(new AccessFilter(redis,jwt,users,mapper),UsernamePasswordAuthenticationFilter.class);
  return http.build();
 }
 private CorsConfigurationSource cors(){CorsConfiguration c=new CorsConfiguration();c.setAllowedOriginPatterns(List.of("http://localhost:*","http://127.0.0.1:*"));c.setAllowedMethods(List.of("GET","POST","PATCH","OPTIONS"));c.setAllowedHeaders(List.of("Authorization","Content-Type","X-Requested-With"));c.setAllowCredentials(true);UrlBasedCorsConfigurationSource s=new UrlBasedCorsConfigurationSource();s.registerCorsConfiguration("/**",c);return s;}
 static void write(HttpServletResponse r,ObjectMapper m,int status,String code,String message)throws java.io.IOException{r.setStatus(status);r.setContentType(MediaType.APPLICATION_JSON_VALUE);m.writeValue(r.getOutputStream(),Map.of("code",code,"message",message));}
 static class AccessFilter extends OncePerRequestFilter {
  final StringRedisTemplate redis;final JwtService jwt;final UserRepository users;final ObjectMapper mapper;
  AccessFilter(StringRedisTemplate r,JwtService j,UserRepository u,ObjectMapper m){redis=r;jwt=j;users=u;mapper=m;}
  @Override protected boolean shouldNotFilter(HttpServletRequest request) {return Set.of("/api/health","/api/auth/register","/api/auth/login","/api/auth/refresh","/api/auth/logout").contains(request.getServletPath());}
  protected void doFilterInternal(HttpServletRequest req,HttpServletResponse res,FilterChain chain)throws ServletException,java.io.IOException{
   String h=req.getHeader("Authorization");if(h==null||!h.startsWith("Bearer ")){chain.doFilter(req,res);return;}
   try{var claims=jwt.parse(h.substring(7)).getPayload();String uid=claims.getSubject(),sid=claims.get("sid",String.class);String stored=redis.opsForValue().get("checklist:session:"+sid);
    if(stored==null||!stored.equals(uid)){write(res,mapper,401,"UNAUTHORIZED","세션이 만료되었습니다.");return;}
    var user=users.findById(Long.valueOf(uid)).orElseThrow();SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(user.id,null,List.of()));
   }catch(org.springframework.dao.DataAccessException e){write(res,mapper,503,"AUTH_UNAVAILABLE","인증 서비스를 사용할 수 없습니다.");return;}
    catch(Exception e){write(res,mapper,401,"UNAUTHORIZED","인증 정보가 올바르지 않습니다.");return;}
   chain.doFilter(req,res);
  }
 }
}
