package com.hydros.ssodemo.service;

import com.hydros.ssodemo.config.DemoSsoProperties;
import io.jsonwebtoken.Claims;
import io.jsonwebtoken.Jwts;
import org.springframework.boot.json.JsonParserFactory;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.core.io.Resource;
import org.springframework.core.io.ResourceLoader;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.client.RestClient;
import org.springframework.web.util.UriComponentsBuilder;

import java.io.IOException;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.AlgorithmParameters;
import java.security.GeneralSecurityException;
import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.Signature;
import java.security.interfaces.ECPrivateKey;
import java.security.interfaces.ECPublicKey;
import java.security.interfaces.RSAPrivateKey;
import java.security.spec.ECGenParameterSpec;
import java.security.spec.ECParameterSpec;
import java.security.spec.ECPoint;
import java.security.spec.ECPublicKeySpec;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Base64;
import java.util.Collection;
import java.util.Map;

/**
 * Demo OIDC 服务。
 */
@Service
public class DemoOidcService {

    private static final String EC_CURVE_P256 = "P-256";

    private final DemoSsoProperties properties;
    private final RestClient restClient;
    private final PrivateKey clientPrivateKey;
    private final ECParameterSpec p256Parameters;

    /**
     * 构造 OIDC 服务。
     *
     * @param properties Demo SSO 配置
     * @param resourceLoader 资源加载器
     */
    public DemoOidcService(DemoSsoProperties properties, ResourceLoader resourceLoader) {
        this.properties = properties;
        this.restClient = RestClient.builder().build();
        this.clientPrivateKey = loadPrivateKey(resourceLoader, properties.getClientPrivateKeyPath());
        this.p256Parameters = loadP256Parameters();
    }

    /**
     * 构建授权地址。
     *
     * @param state 状态参数
     * @param nonce 随机串
     * @return 授权地址
     */
    public String buildAuthorizeUrl(String state, String nonce) {
        return buildAuthorizeUrl(state, nonce, properties.getRedirectUri());
    }

