# ElibertyBookingV2 provider implementation

## Context

The booking team has shipped a new REST API to replace the legacy Eliberty booking backend. We need a new provider `ElibertyBookingV2` that plugs into the existing `ExternalActivityHandlerInterface` so bookable products can be served by the new backend without changing the funnel or other providers.

The new backend is split across **two distinct hosts**:
- **Super-admin backend** (`https://superadmin-backend.skiwise.com`) — hosts ONLY `POST /login`, which returns the JWT used everywhere else. Documented in `booking-admin-api.json`.
- **Booking module** (`https://booking-module.skiwise.com`) — hosts EVERY other endpoint, including the ones prefixed `/admin/*` (e.g. `GET /admin/timeslot/list/{resourceUuid}`) and all `/client/booking/*` calls. Documented in `booking-api-swagger.json`.

Both hosts accept the same Bearer JWT issued by `/login`. Every call to the booking-module host must also carry the multi-tenant header `x-tenant-slag`, whose value is read from ConfigManager key `booking.v2.tenant-slag`.

The new provider must satisfy the same `ExternalActivityHandlerInterface` contract as `AxBooking`, `ElibertyBooking`, `Koralp`, `TeamaxessReservation`, so the existing `BookingService` / `BookingHelper` / cart funnel keep working unchanged. Existing providers stay untouched.

PHP 7.4. All code must pass phpcs, phpstan level 1, and ship with PHPUnit unit tests.

## Architectural decisions (locked)

1. **Auth**: a single JWT obtained from `POST /login` (super-admin host) is sent as `Authorization: Bearer` on all booking-module calls.
2. **HTTP layer**: MUST use the existing `src/RedpillBundle/ApiClient` infrastructure (`AuthJwtApiClient` + `ParameterizedClientFactory` + `RedisApiToken` + `JwtToken`). No raw Guzzle. No new token cache. No new client factory.
3. **synchronizeBooking** = `POST /client/booking/prebook/extend/{bookingUuid}` only. No booker mutation between prebook and confirm.
4. **createBooking** payload uses real Order data via `BaseApiHelper` booker fallback chain, defaulting to existing constants when missing.
5. **No refactor** of existing providers / `BaseApiHelper`. All new code lives under `ExternalActivity/ElibertyBookingV2/` and `ApiClient/ElibertyBookingV2/`.

## Files to create

```
src/RedpillBundle/ApiClient/ElibertyBookingV2/
├── Client/
│   └── ElibertyBookingV2ApiClient.php   # Decorator: adds x-tenant-slag header on every call
└── Repository/
    └── BookingV2Repository.php          # Thin repo: one method per remote endpoint, returns arrays

src/RedpillBundle/ExternalActivity/ElibertyBookingV2/
└── Rest/
    ├── ApiHelper.php                    # Param builders + response→entity mappers
    └── ElibertyBookingV2Handler.php     # Implements ExternalActivityHandlerInterface

tests/Unit/Eliberty/RedpillBundle/ApiClient/ElibertyBookingV2/
├── Client/ElibertyBookingV2ApiClientTest.php
└── Repository/BookingV2RepositoryTest.php

tests/Unit/Eliberty/RedpillBundle/ExternalActivity/ElibertyBookingV2/
└── Rest/
    ├── ElibertyBookingV2HandlerTest.php
    └── ApiHelperTest.php
```

## Files to modify

| File | Change |
|---|---|
| `src/RedpillBundle/Enum/ExternalBookingProvider.php` | Add `ELIBERTY_BOOKING_V2 = 'eliberty_booking_v2'` and append to `$values` array. |
| `src/RedpillBundle/Resources/config/services.yml` | Add 4 service definitions: the underlying `AuthJwtApiClient` (built via `ParameterizedClientFactory::createAuthJwtApiClient`), the `ElibertyBookingV2ApiClient` decorator, the `BookingV2Repository`, and the `ElibertyBookingV2Handler`. The handler is auto-tagged via the existing autoconfiguration of `ExternalActivityHandlerInterface`. |

