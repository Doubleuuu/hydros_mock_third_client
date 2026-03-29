# hydros-sso-demo-client

Minimal relying-party demo app for `hydros-sso-app`.

## Flow

1. Open `/` on port `9091`
2. Click `Start Login`
3. Browser redirects to SSO authorize endpoint
4. Login in SSO page (`demo/demo123`)
5. Callback exchanges authorization code for tokens
6. Demo app verifies `id_token` signature using SSO JWKS endpoint

## Endpoints

- `/` home page
- `/demo/login` trigger authorization flow
- `/callback` authorization callback
- `/demo/refresh` refresh access token
- `/demo/logout` clear local session
