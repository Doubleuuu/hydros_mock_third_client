package com.hydros.ssodemo.controller;

import com.hydros.ssodemo.service.DemoOidcService;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpSession;
import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.security.SecureRandom;
import java.util.Base64;
import java.util.Map;

@RestController
public class DemoClientController {

    private static final String SESSION_STATE = "demo.sso.state";
    private static final String SESSION_NONCE = "demo.sso.nonce";
    private static final String SESSION_REDIRECT_URI = "demo.sso.redirect_uri";
    private static final String SESSION_TOKENS = "demo.sso.tokens";
    private static final String SESSION_ID_CLAIMS = "demo.sso.id_claims";

    private final DemoOidcService oidcService;
    private final SecureRandom secureRandom = new SecureRandom();

    public DemoClientController(DemoOidcService oidcService) {
        this.oidcService = oidcService;
    }

    @GetMapping("/")
    public ResponseEntity<String> index(HttpSession session) {
        Map<String, Object> tokens = castMap(session.getAttribute(SESSION_TOKENS));
        Map<String, Object> claims = castMap(session.getAttribute(SESSION_ID_CLAIMS));

        String tokenBlock = tokens == null ? "<p>No tokens in session.</p>" :
                "<pre style='white-space:pre-wrap;word-break:break-all;'>" + escapeHtml(tokens.toString()) + "</pre>";
        String claimsBlock = claims == null ? "<p>No verified ID token claims.</p>" :
                "<pre style='white-space:pre-wrap;word-break:break-all;'>" + escapeHtml(claims.toString()) + "</pre>";

        String html = """
                <!doctype html>
                <html lang="en">
                <head>
                  <meta charset="utf-8"/>
                  <meta name="viewport" content="width=device-width, initial-scale=1"/>
                  <title>Hydros SSO Demo Client</title>
                  <style>
                    body { font-family: 'Segoe UI', sans-serif; margin: 24px; color: #101828; background: #f8fafc; }
                    a.btn { display:inline-block; margin-right: 10px; margin-bottom:10px; padding:8px 12px; border-radius:8px; text-decoration:none; color:#fff; background:#175cd3; }
                    a.alt { background:#026aa2; }
                    a.warn { background:#b42318; }
                    .card { background:#fff; border-radius:12px; box-shadow:0 8px 20px rgba(0,0,0,.06); padding:16px; margin-top:14px; }
                  </style>
                </head>
                <body>
                  <h1>Hydros OIDC Demo Client</h1>
                  <a class="btn" href="/demo/login">Start Login</a>
                  <a class="btn alt" href="/demo/refresh">Refresh Token</a>
                  <a class="btn warn" href="/demo/logout">Clear Session</a>
                  <div class="card">
                    <h3>Token Response</h3>
                    %s
                  </div>
                  <div class="card">
                    <h3>Verified ID Token Claims</h3>
                    %s
                  </div>
                </body>
                </html>
                """.formatted(tokenBlock, claimsBlock);

        return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(html);
    }

    @GetMapping("/demo/login")
    public ResponseEntity<Void> startLogin(HttpSession session, HttpServletRequest request) {
        String state = randomToken(24);
        String nonce = randomToken(24);
        String redirectUri = buildCurrentCallbackUri(request);
        session.setAttribute(SESSION_STATE, state);
        session.setAttribute(SESSION_NONCE, nonce);
        session.setAttribute(SESSION_REDIRECT_URI, redirectUri);

        String authorizeUrl = oidcService.buildAuthorizeUrl(state, nonce, redirectUri);
        return redirect(authorizeUrl);
    }