No DB migration: re-uses `SubContingent` and `ExternalBooking` entities, distinguished by `type = 'eliberty_booking_v2'`.

## Configuration keys (ConfigManager)

| Key | Type | Purpose |
|---|---|---|
| `booking.v2.tenant-slag` | string | sent as `x-tenant-slag` header on every booking-module call |
| `booking.v2.api_base_url` | string | booking-module host, e.g. `https://booking-module.skiwise.com` |
| `booking.v2.login_url` | string | absolute URL to `POST /login`, e.g. `https://superadmin-backend.skiwise.com/login` |
| `booking.v2.credentials` | json | `{"username": "...", "password": "..."}` (consumed by `ApiConfigParameters` as a single `credentials` value) |
| `booking.v2.cache_expiration_time` | int | timeslot list TTL (default falls back to existing `booking.cache_expiration_time`) |

## Component design

### `ApiClient/ElibertyBookingV2/Client/ElibertyBookingV2ApiClient`

Lightweight decorator implementing `ApiClientInterface`. Its only job is to inject the `x-tenant-slag` header into every call before delegating to the underlying `AuthJwtApiClient` (which already handles JWT login, Redis token caching, TTL from JWT exp claim, and 401-retry).

```php
final class ElibertyBookingV2ApiClient implements ApiClientInterface
{
    public function __construct(
        private ApiClientInterface $authClient,   // wired to the AuthJwtApiClient service
        private ConfigManager $configManager
    ) {}

    public function call(string $method, string $uri = '', array $options = []): ApiResponseInterface
    {
        $tenantSlag = $this->configManager->getStringOption('booking.v2.tenant-slag');
        $options['headers']['x-tenant-slag'] = $tenantSlag;
        return $this->authClient->call($method, $uri, $options);
    }
}
```

> Why a decorator and not `$apiParams['options']['headers']`: the tenant-slag must be read from ConfigManager (per-tenant), not baked into a static service-container parameter. The decorator is the smallest correct seam.

### `ApiClient/ElibertyBookingV2/Repository/BookingV2Repository`

Mirrors the existing `Trinity\Resources\BaseTrinityApiClient` style: a thin wrapper around `ApiClientInterface` that exposes one PHP method per remote endpoint and returns associative arrays. No business logic, no entity mapping.

```php
class BookingV2Repository
{
    public function __construct(private ApiClientInterface $bookingV2ApiClient) {}

    public function listTimeslots(string $resourceUuid, string $dateFrom, string $dateTo): array
    {
        return $this->bookingV2ApiClient->call(
            'GET',
            sprintf('/admin/timeslot/list/%s', $resourceUuid),
            ['query' => ['dateFrom' => $dateFrom, 'dateTo' => $dateTo]]
        )->getData();
    }

    public function createBooking(string $timeslotUuid, array $payload): array
    {
        return $this->bookingV2ApiClient->call(
            'POST',
            sprintf('/client/booking/%s', $timeslotUuid),
            ['json' => $payload]
        )->getData();
    }

    public function extendPrebook(string $bookingUuid): array
    {
        return $this->bookingV2ApiClient->call(
            'POST',
            sprintf('/client/booking/prebook/extend/%s', $bookingUuid)
        )->getData();
    }

    public function confirmPrebook(string $bookingUuid, array $payload): array
    {
        return $this->bookingV2ApiClient->call(
            'POST',
            sprintf('/client/booking/prebook/confirm/%s', $bookingUuid),
            ['json' => $payload]
        )->getData();
    }
}
```

Throws naturally: `AuthJwtApiClient` raises `ApiClientException` / `ApiRetryableException` on non-2xx that isn't a token error. The handler catches and rewraps as `ExternalActivityException`.

