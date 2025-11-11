# Hanko

- Hanko is used for shared auth / login across HOT apps.
- It's an application that doesn't adhere to 12factor app
  env var specifications.
- Instead we need to configure with a config.yaml file.
- ConfigMap is not appropriate, as it needs secret vars.
- Instead we can create a SealedSecret from the `config.yaml`
  file, then mount this inside the deployment.

## Re-creating The Config Secret

- First, login to the k8s cluster.
- Create `config.yaml` containing the config YAML data:

```yaml
debug: false
account:
  allow_deletion: false
  allow_signup: true
database:
  user: hanko
  password: xxx
  host: hanko-db-rw.postgres.svc.cluster.local
  port: 5432
  dialect: postgres
email:
  enabled: true
  email:
    from_address: no-reply@example.com
    from_name: Example Application

  enabled: true
  optional: false
  acquire_on_registration: true
  acquire_on_login: false
  # Else OSM login does not work (we use dummy emails)
  require_verification: false
  limit: 5
  use_as_login_identifier: true
  max_length: 100
  use_for_authentication: true
  passcode_ttl: 300
email_delivery:
  enabled: true
  from_address: login@hotosm.org
  from_name: HOTOSM
  smtp:
    host: "smtp.gmail.com"
    port: "587"
    user: xxx
    password: "xxx"
secrets:
  keys:
    - xxx
# Session
service:
  name: HOTOSM Login
session:
  enable_auth_token_header: true
  audience:
    - "https://login.hotosm.org"
  issuer: "https://login.hotosm.org"
  # Change this to expire JWT faster
  lifespan: 72h
  cookie:
    name: "hanko"
    # .hotosm.org works for all levels of subdomain nesting
    domain: ".hotosm.org"
    retention: persistent
    secure: true
    http_only: true
    same_site: "lax"
server:
  public:
    cors:
      allow_origins:
        - "https://portal.hotosm.org"
        - "https://demo.login.hotosm.org"
        - "https://ui.hotosm.org"
        - "https://fmtm.hotosm.org"
        - "https://hotosm.github.io/openaerialmap"
# Login methods
password:
  enabled: true
third_party:
  error_redirect_url: https://login.hotosm.org
  redirect_url: https://login.hotosm.org/thirdparty/callback
  allowed_redirect_urls:
    - https://**.hotosm.org
    - https://ui.hotosm.org
  providers:
    google:
      enabled: true
      client_id: "xxx"
      secret: "xxx"
  custom_providers:
    openstreetmap:
      enabled: true
      display_name: "OpenStreetMap"
      client_id: "xxx"
      secret: "xxx"
      scopes:
        - "read_prefs"
        - "send_messages"
        - "write_api"
      # OSM does not implement OpenID Connect as an indentity provider
      # See: https://github.com/openstreetmap/openstreetmap-website/issues/5063
      use_discovery: false
      # issuer: "https://www.openstreetmap.org/.well-known/openid-configuration"
      authorization_endpoint: "https://www.openstreetmap.org/oauth2/authorize"
      token_endpoint: "https://www.openstreetmap.org/oauth2/token"
      # userinfo_endpoint: "https://www.openstreetmap.org/oauth2/userinfo" # this endpoint is forbidden
      # userinfo_endpoint: "https://www.openstreetmap.org/api/0.6/user/details.json" # this endpoint doesn't have email key
      userinfo_endpoint: "http://osm-userinfo.hanko.svc.cluster.local:8080"
      # Do not link to existing user accounts, as OSM does not return email address
      allow_linking: false
webauthn:
  timeouts:
    registration: 600000
    login: 600000
  relying_party:
    id: login.hotosm.org
    origins:
      - "https://login.hotosm.org"
# We don't need such high level security for OSM data...
mfa:
  enabled: false
```

- Then create a `secret.yaml` from the config:

```bash
kubectl create secret generic hanko-config \
  --from-file=config.yaml=./config.yaml \
  --namespace hanko \
  --dry-run=client -o yaml > secret.yaml
```

- Then create a sealed secret and commit to the repo:

```bash
kubeseal -f secret.yaml -w sealed-config.yaml
```

> [!IMPORTANT]
> Make sure you cleanup / delete the config.yaml and secret.yaml.