    @GetMapping("/callback")
    public ResponseEntity<String> callback(@RequestParam(name = "code", required = false) String code,
                                           @RequestParam(name = "state", required = false) String state,
                                           @RequestParam(name = "error", required = false) String error,
                                           HttpSession session) {
        if (error != null) {
            return errorPage("SSO returned error: " + error);
        }
        if (code == null || code.isBlank()) {
            return errorPage("Missing authorization code");
        }
        String expectedState = (String) session.getAttribute(SESSION_STATE);
        if (expectedState == null || !expectedState.equals(state)) {
            return errorPage("State mismatch. Please restart from /demo/login and keep the same host (localhost or 127.0.0.1).");
        }

        try {
            String redirectUri = (String) session.getAttribute(SESSION_REDIRECT_URI);
            if (redirectUri == null || redirectUri.isBlank()) {
                return errorPage("Missing redirect_uri in session. Please restart from /demo/login.");
            }
            Map<String, Object> tokenResponse = oidcService.exchangeAuthorizationCode(code, redirectUri);
            String idToken = String.valueOf(tokenResponse.get("id_token"));
            String expectedNonce = (String) session.getAttribute(SESSION_NONCE);
            Map<String, Object> claims = oidcService.verifyIdToken(idToken, expectedNonce);

            session.setAttribute(SESSION_TOKENS, tokenResponse);
            session.setAttribute(SESSION_ID_CLAIMS, claims);
            session.removeAttribute(SESSION_STATE);
            session.removeAttribute(SESSION_NONCE);
            session.removeAttribute(SESSION_REDIRECT_URI);

            return redirectToHtml("/", "Authorization code exchanged and ID token verified");
        } catch (Exception ex) {
            return errorPage("Callback failed: " + ex.getMessage());
        }
    }

    @GetMapping("/demo/refresh")
    public ResponseEntity<String> refresh(HttpSession session) {
        Map<String, Object> tokens = castMap(session.getAttribute(SESSION_TOKENS));
        if (tokens == null || tokens.get("refresh_token") == null) {
            return errorPage("No refresh token in session");
        }
        try {
            String refreshToken = String.valueOf(tokens.get("refresh_token"));
            Map<String, Object> refreshed = oidcService.refreshByToken(refreshToken);
            Map<String, Object> claims = oidcService.verifyIdToken(String.valueOf(refreshed.get("id_token")), null);
            session.setAttribute(SESSION_TOKENS, refreshed);
            session.setAttribute(SESSION_ID_CLAIMS, claims);
            return redirectToHtml("/", "Refresh token exchange succeeded");
        } catch (Exception ex) {
            return errorPage("Refresh failed: " + ex.getMessage());
        }
    }

    @GetMapping("/demo/logout")
    public ResponseEntity<Void> logout(HttpSession session) {
        session.invalidate();
        return redirect("/");
    }

    private ResponseEntity<Void> redirect(String location) {
        return ResponseEntity.status(HttpStatus.FOUND)
                .header(HttpHeaders.LOCATION, location)
                .build();
    }

    private ResponseEntity<String> redirectToHtml(String location, String message) {
        String html = """
                <!doctype html>
                <html><head><meta charset="utf-8"/><title>Redirect</title></head>
                <body style="font-family:Segoe UI, sans-serif; padding:30px;">
                <p>%s</p>
                <p><a href="%s">Continue</a></p>
                </body></html>
                """.formatted(escapeHtml(message), escapeHtml(location));
        return ResponseEntity.ok().contentType(MediaType.TEXT_HTML).body(html);
    }

    private ResponseEntity<String> errorPage(String message) {
        String html = """
                <!doctype html>
                <html><head><meta charset="utf-8"/><title>Error</title></head>
                <body style="font-family:Segoe UI, sans-serif; padding:30px;">
                <h2>Demo client error</h2>
                <p style="color:#b42318;">%s</p>
                <p><a href="/">Back to home</a></p>
                </body></html>
                """.formatted(escapeHtml(message));
        return ResponseEntity.status(HttpStatus.BAD_REQUEST).contentType(MediaType.TEXT_HTML).body(html);
    }

    private String randomToken(int byteLength) {
        byte[] bytes = new byte[byteLength];
        secureRandom.nextBytes(bytes);
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    private String buildCurrentCallbackUri(HttpServletRequest request) {
        return request.getScheme() + "://" + request.getServerName() + ":" + request.getServerPort() + "/callback";
    }

    @SuppressWarnings("unchecked")
    private Map<String, Object> castMap(Object raw) {
        if (raw instanceof Map<?, ?> map) {
            return (Map<String, Object>) map;
        }
        return null;
    }

    private String escapeHtml(String raw) {
        if (raw == null) {
            return "";
        }
        return raw
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;");
    }
}