### `ExternalActivity/ElibertyBookingV2/Rest/ApiHelper`

Extends the existing `BaseApiHelper` to inherit the booker fallback chain, redis cache key helper, cache TTL accessor, logger. Pure mapping/serialization, no HTTP.

Methods:

- `buildCreateBookingPayload(Order, SubContingentData): array` — assembles the `RequestCreateBookingDto` body.
  - `isItPreBooking = true`
  - `customerUserId = (string) $order->getId()`
  - `customerName = trim(getBookerName('firstname', ...) . ' ' . getBookerName('lastname', ...))` (uses base helper fallback chain)
  - `customerEmail = $order->getEmail() ?? ExternalBooking::DEFAULT_NAME . '@local'`
  - `customerPhoneNumber = getBookerPhone(...)`
  - `bookingDetail = { productName, productId: $product->getCode(), pricePaid (cents), currency: 'EUR', orderDate: today, origin: 'ESHOP' }`
- `buildConfirmBookingPayload(Order, ExternalBooking): array` — re-emits the same `bookingDetail` shape.
- `mapTimeslotToSubContingent(array $timeslot, Product, WebInstance): SubContingent` — find-or-create by `externalId = $timeslot['uuid']`, sets `quotaAvailable = capacity - occupiedSlots`, `quotaInUse = occupiedSlots`, `date = startDate + startTime minutes`, `dailyBooking = false`, `type = ELIBERTY_BOOKING_V2`. Persists via injected `EntityManagerInterface`.
- `mapBookingResponseToExternalBooking(array $response, ?SubContingent, ?ExternalBooking): ExternalBooking` — sets `externalId = $response['uuid']`, status from `$response['isCanceled']`.
- `getDateRangeForAvailability(Product): array{from:string, to:string}` — re-uses the season pattern from `src/RedpillBundle/ExternalActivity/Traits/getDaysAvailabilityTrait.php`.

### `ExternalActivity/ElibertyBookingV2/Rest/ElibertyBookingV2Handler`

Implements `ExternalActivityHandlerInterface`. Constructor injects `BookingV2Repository`, `ApiHelper` (the new one), `CacheInterface $redisCache`, `EntityManagerInterface`, `LoggerInterface $loggerBooking`.

Interface method mapping:

| Interface method | Implementation |
|---|---|
| `getDaysAvailability(Product)` | Compute `[dateFrom, dateTo]` via `ApiHelper::getDateRangeForAvailability`. Cache by `getRedisKey('booking_v2_days', $resourceUuid, $params)`. On miss, `$repository->listTimeslots(...)`, return distinct `startDate` values. |
| `getSubContingentsBetweenDates(Product, $start, $end)` | Same `listTimeslots` call with the requested range. Map every timeslot via `ApiHelper::mapTimeslotToSubContingent()`. **Cached**. |
| `getSubContingent(Product, $date, $id, $withCache)` | Try DB lookup `(externalId=$id, webinstance, type=v2)`; on miss, call `getSubContingentsBetweenDates` for that single day and re-query DB. |
| `createBooking(Order, SubContingentData)` | `$repository->createBooking($subContingent->getExternalId(), $apiHelper->buildCreateBookingPayload(...))`. Map response → ExternalBooking with status INIT. Persist. |
| `synchronizeBooking(Order, ExternalBooking)` | `$repository->extendPrebook($externalBooking->getExternalId())`. Status untouched. |
| `confirmBooking(Order, ExternalBooking)` | `$repository->confirmPrebook($externalBooking->getExternalId(), $apiHelper->buildConfirmBookingPayload(...))`. Status → CONFIRMED. |
| `findBooking($externalBookingId, WebInstance, ?$item)` | DB-only lookup (mirrors v1; the new API has no read-by-id endpoint). |

All public methods wrap external errors (`ApiClientException`, `ApiRetryableException`, `\Throwable`) into `ExternalActivityException` via `BaseApiHelper::parseAndLogException()`.

