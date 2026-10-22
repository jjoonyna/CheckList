package com.checklist.global.api;


import org.springframework.http.*;
import org.springframework.web.bind.annotation.*;
import java.util.Map;
@RestControllerAdvice public class ApiAdvice {
 @ExceptionHandler(ApiException.class) ResponseEntity<?> api(ApiException e){return ResponseEntity.status(e.status).body(Map.of("message",e.getMessage(),"code",e.code));}
 @ExceptionHandler(IllegalArgumentException.class) ResponseEntity<?> bad(IllegalArgumentException e){return ResponseEntity.badRequest().body(Map.of("message",e.getMessage(),"code","INVALID_INPUT"));}
 @ExceptionHandler(org.springframework.web.bind.MethodArgumentNotValidException.class) ResponseEntity<?> invalid(org.springframework.web.bind.MethodArgumentNotValidException e){String m="이메일·비밀번호·이름 등 입력값을 확인해 주세요.";return ResponseEntity.badRequest().body(Map.of("message",m,"code","INVALID_INPUT"));}
 @ExceptionHandler(org.springframework.web.bind.MissingServletRequestParameterException.class) ResponseEntity<?> missingParameter(Exception e){return ResponseEntity.badRequest().body(Map.of("message","필수 요청값이 없습니다.","code","INVALID_INPUT"));}
 @ExceptionHandler(org.springframework.http.converter.HttpMessageNotReadableException.class) ResponseEntity<?> unreadable(Exception e){return ResponseEntity.badRequest().body(Map.of("message","요청 형식이나 값이 올바르지 않습니다.","code","INVALID_INPUT"));}
 @ExceptionHandler(org.springframework.web.multipart.MaxUploadSizeExceededException.class) ResponseEntity<?> tooLarge(Exception e){return ResponseEntity.status(413).body(Map.of("message","첨부 요청 크기가 허용 범위를 넘었습니다.","code","ATTACHMENT_TOO_LARGE"));}
 @ExceptionHandler(org.springframework.orm.ObjectOptimisticLockingFailureException.class) ResponseEntity<?> stale(Exception e){return ResponseEntity.status(409).body(Map.of("message","항목이 다른 사용자에 의해 변경되었습니다. 새로고침해 주세요.","code","VERSION_CONFLICT"));}
 @ExceptionHandler(org.springframework.web.method.annotation.MethodArgumentTypeMismatchException.class) ResponseEntity<?> invalidType(Exception e){return ResponseEntity.badRequest().body(Map.of("message","날짜나 요청값의 형식이 올바르지 않습니다.","code","INVALID_INPUT"));}
 @ExceptionHandler(Exception.class) ResponseEntity<?> unknown(Exception e){return ResponseEntity.status(500).body(Map.of("message","요청을 처리하지 못했습니다.","code","INTERNAL_ERROR"));}
}
