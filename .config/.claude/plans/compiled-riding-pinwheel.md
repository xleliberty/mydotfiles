# Xsalto PDS Fidelity API Importer — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a PHP CLI tool that authenticates against the Xsalto PDS API, paginates over all contacts, and upserts each record into a PostgreSQL database while tracking downloaded pages for safe retry.

**Architecture:** A thin CLI entry point (`bin/import.php`) wires together an API client (Symfony HTTP Client), a mapper (pure data transform), a contact repository (Doctrine DBAL upsert), and a page tracker (records completed offsets) — all orchestrated by a `ContactImporter` loop.

**Tech Stack:** PHP 8.1+, Doctrine DBAL 4.4 (PostgreSQL), Symfony HTTP Client 8.0, PHPUnit 11 (tests)

---

## File Map

| File | Responsibility |
|------|---------------|
| `database/schema.sql` | Create `xsalto_fidelity` DB, `contacts` and `pages` tables |
| `composer.json` | Add PHPUnit dev dep + autoload-dev for tests |
| `phpunit.xml` | PHPUnit bootstrap config |
| `src/Config/DatabaseConfig.php` | Build Doctrine DBAL Connection from `$_ENV` |
| `src/ApiClient/XsaltoApiClient.php` | Login + paginated GET /api/contacts |
| `src/Mapper/ContactMapper.php` | Map one API contact array → DB row array |
| `src/Database/ContactRepository.php` | UPSERT a row into `contacts` |
| `src/Database/PageTracker.php` | Check/mark pages as downloaded |
| `src/Importer/ContactImporter.php` | Loop pages, skip downloaded, save contacts |
| `bin/import.php` | CLI entry point: load .env, wire deps, run |
| `.env.example` | Template for credentials/config |
| `tests/Mapper/ContactMapperTest.php` | Unit tests for mapper (no I/O) |

---

## Task 1: Database Schema

**Files:**
- Create: `database/schema.sql`

- [ ] **Step 1: Create schema file**

```sql
-- database/schema.sql
-- Run as superuser:  psql -U postgres -f database/schema.sql

CREATE DATABASE xsalto_fidelity;

\c xsalto_fidelity;

CREATE TABLE IF NOT EXISTS contacts (
    id          VARCHAR(50)  PRIMARY KEY,
    lastname    VARCHAR(255),
    firstname   VARCHAR(255),
    email       VARCHAR(255),
    address1    VARCHAR(255),
    address2    VARCHAR(255),
    address3    VARCHAR(255),
    zipcode     VARCHAR(20),
    city        VARCHAR(255),
    country     VARCHAR(10),
    balance     INTEGER,
    lastmove    TIMESTAMP,
    language    VARCHAR(10),
    skiers      JSONB,
    resorts     JSONB,
    created     TIMESTAMP
);

CREATE TABLE IF NOT EXISTS pages (
    offset       INTEGER      PRIMARY KEY,
    size         INTEGER      NOT NULL DEFAULT 100,
    downloaded_at TIMESTAMP   NOT NULL DEFAULT NOW(),
    record_count INTEGER,
    status       VARCHAR(20)  NOT NULL DEFAULT 'completed'
);
```

- [ ] **Step 2: Apply schema**

```bash
psql -U postgres -f database/schema.sql
```
Expected: `CREATE DATABASE`, `CREATE TABLE`, `CREATE TABLE` — no errors.

- [ ] **Step 3: Commit**

```bash
git add database/schema.sql
git commit -m "feat: add postgresql schema for contacts and pages tables"
```

---

## Task 2: Project Setup (PHPUnit)

**Files:**
- Modify: `composer.json`
- Create: `phpunit.xml`

- [ ] **Step 1: Add PHPUnit and autoload-dev to composer.json**

Replace the existing `composer.json` with:

```json
{
    "name": "xav/xsalto-pds-fid",
    "type": "project",
    "require": {
        "doctrine/dbal": "^4.4",
        "symfony/http-client": "^8.0"
    },
    "require-dev": {
        "phpunit/phpunit": "^11"
    },
    "autoload": {
        "psr-4": {
            "Xav\\XsaltoPdsFid\\": "src/"
        }
    },
    "autoload-dev": {
        "psr-4": {
            "Xav\\XsaltoPdsFid\\Tests\\": "tests/"
        }
    },
    "authors": [
        {
            "name": "Xavier LEMBO",
            "email": "xavier.lembo@eliberty.fr"
        }
    ]
}
```