## Service wiring (services.yml)

```yaml
# Underlying authenticated JWT client built by the existing factory.
# login_url is absolute and points to the super-admin host;
# main_uri/base_uri points to the booking-module host.
eliberty_booking_v2.api.client.jwt.authenticated:
    class: Eliberty\RedpillBundle\ApiClient\Infra\Client\AuthJwtApiClient
    factory: ['@Eliberty\RedpillBundle\ApiClient\Infra\Client\ParameterizedClientFactory', 'createAuthJwtApiClient']
    arguments:
        $tokenError: '@Eliberty\RedpillBundle\ApiClient\Infra\Error\Token\StatusCodeTokenError'
        $apiParams:
            login_data_key: json
            response_token_key: access_token
            cache_keys_excluded: ['password']
        $apiConfigParams:
            base_uri:    [booking.v2.api_base_url]
            main_uri:    [booking.v2.api_base_url]
            login_uri:   [booking.v2.login_url]
            credentials: [booking.v2.credentials]

# Decorator that injects x-tenant-slag from ConfigManager.
Eliberty\RedpillBundle\ApiClient\ElibertyBookingV2\Client\ElibertyBookingV2ApiClient:
    arguments:
        $authClient: '@eliberty_booking_v2.api.client.jwt.authenticated'
        $configManager: '@Eliberty\ConfigManagerBundle\Model\ConfigManager'

# Repository — exposed to the handler.
Eliberty\RedpillBundle\ApiClient\ElibertyBookingV2\Repository\BookingV2Repository:
    arguments:
        $bookingV2ApiClient: '@Eliberty\RedpillBundle\ApiClient\ElibertyBookingV2\Client\ElibertyBookingV2ApiClient'

# ApiHelper (extends existing BaseApiHelper, picks up its bindings).
Eliberty\RedpillBundle\ExternalActivity\ElibertyBookingV2\Rest\ApiHelper: ~

# Handler — auto-tagged because of the existing
# `ExternalActivityHandlerInterface: tags: [external_activity.handler]`
# entry; the GenericTagCompilerPass adds it to the factory.
Eliberty\RedpillBundle\ExternalActivity\ElibertyBookingV2\Rest\ElibertyBookingV2Handler: ~
```

The handler service ID MUST be the FQCN above so the existing `ExternalActivityHandlerFactory::getServiceId('eliberty_booking_v2')` resolution works. Name conversion: `'eliberty_booking_v2'` → `'ElibertyBookingV2'` → `Eliberty\RedpillBundle\ExternalActivity\ElibertyBookingV2\Rest\ElibertyBookingV2Handler`.

## Existing utilities to reuse (do NOT reimplement)

- `Eliberty\RedpillBundle\ApiClient\Infra\Client\AuthJwtApiClient` — JWT login + Redis token cache + 401 retry. Configured via `ParameterizedClientFactory::createAuthJwtApiClient`.
- `Eliberty\RedpillBundle\ApiClient\Infra\Client\ParameterizedClientFactory` — service factory.
- `Eliberty\RedpillBundle\ApiClient\Infra\Token\{RedisApiToken, JwtToken}` — token storage with TTL parsed from the JWT `exp` claim.
- `Eliberty\RedpillBundle\ApiClient\Infra\Error\Token\StatusCodeTokenError` — `401 → re-login` strategy. The new API does not document a richer error envelope, so plain status-code matching is sufficient. If smoke tests show false positives we can add a dedicated `ElibertyBookingV2TokenError` later.
- `Eliberty\RedpillBundle\ExternalActivity\Helpers\BaseApiHelper` — booker fallback chain, redis key builder, cache TTL, logger.
- `Eliberty\RedpillBundle\ExternalActivity\Models\{SubContingent, ExternalBooking, SubContingentData}` — funnel data carriers.
- `Eliberty\RedpillBundle\ExternalActivity\ExternalActivityHandlerFactory` — auto-resolves the handler by class name.
- `Eliberty\RedpillBundle\Entity\Season::getCurrentSeason()` — date range for availability.
- `@generic_cache` (`Psr\SimpleCache\CacheInterface`) — bound as `$redisCache`.
- `@monolog.logger.booking` — bound as `$loggerBooking`.

