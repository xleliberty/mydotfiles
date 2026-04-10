# Plan — stripeconnect.eliberty.fr

## Context

The repo is empty (only `docs/stripeconnector-website.md` and a stub README).
We are bootstrapping a brand-new Symfony 8.x / PHP 8.4 web app whose sole job is
to onboard E-Liberty customers onto our Stripe Connect platform via the
**OAuth standard accounts** flow
(https://docs.stripe.com/connect/oauth-standard-accounts).

The site exposes three pages:

1. **Landing** — branded explanation + CTA "Connect my account with E-Liberty"
   that redirects the browser to Stripe's OAuth authorize URL.
2. **OAuth callback** (`/oauth/callback`) — exchanges the `code` against an
   access token via Stripe API, then renders either…
3. **Success** or **Error/Unfinished** result page (single template, two
   states) — display only, every meaningful event is logged via Monolog.
   No DB, no persistence.

The whole stack must be Dockerized (FrankenPHP), CI-validated with Mago +
PHPUnit, and deployable to two ECS Fargate environments (preprod/prod) sharing
an existing ALB, via idempotent shell scripts.

---

## Tech stack & conventions

| Concern        | Choice                                                          |
|----------------|-----------------------------------------------------------------|
| Language       | PHP 8.4                                                         |
| Framework      | Symfony 8.x (full stack, Twig, Monolog, HttpClient bundles)     |
| Runtime image  | `dunglas/frankenphp:latest-php8.4` (worker mode)                |
| Templating     | Twig                                                            |
| Logging        | Monolog → stderr (JSON formatter) → CloudWatch via awslogs      |
| HTTP to Stripe | `symfony/http-client` (no `stripe/stripe-php` SDK needed — only |
|                | one OAuth token endpoint is called)                             |
| Test           | PHPUnit (latest, attribute-based)                               |
| Quality        | Mago (format + lint + analyze)                                  |
| Secrets        | AWS SSM Parameter Store (SecureString), injected by ECS         |
| IaC            | Shell scripts using idempotent `aws` CLI calls                  |
| CI             | GitHub Actions (mago + phpunit on every push/PR)                |
| CD             | GitHub Actions on release tagged `*-preprod` → OIDC → ECS deploy|

---

## Repository layout

```
.
├── .github/
│   └── workflows/
│       ├── ci.yml                  # mago + phpunit
│       └── deploy-preprod.yml      # OIDC → build → push ECR → ecs deploy
├── bin/console
├── compose.yaml                    # dev stack (frankenphp + mailcatcher? no — just app)
├── compose.override.yaml           # dev-only volumes / xdebug
├── config/
│   ├── bundles.php
│   ├── packages/
│   │   ├── framework.yaml
│   │   ├── monolog.yaml            # JSON to stderr in prod, pretty in dev
│   │   ├── twig.yaml
│   │   └── routing.yaml
│   ├── routes.yaml
│   └── services.yaml
├── docker/
│   ├── Dockerfile                  # multi-stage: composer → frankenphp runtime
│   ├── Caddyfile                   # frankenphp vhost
│   └── php.ini
├── deploy/
│   ├── lib.sh                      # shared aws helpers (idempotent wrappers)
│   ├── ensure-cluster.sh
│   ├── ensure-target-group.sh
│   ├── ensure-listener-rule.sh
│   ├── ensure-task-definition.sh
│   ├── ensure-service.sh
│   ├── deploy.sh                   # orchestrates everything for $ENV
│   └── env/
│       ├── preprod.env
│       └── prod.env                # placeholder; values TBD
├── docs/
│   └── stripeconnector-website.md  # original spec (kept)
├── public/
│   └── index.php
├── src/
│   ├── Controller/
│   │   ├── HomeController.php          # GET /  → landing
│   │   ├── ConnectController.php       # GET /connect → 302 to Stripe authorize URL
│   │   └── OAuthCallbackController.php # GET /oauth/callback?code=&state=
│   ├── Stripe/
│   │   ├── StripeOAuthClient.php       # exchange code → token via http-client
│   │   └── Dto/StripeOAuthTokenResponse.php
│   ├── Security/
│   │   └── OAuthStateManager.php       # CSRF/state token via session
│   └── Kernel.php
├── templates/
│   ├── base.html.twig                  # E-Liberty corporate layout (header, footer, reinsurance)
│   ├── home.html.twig
│   └── result.html.twig                # success | error variants driven by `status`
├── translations/
├── tests/
│   ├── Controller/
│   │   ├── HomeControllerTest.php
│   │   ├── ConnectControllerTest.php
│   │   └── OAuthCallbackControllerTest.php
│   ├── Stripe/
│   │   └── StripeOAuthClientTest.php   # MockHttpClient
│   └── Security/
│       └── OAuthStateManagerTest.php
├── Makefile
├── mago.toml
├── phpunit.xml.dist
├── composer.json
├── .env                            # public defaults
├── .env.local.dist                 # template for dev secrets
└── README.md
```

---

## OAuth flow (implementation details)

1. `GET /` — `HomeController` renders `home.html.twig`. CTA links to `/connect`.
2. `GET /connect` — `ConnectController`
   - Generates a CSRF `state` via `OAuthStateManager` (session-stored, 10-min TTL).
   - Builds Stripe authorize URL:
     `https://connect.stripe.com/oauth/authorize?response_type=code&client_id=$STRIPE_CLIENT_ID&scope=read_write&state=$state&redirect_uri=$REDIRECT_URI`
   - Logs `stripe.connect.initiated` (info).
   - Returns 302.
3. `GET /oauth/callback` — `OAuthCallbackController`
   - Reads `code`, `state`, `error`, `error_description`.
   - If `error` is present → log `stripe.connect.user_aborted` (warning), render
     `result.html.twig` with `status=error`.
   - Validates `state` against `OAuthStateManager`. Mismatch → log
     `stripe.connect.state_mismatch` (error), render error.
   - Calls `StripeOAuthClient::exchangeCode($code)`:
     POST `https://connect.stripe.com/oauth/token`
     with `client_secret`, `code`, `grant_type=authorization_code`.
   - On HTTP error or non-2xx → log `stripe.connect.token_exchange_failed`
     (error, with response body), render error.
   - On success → log `stripe.connect.success`
     (info, with `stripe_user_id`, `livemode`, masked token), render success.

**No persistence** — the page is the only output. Monolog is the audit trail.

### Configuration (env vars)

| Var                       | Source (preprod/prod) | Dev default                       |
|---------------------------|------------------------|-----------------------------------|
| `APP_ENV`                 | task def               | `dev`                             |
| `APP_SECRET`              | SSM SecureString       | random in `.env.local`            |
| `STRIPE_CLIENT_ID`        | SSM SecureString       | `.env.local`                      |
| `STRIPE_CLIENT_SECRET`    | SSM SecureString       | `.env.local`                      |
| `STRIPE_REDIRECT_URI`     | task def (plain)       | `http://localhost/oauth/callback` |
| `STRIPE_OAUTH_BASE_URL`   | task def (plain)       | `https://connect.stripe.com`      |

SSM path convention: `/stripeconnect-website/{env}/{KEY}`.

---

## Docker / FrankenPHP

- **Multi-stage Dockerfile**:
  - stage `vendor`: `composer:2` → `composer install --no-dev --no-scripts -o`
  - stage `runtime`: `dunglas/frankenphp:1-php8.4` → copy app + vendor,
    `EXPOSE 80`, healthcheck `GET /healthz`.
- `Caddyfile` enables `frankenphp { worker /app/public/index.php }` for the
  worker-mode performance Symfony recommends.
- A trivial `HealthController` answers `/healthz` for ALB target group.
- `compose.yaml` for dev: single `app` service, ports `80:80`, bind-mounts
  source for hot reload, `XDEBUG_MODE=off` by default.

---

## Quality & test tooling

- **Mago** (`mago.toml`): enable `format`, `lint`, `analyze`. Targets `src/`,
  `tests/`, `public/`.
- **PHPUnit** (latest, attribute syntax — `#[Test]`, `#[DataProvider]`, etc.).
  - Controller tests use `WebTestCase` + `MockHttpClient` to stub Stripe.
  - `StripeOAuthClientTest` covers happy path, HTTP error, malformed JSON.
  - `OAuthStateManagerTest` covers create/validate/expired/replay.
- Full CI gate: `make ci` ⇒ `mago format --check && mago lint && mago analyze && phpunit`.

### Makefile targets

```
make up               # docker compose up -d
make down
make sh               # exec into app container
make install          # composer install
make test             # phpunit
make format           # mago format
make lint             # mago lint
make analyze          # mago analyze
make ci               # format --check + lint + analyze + test
make build            # docker build -t stripeconnect-website:local .
make deploy ENV=preprod
```

---

## Infrastructure & deployment scripts

All scripts live under `deploy/`, take `ENV` (preprod|prod) as the only input,
and are **idempotent** (read-then-create-or-update pattern via `aws ... describe-*`).

`deploy/lib.sh` provides:

- `aws_or_create <describe-cmd> <create-cmd>` helper
- shared variable loader from `deploy/env/$ENV.env`
- consistent naming: `stripeconnect-website-${ENV}-{cluster|svc|tg|task|logs}`

Per-env file `deploy/env/preprod.env`:

```sh
ENV=preprod
AWS_REGION=eu-west-1
ACCOUNT_ID=004794120172
CLUSTER_NAME=stripeconnect-website-preprod-cluster
SERVICE_NAME=stripeconnect-website-preprod-svc
TG_NAME=stripeconnect-website-preprod-tg
TASK_FAMILY=stripeconnect-website-preprod
ALB_ARN=arn:aws:elasticloadbalancing:eu-west-1:004794120172:loadbalancer/app/preprod-shared-alb/668daaa81d5faa93
LISTENER_ARN=arn:aws:elasticloadbalancing:eu-west-1:004794120172:listener/app/preprod-shared-alb/668daaa81d5faa93/ea03274d8f2e4f4f
VPC_ID=vpc-0b9ef02f7aaf3b3d5
SUBNETS="subnet-0abc5e311761adb09 subnet-093122bf91d93015d"
SECURITY_GROUP=sg-0bac5a56a67d31cfa
HOST=stripeconnect.eliberty.fr
ECR_REPO=stripeconnect-website
DESIRED_COUNT=2
CPU=512
MEMORY=1024
```

> Note — the spec listed two `subnet-*` values under "security groups". I
> interpret these as **subnets** and the `sg-*` value as the security group.
> This will be reconfirmed during execution.

`deploy/deploy.sh` orchestration order:

1. `ensure-target-group.sh` — create TG (port 80, HTTP, target type `ip`,
   healthcheck `/healthz`) if missing.
2. `ensure-listener-rule.sh` — add host-header rule on the shared listener
   matching `$HOST` → forward to TG (skip if rule already exists).
3. `ensure-cluster.sh` — `aws ecs create-cluster` if missing.
4. `ensure-task-definition.sh` — register a new revision pointing at the new
   image tag, with `secrets` referencing SSM paths.
5. `ensure-service.sh` — create the service the first time
   (`launchType=FARGATE`, attach to TG, in `$SUBNETS` + `$SECURITY_GROUP`),
   otherwise `aws ecs update-service --force-new-deployment`.
6. Wait for service stability (`aws ecs wait services-stable`).

### CI/CD (GitHub Actions)

- `.github/workflows/ci.yml` — runs on push & PR:
  - matrix: PHP 8.4 only
  - `composer install`
  - `make ci`
- `.github/workflows/deploy-preprod.yml` — runs on
  `release: { types: [published] }` filtered to tags ending in `-preprod`:
  - OIDC `aws-actions/configure-aws-credentials` → role
    `arn:aws:iam::004794120172:role/github-oidc-stripeconnect-website-preprod`
    *(name to be confirmed; document in README)*
  - `docker build` + push to ECR (`$ECR_REPO:$GIT_SHA` and `:preprod`)
  - `./deploy/deploy.sh preprod` with `IMAGE_TAG=$GIT_SHA`

Production workflow stub will be added later (spec says "we will elaborate
later for production").

---

## CLAUDE.md (to be written after plan approval)

Will document — for future Claude sessions — only the **non-obvious** facts
that cannot be derived from reading the repo:

- Project goal in one paragraph + Stripe doc link.
- The OAuth flow + the **no-persistence / log-only** rule (this is a
  deliberate choice, not an omission).
- Quality gate command: `make ci` must pass before any commit.
- Mago is the single source of truth for format/lint/analyze — never run
  `php-cs-fixer`/`phpstan` directly.
- PHPUnit uses **attribute** syntax exclusively (no doc-block annotations).
- ECS naming convention: `stripeconnect-website-${ENV}-{cluster|svc|tg}`.
- Secrets live in SSM under `/stripeconnect-website/{env}/...`; never inline.
- Deployment is driven by `deploy/deploy.sh ENV=...` — never `aws` ad-hoc.
- Production env values are intentionally placeholders until further notice.

---

## Verification (end-to-end)

After implementation:

1. **Local** — `make up && make ci` must be green.
2. **Local OAuth happy path** — set Stripe test client_id/secret in
   `.env.local`, browse to `http://localhost/`, click CTA, complete the Stripe
   sandbox flow, land on success page; check container logs for
   `stripe.connect.success` JSON entry.
3. **Local error path** — manually hit
   `/oauth/callback?error=access_denied&error_description=foo` → error page +
   `stripe.connect.user_aborted` log.
4. **State CSRF** — hit `/oauth/callback?code=x&state=wrong` → error page +
   `stripe.connect.state_mismatch` log.
5. **Image build** — `make build` succeeds; `docker run -p 8080:80 …` serves
   `/healthz` 200.
6. **Preprod deploy dry-run** — run each `deploy/ensure-*.sh` script with
   `--dry-run`-style read-only flags first to confirm idempotency, then run
   `deploy/deploy.sh preprod` against a throwaway tag. `aws ecs wait
   services-stable` exits 0 and the ALB host returns 200 on `/healthz`.
7. **CI** — push a branch, confirm GitHub Actions `ci.yml` is green.
8. **CD** — cut a `v0.1.0-preprod` release; confirm `deploy-preprod.yml`
   builds, pushes to ECR, and the ECS service rolls over to the new task def.

---

## Open items (to confirm during execution, not blocking the plan)

- Exact GitHub OIDC role ARN/name for preprod (must be created out-of-band by
  AWS admin).
- ECR repository creation — assumed pre-existing; if not, add an
  `ensure-ecr.sh` script.
- Confirmation of subnet vs security-group interpretation in the spec.
- Brand assets (logo, colors) for `base.html.twig` — placeholder until
  delivered.