- [ ] **Step 2: Install dependencies**

```bash
composer install
```
Expected: PHPUnit installed under `vendor/phpunit/`.

- [ ] **Step 3: Create phpunit.xml**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<phpunit xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:noNamespaceSchemaLocation="vendor/phpunit/phpunit/phpunit.xsd"
         bootstrap="vendor/autoload.php"
         colors="true">
    <testsuites>
        <testsuite name="Unit">
            <directory>tests</directory>
        </testsuite>
    </testsuites>
    <source>
        <include>
            <directory>src</directory>
        </include>
    </source>
</phpunit>
```

- [ ] **Step 4: Commit**

```bash
git add composer.json composer.lock phpunit.xml
git commit -m "feat: add phpunit and test autoloading"
```

---

## Task 3: ContactMapper (TDD)

**Files:**
- Create: `src/Mapper/ContactMapper.php`
- Create: `tests/Mapper/ContactMapperTest.php`

- [ ] **Step 1: Write the failing tests**

```php
<?php
// tests/Mapper/ContactMapperTest.php
namespace Xav\XsaltoPdsFid\Tests\Mapper;

use PHPUnit\Framework\TestCase;
use Xav\XsaltoPdsFid\Mapper\ContactMapper;

class ContactMapperTest extends TestCase
{
    private ContactMapper $mapper;

    protected function setUp(): void
    {
        $this->mapper = new ContactMapper();
    }

    public function testMapsBasicContactAttributes(): void
    {
        $contact = [
            'id' => '6q85iaor8ayw',
            'attributes' => [
                'LastName'  => 'STONE',
                'FirstName' => 'LUKE',
                'Email'     => 'luke_stone@hotmail.com',
                'Address1'  => '60 Long Garden Walk',
                'Address2'  => null,
                'Address3'  => null,
                'ZipCode'   => 'GU9 7HX',
                'City'      => 'Farnham',
                'Language'  => null,
                'LASTMOVE'  => '2026-03-28 10:13:06',
                'Balance'   => 360,
                'created'   => '2019-03-30 10:08:43',
            ],
            'relationships' => [
                'Country' => ['data' => ['type' => 'countries', 'id' => 'CH']],
                'Resorts' => ['data' => [['type' => 'resorts', 'id' => 'LesGets']]],
                'skiers'  => ['data' => []],
            ],
        ];

        $row = $this->mapper->mapToRow($contact);

        $this->assertSame('6q85iaor8ayw', $row['id']);
        $this->assertSame('STONE', $row['lastname']);
        $this->assertSame('LUKE', $row['firstname']);
        $this->assertSame('luke_stone@hotmail.com', $row['email']);
        $this->assertSame('60 Long Garden Walk', $row['address1']);
        $this->assertNull($row['address2']);
        $this->assertSame('GU9 7HX', $row['zipcode']);
        $this->assertSame('Farnham', $row['city']);
        $this->assertSame('CH', $row['country']);
        $this->assertSame(360, $row['balance']);
        $this->assertSame('2026-03-28 10:13:06', $row['lastmove']);
        $this->assertNull($row['language']);
        $this->assertSame('2019-03-30 10:08:43', $row['created']);
    }

    public function testMapsResortsAsJson(): void
    {
        $contact = [
            'id' => 'test-id',
            'attributes' => [],
            'relationships' => [
                'Resorts' => ['data' => [['type' => 'resorts', 'id' => 'LesGets']]],
                'skiers'  => ['data' => []],
            ],
        ];

        $row = $this->mapper->mapToRow($contact);

        $this->assertSame('[{"type":"resorts","id":"LesGets"}]', $row['resorts']);
    }

    public function testMapsSkiersAsJson(): void
    {
        $skierData = [['id' => 'skier1', 'attributes' => ['LastName' => 'STONE']]];
        $contact = [
            'id' => 'test-id',
            'attributes' => [],
            'relationships' => ['skiers' => ['data' => $skierData]],
        ];

        $row = $this->mapper->mapToRow($contact);

        $this->assertSame(json_encode($skierData), $row['skiers']);
    }