## Build sequence

1. **Enum entry** — add `ELIBERTY_BOOKING_V2` to `ExternalBookingProvider`.
2. **Decorator client** `ElibertyBookingV2ApiClient` + unit test (assert header injected, assert delegation, assert decorator preserves caller-supplied options).
3. **Service wiring** for the JWT client + decorator (via `ParameterizedClientFactory`). Verify with a small functional bootstrap test that the container compiles.
4. **`BookingV2Repository`** + unit test (mock `ApiClientInterface`, assert correct method/uri/options on each call, assert response data is forwarded).
5. **`ApiHelper`** + unit test for each mapping function with fixture arrays.
6. **`ElibertyBookingV2Handler`** — implement methods one at a time, each with a focused unit test that mocks `BookingV2Repository`. Mirror the structure of `tests/Unit/Eliberty/RedpillBundle/ApiClient/IoMedia/BenefitApiClientTest.php` for the mocking style.
7. **Extend `ExternalActivityHandlerFactoryTest`** to assert `getHandler('eliberty_booking_v2')` resolves the new class.
8. **Run quality gates**: `composer cs-fix && composer stan && composer ci:tests:unit`.

## Verification

```bash
docker compose exec redpill php vendor/bin/phpunit --configuration config/phpunit.xml.dist \
  --filter ElibertyBookingV2

docker compose exec redpill php vendor/bin/php-cs-fixer fix --config=.php-cs-fixer.dist.php --dry-run --diff \
  src/RedpillBundle/ExternalActivity/ElibertyBookingV2 \
  src/RedpillBundle/ApiClient/ElibertyBookingV2

docker compose exec redpill php vendor/bin/phpstan analyse -c phpstan.neon.dist -l 1 \
  src/RedpillBundle/ExternalActivity/ElibertyBookingV2 \
  src/RedpillBundle/ApiClient/ElibertyBookingV2
```

End-to-end smoke (manual, on a dev tenant configured with the v2 keys):

1. Set `booking.v2.*` keys in ConfigManager for a dev webinstance (`tenant-slag`, `api_base_url`, `login_url`, `credentials`).
2. Mark a test product `externalBookingProvider = 'eliberty_booking_v2'` and set its `externalActivityResourceId` to a real `resourceUuid`.
3. Call the funnel that lists availabilities (existing controller calling `BookingService`) — confirm timeslots come back and `SubContingent` rows are persisted with `type = eliberty_booking_v2`. Inspect Redis for the cached JWT token under the AuthJwtApiClient hash key.
4. Add the product to a cart → confirm `POST /client/booking/{uuid}` is hit, `ExternalBooking` row created with status `INIT`.
5. Trigger sync (cart refresh) → confirm `/prebook/extend/...` call.
6. Pay the order → confirm `/prebook/confirm/...` call and status flips to `CONFIRMED`.
7. Force a 401 (delete the cached token in Redis) → confirm `AuthJwtApiClient` re-logins transparently and the next call succeeds.

## Open items to flag during implementation

- `currency = 'EUR'` is hardcoded; surface a TODO if any tenant uses another currency.
- The new API has no `findBooking` by ID endpoint; if the funnel ever needs to recover a lost booking remotely this becomes a follow-up.
- `customerUserId = (string) $order->getId()`. If the v2 backend expects a stable cross-system identifier, revisit during smoke test.
- If the booking module returns 401 with a richer error body, swap `StatusCodeTokenError` for a dedicated `ElibertyBookingV2TokenError` strategy (one new class, one services.yml line).
