package com.checklist.domain.security;
import com.checklist.global.security.JwtService;


import com.checklist.global.security.JwtService;
import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

class JwtServiceTest {
 @Test void requiresProductionSecretOfAtLeast32Bytes(){assertThrows(IllegalStateException.class,()->new JwtService("short"));}
 @Test void accessTokenCarriesSessionAndRefreshSecretsAreUnique(){JwtService service=new JwtService("test-only-secret-that-is-longer-than-thirty-two-bytes");String a=service.newRefresh(),b=service.newRefresh();assertNotEquals(a,b);var claims=service.parse(service.issue(7,"session-id")).getPayload();assertEquals("7",claims.getSubject());assertEquals("session-id",claims.get("sid"));}
}