    public function testHandlesMissingRelationships(): void
    {
        $contact = [
            'id' => 'test-id',
            'attributes' => ['Balance' => '150'],
            'relationships' => [],
        ];

        $row = $this->mapper->mapToRow($contact);

        $this->assertNull($row['country']);
        $this->assertNull($row['resorts']);
        $this->assertNull($row['skiers']);
        $this->assertSame(150, $row['balance']);
    }
}
```

- [ ] **Step 2: Run tests — verify they FAIL**

```bash
vendor/bin/phpunit tests/Mapper/ContactMapperTest.php
```
Expected: `Error: Class "Xav\XsaltoPdsFid\Mapper\ContactMapper" not found`

- [ ] **Step 3: Implement ContactMapper**

```php
<?php
// src/Mapper/ContactMapper.php
namespace Xav\XsaltoPdsFid\Mapper;

class ContactMapper
{
    public function mapToRow(array $contact): array
    {
        $attr = $contact['attributes'] ?? [];
        $rels = $contact['relationships'] ?? [];

        return [
            'id'        => $contact['id'],
            'lastname'  => $attr['LastName'] ?? null,
            'firstname' => $attr['FirstName'] ?? null,
            'email'     => $attr['Email'] ?? null,
            'address1'  => $attr['Address1'] ?? null,
            'address2'  => $attr['Address2'] ?? null,
            'address3'  => $attr['Address3'] ?? null,
            'zipcode'   => $attr['ZipCode'] ?? null,
            'city'      => $attr['City'] ?? null,
            'country'   => $rels['Country']['data']['id'] ?? null,
            'balance'   => isset($attr['Balance']) ? (int) $attr['Balance'] : null,
            'lastmove'  => $attr['LASTMOVE'] ?? null,
            'language'  => $attr['Language'] ?? null,
            'skiers'    => isset($rels['skiers']['data']) ? json_encode($rels['skiers']['data']) : null,
            'resorts'   => isset($rels['Resorts']['data']) ? json_encode($rels['Resorts']['data']) : null,
            'created'   => $attr['created'] ?? null,
        ];
    }
}
```

- [ ] **Step 4: Run tests — verify they PASS**

```bash
vendor/bin/phpunit tests/Mapper/ContactMapperTest.php
```
Expected: `OK (4 tests, 17 assertions)`

- [ ] **Step 5: Commit**

```bash
git add src/Mapper/ContactMapper.php tests/Mapper/ContactMapperTest.php
git commit -m "feat: add ContactMapper with unit tests"
```

---

## Task 4: DatabaseConfig

**Files:**
- Create: `src/Config/DatabaseConfig.php`

- [ ] **Step 1: Implement DatabaseConfig**

```php
<?php
// src/Config/DatabaseConfig.php
namespace Xav\XsaltoPdsFid\Config;

use Doctrine\DBAL\Connection;
use Doctrine\DBAL\DriverManager;