    /**
     * 构建授权地址。
     *
     * @param state 状态参数
     * @param nonce 随机串
     * @param redirectUri 回调地址
     * @return 授权地址
     */
    public String buildAuthorizeUrl(String state, String nonce, String redirectUri) {
        return UriComponentsBuilder.fromUriString(properties.getIssuer() + "/sso/api/oauth2/authorize")
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

    /**
     * 构建 SSO 统一登出入口地址。
     *
     * @return SSO 登出入口地址
     */
    public String buildSsoLogoutUrl() {
        return buildSsoLogoutUrl(null);
    }

    /**
     * 构建 SSO 统一登出入口地址。
     *
     * @param postLogoutRedirectUri 登出后回跳地址
     * @return SSO 登出入口地址
     */
    public String buildSsoLogoutUrl(String postLogoutRedirectUri) {
        UriComponentsBuilder builder = UriComponentsBuilder.fromUriString(properties.getIssuer())
                .path("/sso/api/logout")
                .queryParam("client_id", properties.getClientId());
        if (postLogoutRedirectUri != null && !postLogoutRedirectUri.isBlank()) {
            builder.queryParam("post_logout_redirect_uri", postLogoutRedirectUri);
        }
        return builder
                .build()
                .encode()
                .toUriString();
    }

    /**
     * 构建 SSO 统一登出入口地址。
     *
     * @param clientId 客户端 ID
     * @param postLogoutRedirectUri 登出后回跳地址
     * @return SSO 登出入口地址
     */
    public String buildSsoLogoutUrl(String clientId, String postLogoutRedirectUri) {
        UriComponentsBuilder builder = UriComponentsBuilder.fromUriString(properties.getIssuer())
                .path("/sso/api/logout");
        if (clientId != null && !clientId.isBlank()) {
            builder.queryParam("client_id", clientId);
        }
        if (postLogoutRedirectUri != null && !postLogoutRedirectUri.isBlank()) {
            builder.queryParam("post_logout_redirect_uri", postLogoutRedirectUri);
        }
        return builder
                .build()
                .encode()
                .toUriString();
    }

    /**
     * 使用授权码换取令牌。
     *
     * @param code 授权码
     * @return 令牌响应
     */
    public Map<String, Object> exchangeAuthorizationCode(String code) {
        return exchangeAuthorizationCode(code, properties.getRedirectUri());
    }

    /**
     * 使用授权码换取令牌。
     * 此处保留 redirectUri 参数仅为兼容调用方，当前协议不再使用该参数。
     *
     * @param code 授权码
     * @param redirectUri 回调地址（兼容参数，当前不会发送）
     * @return 令牌响应
     */
    public Map<String, Object> exchangeAuthorizationCode(String code, String redirectUri) {
        Map<String, Object> requestBody = Map.of(
                "clientId", properties.getClientId(),
                "code", code,
                "codeSignature", signCode(code)
        );
        Map<String, Object> response = restClient.post()
                .uri(properties.getIssuer() + "/sso/api/oauth2/token")
                .contentType(MediaType.APPLICATION_JSON)
                .body(requestBody)
                .retrieve()
                .body(new ParameterizedTypeReference<>() {
                });
        return unwrapTokenData(response);
    }

    /**
     * 使用刷新令牌换取新令牌。
     *
     * @param refreshToken 刷新令牌
     * @return 令牌响应
     */
    public Map<String, Object> refreshByToken(String refreshToken) {
        Map<String, Object> requestBody = Map.of(
                "clientId", properties.getClientId(),
                "refreshToken", refreshToken
        );
        Map<String, Object> response = restClient.post()
                .uri(properties.getIssuer() + "/sso/api/oauth2/refresh_token")
                .contentType(MediaType.APPLICATION_JSON)
                .body(requestBody)
                .retrieve()
                .body(new ParameterizedTypeReference<>() {
                });
        return unwrapTokenData(response);
    }

    /**
     * 验证 ID Token。
     *
     * @param idToken ID Token
     * @param expectedNonce 期望 nonce
     * @return Claims
     */
    public Map<String, Object> verifyIdToken(String idToken, String expectedNonce) {
        try {
            ECPublicKey publicKey = resolvePublicKeyByKid(idToken);
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

    /**
     * 对授权码进行签名。
     *
     * @param code 授权码
     * @return Base64URL 编码后的签名值
     */
    private String signCode(String code) {
        try {
            Signature signature = Signature.getInstance(resolveSignatureAlgorithm(clientPrivateKey));
            signature.initSign(clientPrivateKey);
            signature.update(code.getBytes(StandardCharsets.UTF_8));
            byte[] rawSignature = signature.sign();
            return Base64.getUrlEncoder().withoutPadding().encodeToString(rawSignature);
        } catch (GeneralSecurityException ex) {
            throw new IllegalStateException("Failed to sign authorization code", ex);
        }
    }

    private PrivateKey loadPrivateKey(ResourceLoader resourceLoader, String path) {
        if (path == null || path.isBlank()) {
            throw new IllegalStateException("demo.sso.client-private-key-path is required");
        }
        Resource resource = resourceLoader.getResource(path);
        if (!resource.exists()) {
            throw new IllegalStateException("Client private key resource does not exist: " + path);
        }
        try {
            byte[] bytes = resource.getInputStream().readAllBytes();
            String pem = new String(bytes, StandardCharsets.UTF_8);
            String normalized = pem
                    .replace("-----BEGIN PRIVATE KEY-----", "")
                    .replace("-----END PRIVATE KEY-----", "")
                    .replaceAll("\\s+", "");
            byte[] keyBytes = Base64.getDecoder().decode(normalized);

            PrivateKey ecPrivateKey = tryParsePrivateKey("EC", keyBytes);
            if (ecPrivateKey != null) {
                return ecPrivateKey;
            }
            PrivateKey rsaPrivateKey = tryParsePrivateKey("RSA", keyBytes);
            if (rsaPrivateKey != null) {
                return rsaPrivateKey;
            }
            throw new IllegalStateException("Unsupported client private key type");
        } catch (IOException ex) {
            throw new IllegalStateException("Failed to load client private key", ex);
        }
    }

    private PrivateKey tryParsePrivateKey(String algorithm, byte[] keyBytes) {
        try {
            KeyFactory factory = KeyFactory.getInstance(algorithm);
            return factory.generatePrivate(new PKCS8EncodedKeySpec(keyBytes));
        } catch (GeneralSecurityException ex) {
            return null;
        }
    }

    private String resolveSignatureAlgorithm(PrivateKey privateKey) {
        if (privateKey instanceof ECPrivateKey) {
            return "SHA256withECDSA";
        }
        if (privateKey instanceof RSAPrivateKey) {
            return "SHA256withRSA";
        }
        throw new IllegalStateException("Unsupported client private key type");
    }

    @SuppressWarnings("unchecked")
    private ECPublicKey resolvePublicKeyByKid(String jwt) throws Exception {
        String[] segments = jwt.split("\\.");
        if (segments.length < 2) {
            throw new IllegalArgumentException("Invalid JWT format");
        }
        String headerJson = new String(Base64.getUrlDecoder().decode(segments[0]), StandardCharsets.UTF_8);
        Map<String, Object> header = JsonParserFactory.getJsonParser().parseMap(headerJson);
        String kid = (String) header.get("kid");

        Map<String, Object> jwks = restClient.get()
                .uri(properties.getIssuer() + "/sso/api/oauth2/jwks")
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
        if (!"EC".equals(String.valueOf(key.get("kty")))) {
            throw new IllegalStateException("Unsupported key type in JWKS");
        }
        String curve = String.valueOf(key.get("crv"));
        if (!EC_CURVE_P256.equals(curve)) {
            throw new IllegalStateException("Unsupported EC curve in JWKS: " + curve);
        }

        String x = String.valueOf(key.get("x"));
        String y = String.valueOf(key.get("y"));
        BigInteger xCoordinate = new BigInteger(1, Base64.getUrlDecoder().decode(x));
        BigInteger yCoordinate = new BigInteger(1, Base64.getUrlDecoder().decode(y));
        ECPublicKeySpec keySpec = new ECPublicKeySpec(new ECPoint(xCoordinate, yCoordinate), p256Parameters);

        KeyFactory factory = KeyFactory.getInstance("EC");
        return (ECPublicKey) factory.generatePublic(keySpec);
    }

    private ECParameterSpec loadP256Parameters() {
        try {
            AlgorithmParameters parameters = AlgorithmParameters.getInstance("EC");
            parameters.init(new ECGenParameterSpec("secp256r1"));
            return parameters.getParameterSpec(ECParameterSpec.class);
        } catch (GeneralSecurityException ex) {
            throw new IllegalStateException("Failed to load EC curve parameters", ex);
        }
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

    @SuppressWarnings("unchecked")
    private Map<String, Object> unwrapTokenData(Map<String, Object> response) {
        if (response == null) {
            throw new IllegalStateException("Token API response is empty");
        }

        Object data = response.get("data");
        if (data instanceof Map<?, ?> dataMap) {
            return (Map<String, Object>) dataMap;
        }

        if (response.containsKey("access_token") || response.containsKey("id_token")) {
            return response;
        }

        String message = resolveResultMessage(response);
        throw new IllegalStateException("Token API failed: " + message);
    }

    private String resolveResultMessage(Map<String, Object> response) {
        String msg = firstNonBlank(
                stringValue(response.get("msg")),
                stringValue(response.get("message")),
                stringValue(response.get("error_description")),
                stringValue(response.get("error"))
        );
        return msg == null ? "unknown error" : msg;
    }

    private String stringValue(Object value) {
        return value == null ? null : String.valueOf(value);
    }

    private String firstNonBlank(String... values) {
        if (values == null) {
            return null;
        }
        for (String value : values) {
            if (value != null && !value.isBlank()) {
                return value.trim();
            }
        }
        return null;
    }
}
