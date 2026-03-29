package com.hydros.ssodemo.service;

import com.hydros.ssodemo.config.DemoSsoProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import org.springframework.boot.json.JsonParserFactory;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.util.LinkedMultiValueMap;
import org.springframework.util.MultiValueMap;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriComponentsBuilder;

import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.RSAPublicKeySpec;
import java.util.Base64;
import java.util.Collection;
import java.util.Map;

@Service
public class DemoOidcService {

    private final DemoSsoProperties properties;
    private final RestClient restClient;

    public DemoOidcService(DemoSsoProperties properties) {
        this.properties = properties;
        this.restClient = RestClient.builder().build();
    }

    public String buildAuthorizeUrl(String state, String nonce) {
        return buildAuthorizeUrl(state, nonce, properties.getRedirectUri());
    }

    public String buildAuthorizeUrl(String state, String nonce, String redirectUri) {
        return UriComponentsBuilder.fromUriString(properties.getIssuer() + "/oauth2/authorize")
                .queryParam("response_type", "code")
                .queryParam("client_id", properties.getClientId())
                .queryParam("redirect_uri", redirectUri)
                .queryParam("scope", properties.getScope())
                .queryParam("state", state)
                .queryParam("nonce", nonce)
                .build()
                .encode()
                .toUriString();
    }

    public Map<String, Object> exchangeAuthorizationCode(String code) {
        return exchangeAuthorizationCode(code, properties.getRedirectUri());
    }

    public Map<String, Object> exchangeAuthorizationCode(String code, String redirectUri) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "authorization_code");
        form.add("code", code);
        form.add("redirect_uri", redirectUri);

        return postTokenForm(form);
    }

    public Map<String, Object> refreshByToken(String refreshToken) {
        MultiValueMap<String, String> form = new LinkedMultiValueMap<>();
        form.add("grant_type", "refresh_token");
        form.add("refresh_token", refreshToken);
        return postTokenForm(form);
    }

    public Map<String, Object> verifyIdToken(String idToken, String expectedNonce) {
        try {
            RSAPublicKey publicKey = resolvePublicKeyByKid(idToken);
            Claims claims = Jwts.parser()
                    .verifyWith(publicKey)
                    .build()
                    .parseSignedClaims(idToken)
                    .getPayload();

            if (!properties.getIssuer().equals(claims.getIssuer())) {
                throw new IllegalStateException("ID Token issuer mismatch");
            }
            if (!audienceContains(claims.get("aud"), properties.getClientId())) {
                throw new IllegalStateException("ID Token audience mismatch");
            }
            if (expectedNonce != null && !expectedNonce.isBlank()) {
                String nonce = claims.get("nonce", String.class);
                if (!expectedNonce.equals(nonce)) {
                    throw new IllegalStateException("ID Token nonce mismatch");
                }
            }
            return claims;
        } catch (Exception ex) {
            throw new IllegalStateException("Failed to verify ID token: " + ex.getMessage(), ex);
        }
    }

    private Map<String, Object> postTokenForm(MultiValueMap<String, String> form) {
        String basic = Base64.getEncoder()
                .encodeToString((properties.getClientId() + ":" + properties.getClientSecret()).getBytes(StandardCharsets.UTF_8));
        return restClient.post()
                .uri(properties.getIssuer() + "/oauth2/token")
                .contentType(MediaType.APPLICATION_FORM_URLENCODED)
                .header(HttpHeaders.AUTHORIZATION, "Basic " + basic)
                .body(form)
                .retrieve()
                .body(new ParameterizedTypeReference<>() {
                });
    }

    private RSAPublicKey resolvePublicKeyByKid(String jwt) throws Exception {
        String[] segments = jwt.split("\\.");
        if (segments.length < 2) {
            throw new IllegalArgumentException("Invalid JWT format");
        }
        String headerJson = new String(Base64.getUrlDecoder().decode(segments[0]), StandardCharsets.UTF_8);
        Map<String, Object> header = JsonParserFactory.getJsonParser().parseMap(headerJson);
        String kid = (String) header.get("kid");

        Map<String, Object> jwks = restClient.get()
                .uri(properties.getIssuer() + "/oauth2/jwks")
                .retrieve()
                .body(new ParameterizedTypeReference<>() {
                });

        Object rawKeys = jwks.get("keys");
        if (!(rawKeys instanceof Collection<?> keys) || keys.isEmpty()) {
            throw new IllegalStateException("JWKS does not contain keys");
        }

        Map<String, Object> key = null;
        for (Object item : keys) {
            if (item instanceof Map<?, ?> candidate) {
                String itemKid = String.valueOf(candidate.get("kid"));
                if (kid == null || kid.equals(itemKid)) {
                    key = (Map<String, Object>) candidate;
                    break;
                }
            }
        }
        if (key == null) {
            throw new IllegalStateException("No matching key id found in JWKS");
        }

        String n = String.valueOf(key.get("n"));
        String e = String.valueOf(key.get("e"));
        BigInteger modulus = new BigInteger(1, Base64.getUrlDecoder().decode(n));
        BigInteger exponent = new BigInteger(1, Base64.getUrlDecoder().decode(e));

        RSAPublicKeySpec keySpec = new RSAPublicKeySpec(modulus, exponent);
        KeyFactory factory = KeyFactory.getInstance("RSA");
        return (RSAPublicKey) factory.generatePublic(keySpec);
    }

    private boolean audienceContains(Object audClaim, String expectedClientId) {
        if (audClaim == null) {
            return false;
        }
        if (audClaim instanceof String audString) {
            return expectedClientId.equals(audString);
        }
        if (audClaim instanceof Collection<?> collection) {
            return collection.stream().map(String::valueOf).anyMatch(expectedClientId::equals);
        }
        return false;
    }
}

