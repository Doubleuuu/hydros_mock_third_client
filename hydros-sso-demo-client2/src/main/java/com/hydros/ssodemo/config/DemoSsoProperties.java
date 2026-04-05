package com.hydros.ssodemo.config;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

@Getter
@Setter
@ConfigurationProperties(prefix = "demo.sso")
public class DemoSsoProperties {

    private String issuer = "http://localhost:7071";
    private String clientId = "demo-client";
    private String clientPrivateKeyPath = "classpath:keys/demo-client-private.pem";
    private long clientAssertionTtlSeconds = 300;
    private String redirectUri = "http://localhost:9091/callback";
    private String scope = "openid profile";
}