class DatabaseConfig
{
    public static function createConnection(): Connection
    {
        return DriverManager::getConnection([
            'driver'   => 'pdo_pgsql',
            'host'     => $_ENV['DB_HOST'] ?? 'localhost',
            'port'     => (int) ($_ENV['DB_PORT'] ?? 5432),
            'dbname'   => $_ENV['DB_NAME'] ?? 'xsalto_fidelity',
            'user'     => $_ENV['DB_USER'] ?? 'postgres',
            'password' => $_ENV['DB_PASSWORD'] ?? '',
        ]);
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add src/Config/DatabaseConfig.php
git commit -m "feat: add DatabaseConfig for Doctrine DBAL connection"
```

---

## Task 5: ContactRepository

**Files:**
- Create: `src/Database/ContactRepository.php`

- [ ] **Step 1: Implement ContactRepository**

```php
<?php
// src/Database/ContactRepository.php
namespace Xav\XsaltoPdsFid\Database;

use Doctrine\DBAL\Connection;

class ContactRepository
{
    public function __construct(private readonly Connection $connection) {}

    public function upsert(array $row): void
    {
        $sql = <<<SQL
            INSERT INTO contacts
                (id, lastname, firstname, email, address1, address2, address3,
                 zipcode, city, country, balance, lastmove, language, skiers, resorts, created)
            VALUES
                (:id, :lastname, :firstname, :email, :address1, :address2, :address3,
                 :zipcode, :city, :country, :balance, :lastmove, :language,
                 :skiers::jsonb, :resorts::jsonb, :created)
            ON CONFLICT (id) DO UPDATE SET
                lastname  = EXCLUDED.lastname,
                firstname = EXCLUDED.firstname,
                email     = EXCLUDED.email,
                address1  = EXCLUDED.address1,
                address2  = EXCLUDED.address2,
                address3  = EXCLUDED.address3,
                zipcode   = EXCLUDED.zipcode,
                city      = EXCLUDED.city,
                country   = EXCLUDED.country,
                balance   = EXCLUDED.balance,
                lastmove  = EXCLUDED.lastmove,
                language  = EXCLUDED.language,
                skiers    = EXCLUDED.skiers,
                resorts   = EXCLUDED.resorts,
                created   = EXCLUDED.created
        SQL;

        $this->connection->executeStatement($sql, $row);
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add src/Database/ContactRepository.php
git commit -m "feat: add ContactRepository with upsert logic"
```

---

## Task 6: PageTracker

**Files:**
- Create: `src/Database/PageTracker.php`

- [ ] **Step 1: Implement PageTracker**

```php
<?php
// src/Database/PageTracker.php
namespace Xav\XsaltoPdsFid\Database;

use Doctrine\DBAL\Connection;

class PageTracker
{
    public function __construct(private readonly Connection $connection) {}

    public function isDownloaded(int $offset, int $size): bool
    {
        $count = $this->connection->fetchOne(
            'SELECT COUNT(*) FROM pages WHERE offset = :offset AND size = :size AND status = :status',
            ['offset' => $offset, 'size' => $size, 'status' => 'completed']
        );
        return (int) $count > 0;
    }

    public function markDownloaded(int $offset, int $size, int $recordCount): void
    {
        $this->connection->executeStatement(
            'INSERT INTO pages (offset, size, downloaded_at, record_count, status)
             VALUES (:offset, :size, NOW(), :record_count, :status)
             ON CONFLICT (offset) DO UPDATE SET
                size          = EXCLUDED.size,
                downloaded_at = NOW(),
                record_count  = EXCLUDED.record_count,
                status        = EXCLUDED.status',
            ['offset' => $offset, 'size' => $size, 'record_count' => $recordCount, 'status' => 'completed']
        );
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add src/Database/PageTracker.php
git commit -m "feat: add PageTracker to record downloaded pages"
```

---

## Task 7: XsaltoApiClient

**Files:**
- Create: `src/ApiClient/XsaltoApiClient.php`

- [ ] **Step 1: Implement XsaltoApiClient**

```php
<?php
// src/ApiClient/XsaltoApiClient.php
namespace Xav\XsaltoPdsFid\ApiClient;

use Symfony\Component\HttpClient\HttpClient;
use Symfony\Contracts\HttpClient\HttpClientInterface;

class XsaltoApiClient
{
    private readonly HttpClientInterface $client;
    private ?string $token = null;

    public function __construct(private readonly string $baseUrl = 'https://pds.xsalto.com')
    {
        $this->client = HttpClient::create();
    }

    public function login(string $login, string $password): void
    {
        $response = $this->client->request('GET', $this->baseUrl . '/api/login', [
            'query' => ['login' => $login, 'password' => $password],
        ]);

        $data = $response->toArray();
        $this->token = $data['data']['token'];
    }

    public function getContacts(int $offset, int $size = 100): array
    {
        if ($this->token === null) {
            throw new \RuntimeException('Not authenticated. Call login() first.');
        }

        $response = $this->client->request('GET', $this->baseUrl . '/api/contacts', [
            'headers' => ['Authorization' => 'Bearer ' . $this->token],
            'query'   => ['page[size]' => $size, 'page[offset]' => $offset],
        ]);

        return $response->toArray();
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add src/ApiClient/XsaltoApiClient.php
git commit -m "feat: add XsaltoApiClient for login and paginated contacts"
```

---

## Task 8: ContactImporter

**Files:**
- Create: `src/Importer/ContactImporter.php`

- [ ] **Step 1: Implement ContactImporter**

```php
<?php
// src/Importer/ContactImporter.php
namespace Xav\XsaltoPdsFid\Importer;

use Xav\XsaltoPdsFid\ApiClient\XsaltoApiClient;
use Xav\XsaltoPdsFid\Database\ContactRepository;
use Xav\XsaltoPdsFid\Database\PageTracker;
use Xav\XsaltoPdsFid\Mapper\ContactMapper;

class ContactImporter
{
    public function __construct(
        private readonly XsaltoApiClient    $apiClient,
        private readonly ContactRepository  $contactRepository,
        private readonly PageTracker        $pageTracker,
        private readonly ContactMapper      $mapper,
        private readonly int                $pageSize = 100,
    ) {}

    public function import(): void
    {
        $offset = 0;

        do {
            if ($this->pageTracker->isDownloaded($offset, $this->pageSize)) {
                echo "Skipping offset={$offset} (already downloaded)\n";
                $offset += $this->pageSize;
                // We don't know if there's a next page without fetching, so continue
                // until we hit a page that wasn't skipped and has no next link.
                continue;
            }

            $response = $this->apiClient->getContacts($offset, $this->pageSize);
            $contacts = $response['data'];

            foreach ($contacts as $contact) {
                $row = $this->mapper->mapToRow($contact);
                $this->contactRepository->upsert($row);
            }

            $this->pageTracker->markDownloaded($offset, $this->pageSize, count($contacts));
            echo "Imported offset={$offset}: " . count($contacts) . " contacts\n";

            $offset += $this->pageSize;
            $hasNext = isset($response['links']['next']) && count($contacts) > 0;
        } while ($hasNext ?? true);
    }
}
```

- [ ] **Step 2: Commit**

```bash
git add src/Importer/ContactImporter.php
git commit -m "feat: add ContactImporter orchestrating pagination and upsert"
```

---

## Task 9: CLI Entry Point and Environment Config

**Files:**
- Create: `bin/import.php`
- Create: `.env.example`

- [ ] **Step 1: Create .env.example**

```bash
# .env.example
API_BASE_URL=https://pds.xsalto.com
API_LOGIN=AVORIAZ
API_PASSWORD=Avoriaz@2026
DB_HOST=localhost
DB_PORT=5432
DB_NAME=xsalto_fidelity
DB_USER=postgres
DB_PASSWORD=
PAGE_SIZE=100
```

- [ ] **Step 2: Copy to .env and fill in real values**

```bash
cp .env.example .env
# Edit .env with actual DB password if needed
```

- [ ] **Step 3: Create bin/import.php**

```php
<?php
// bin/import.php
require __DIR__ . '/../vendor/autoload.php';

// Minimal .env loader (no extra dependencies)
if (file_exists(__DIR__ . '/../.env')) {
    foreach (file(__DIR__ . '/../.env', FILE_IGNORE_NEW_LINES | FILE_SKIP_EMPTY_LINES) as $line) {
        if (str_starts_with(trim($line), '#') || !str_contains($line, '=')) {
            continue;
        }
        [$key, $value] = explode('=', $line, 2);
        $_ENV[trim($key)] = trim($value);
    }
}

use Xav\XsaltoPdsFid\ApiClient\XsaltoApiClient;
use Xav\XsaltoPdsFid\Config\DatabaseConfig;
use Xav\XsaltoPdsFid\Database\ContactRepository;
use Xav\XsaltoPdsFid\Database\PageTracker;
use Xav\XsaltoPdsFid\Importer\ContactImporter;
use Xav\XsaltoPdsFid\Mapper\ContactMapper;

$apiClient = new XsaltoApiClient($_ENV['API_BASE_URL'] ?? 'https://pds.xsalto.com');
$apiClient->login($_ENV['API_LOGIN'], $_ENV['API_PASSWORD']);

$connection = DatabaseConfig::createConnection();

$importer = new ContactImporter(
    $apiClient,
    new ContactRepository($connection),
    new PageTracker($connection),
    new ContactMapper(),
    (int) ($_ENV['PAGE_SIZE'] ?? 100),
);

$importer->import();
```

- [ ] **Step 4: Commit**

```bash
git add bin/import.php .env.example
git commit -m "feat: add CLI entry point and env configuration template"
```

---

## Verification

### Unit tests
```bash
vendor/bin/phpunit
```
Expected: `OK (4 tests, 17 assertions)`

### Full end-to-end run
```bash
# 1. Apply schema (once)
psql -U postgres -f database/schema.sql

# 2. Run importer
php bin/import.php
```
Expected output (truncated):
```
Imported offset=0: 100 contacts
Imported offset=100: 100 contacts
...
```

### Verify data in PostgreSQL
```sql
\c xsalto_fidelity
SELECT COUNT(*) FROM contacts;
SELECT COUNT(*) FROM pages;
SELECT id, lastname, firstname, country, balance FROM contacts LIMIT 5;
SELECT * FROM pages ORDER BY offset;
```

### Re-run for retry/resume
```bash
php bin/import.php
```
Expected: already-downloaded pages show `Skipping offset=N`, fresh pages are imported.
