# F1 Race Countdown Dashboard — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a McLaren-themed F1 countdown dashboard with live session tracking, standings, race calendar, weather, and results — deployed on Unraid via Docker.

**Architecture:** Express + TypeScript backend proxies OpenF1/Jolpica/Open-Meteo APIs with MySQL caching and permanent race archiving. React + Vite + TypeScript frontend renders a single-page carbon-fiber HUD dashboard. Single Docker container on port 1950.

**Tech Stack:** Node 20, Express, React 18, Vite 5, TypeScript, mysql2, node-cron, Google Fonts (Orbitron, Barlow Condensed, DM Mono)

**APIs:**
- OpenF1 (`https://api.openf1.org/v1/`) — sessions, meetings, session results, live detection
- Jolpica (`https://api.jolpi.ca/ergast/f1/`) — driver standings, constructor standings, race results, schedule with circuit lat/lng
- Open-Meteo (`https://api.open-meteo.com/v1/forecast`) — weather by lat/lng (free, no key)

**MySQL:** Host `192.168.1.103:3306`, user `mainUser`, schema `` `JT-F1` ``

---

## Phase 1: Project Foundation

### Task 1: Root Workspace & Package Setup

**Files:**
- Create: `package.json` (root workspace)
- Modify: `src/server/package.json`
- Create: `src/server/tsconfig.json`
- Modify: `src/client/package.json`
- Create: `src/client/tsconfig.json`
- Create: `src/client/vite.config.ts`
- Modify: `.env.example`
- Create: `.env`
- Modify: `.gitignore`

**Step 1: Create root package.json with npm workspaces**

```json
{
  "name": "f1-dashboard",
  "private": true,
  "workspaces": ["src/server", "src/client"],
  "scripts": {
    "dev:server": "npm run dev --workspace=src/server",
    "dev:client": "npm run dev --workspace=src/client",
    "build:client": "npm run build --workspace=src/client",
    "build:server": "npm run build --workspace=src/server",
    "build": "npm run build:client && npm run build:server",
    "start": "npm run start --workspace=src/server"
  }
}
```

**Step 2: Create server package.json**

```json
{
  "name": "f1-server",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "dev": "tsx watch src/index.ts",
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "express": "^4.21.0",
    "mysql2": "^3.11.0",
    "node-cron": "^3.0.3",
    "cors": "^2.8.5"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/node": "^20.14.0",
    "@types/cors": "^2.8.17",
    "@types/node-cron": "^3.0.11",
    "tsx": "^4.19.0",
    "typescript": "^5.5.0"
  }
}
```

**Step 3: Create server tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "commonjs",
    "lib": ["ES2022"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
```

**Step 4: Create client package.json**

```json
{
  "name": "f1-client",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview"
  },
  "dependencies": {
    "react": "^18.3.0",
    "react-dom": "^18.3.0"
  },
  "devDependencies": {
    "@types/react": "^18.3.0",
    "@types/react-dom": "^18.3.0",
    "@vitejs/plugin-react": "^4.3.0",
    "typescript": "^5.5.0",
    "vite": "^5.4.0"
  }
}
```

**Step 5: Create client tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "isolatedModules": true,
    "moduleDetection": "force",
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true
  },
  "include": ["src"]
}
```

**Step 6: Create client vite.config.ts**

```typescript
import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    proxy: {
      '/api': {
        target: 'http://localhost:1950',
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
  },
});
```

**Step 7: Update .env.example and create .env**

`.env.example`:
```env
PORT=1950
NODE_ENV=development

# MySQL (Unraid)
DB_HOST=192.168.1.103
DB_PORT=3306
DB_USER=mainUser
DB_PASS=mainPass
DB_NAME=JT-F1
```

`.env` — same contents with real values (already gitignored).

**Step 8: Update .gitignore — add `node_modules/`, `dist/`, `.env`, `*.log`**

**Step 9: Install dependencies**

```bash
cd f1-website && npm install
```

**Step 10: Commit**

```bash
git add -A && git commit -m "chore: project scaffolding with npm workspaces, vite, and typescript configs"
```

---

### Task 2: Shared Types

**Files:**
- Modify: `src/shared/types/index.ts`

**Step 1: Write shared type definitions used by both client and server**

```typescript
// ---- API Response Types ----

export interface F1Session {
  session_key: number;
  session_name: string;
  session_type: string; // 'Practice' | 'Qualifying' | 'Race' | 'Sprint' etc.
  date_start: string;   // ISO date
  date_end: string;
  meeting_key: number;
  circuit_short_name: string;
  country_name: string;
  country_code: string;
  location: string;
  year: number;
}

export interface F1Meeting {
  meeting_key: number;
  meeting_name: string;
  meeting_official_name: string;
  circuit_key: number;
  circuit_short_name: string;
  country_name: string;
  country_code: string;
  date_start: string;
  date_end: string;
  location: string;
  year: number;
}

export interface DriverStanding {
  position: number;
  points: number;
  wins: number;
  driverCode: string;
  driverNumber: string;
  givenName: string;
  familyName: string;
  nationality: string;
  constructorName: string;
  constructorId: string;
}

export interface ConstructorStanding {
  position: number;
  points: number;
  wins: number;
  constructorId: string;
  constructorName: string;
  nationality: string;
}

export interface RaceResult {
  position: number;
  driverCode: string;
  driverNumber: string;
  givenName: string;
  familyName: string;
  constructorName: string;
  constructorId: string;
  grid: number;
  laps: number;
  status: string;
  time: string | null;
  points: number;
}

export interface RaceWeekend {
  season: string;
  round: number;
  raceName: string;
  circuitName: string;
  circuitId: string;
  country: string;
  locality: string;
  lat: string;
  lng: string;
  raceDate: string;
  raceTime: string;
  sessions: {
    fp1?: { date: string; time: string };
    fp2?: { date: string; time: string };
    fp3?: { date: string; time: string };
    qualifying?: { date: string; time: string };
    sprint?: { date: string; time: string };
  };
  isCompleted: boolean;
}

export interface CircuitWeather {
  temperature: number;
  windSpeed: number;
  windDirection: number;
  weatherCode: number;
  isDay: boolean;
  humidity: number;
}

// ---- Dashboard API Responses ----

export interface NextSessionResponse {
  session: F1Session | null;
  meeting: F1Meeting | null;
  isLive: boolean;
}

export interface CalendarResponse {
  races: RaceWeekend[];
}

export interface StandingsResponse<T> {
  season: string;
  standings: T[];
}

export interface ResultsResponse {
  raceName: string;
  round: number;
  circuitName: string;
  date: string;
  results: RaceResult[];
}

export interface WeatherResponse {
  circuitName: string;
  weather: CircuitWeather;
}

// ---- Circuit Static Data ----

export interface CircuitInfo {
  circuitId: string;
  name: string;
  country: string;
  lat: number;
  lng: number;
  lapCount: number;
  lapRecord: string;
  lapRecordHolder: string;
  lapRecordYear: number;
  drsZones: number;
  circuitLength: string; // km
}
```

**Step 2: Commit**

```bash
git add src/shared/types/index.ts && git commit -m "feat: add shared type definitions for F1 dashboard"
```

---

### Task 3: MySQL Connection & Migrations

**Files:**
- Create: `src/server/src/db/connection.ts`
- Create: `src/server/src/db/migrations.ts`

**Step 1: Create MySQL connection pool**

`src/server/src/db/connection.ts`:
```typescript
import mysql from 'mysql2/promise';

let pool: mysql.Pool | null = null;

export function getPool(): mysql.Pool {
  if (!pool) {
    pool = mysql.createPool({
      host: process.env.DB_HOST || '192.168.1.103',
      port: parseInt(process.env.DB_PORT || '3306', 10),
      user: process.env.DB_USER || 'mainUser',
      password: process.env.DB_PASS || 'mainPass',
      database: process.env.DB_NAME || 'JT-F1',
      waitForConnections: true,
      connectionLimit: 10,
      queueLimit: 0,
    });
  }
  return pool;
}

export async function testConnection(): Promise<boolean> {
  try {
    const db = getPool();
    await db.query('SELECT 1');
    console.log('[DB] MySQL connected successfully');
    return true;
  } catch (err) {
    console.error('[DB] MySQL connection failed:', err);
    return false;
  }
}
```

**Step 2: Create migrations (auto-run on startup)**

`src/server/src/db/migrations.ts`:
```typescript
import { getPool } from './connection';

export async function runMigrations(): Promise<void> {
  const db = getPool();
  console.log('[DB] Running migrations...');

  await db.query(`
    CREATE TABLE IF NOT EXISTS \`api_cache\` (
      \`cache_key\`     VARCHAR(255) NOT NULL PRIMARY KEY,
      \`response_data\` LONGTEXT     NOT NULL,
      \`expires_at\`    DATETIME     NOT NULL,
      \`created_at\`    DATETIME     DEFAULT CURRENT_TIMESTAMP
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS \`race_results\` (
      \`id\`            INT AUTO_INCREMENT PRIMARY KEY,
      \`session_key\`   VARCHAR(50)  NOT NULL,
      \`season_year\`   INT          NOT NULL,
      \`round_number\`  INT          NOT NULL,
      \`race_name\`     VARCHAR(100) NOT NULL,
      \`circuit\`       VARCHAR(100) NOT NULL,
      \`session_type\`  VARCHAR(20)  NOT NULL,
      \`session_date\`  DATETIME     NOT NULL,
      \`position\`      INT,
      \`driver_number\` INT,
      \`driver_code\`   VARCHAR(10),
      \`driver_name\`   VARCHAR(100),
      \`team\`          VARCHAR(100),
      \`finish_time\`   VARCHAR(50),
      \`points\`        DECIMAL(5,2),
      \`laps\`          INT,
      \`grid\`          INT,
      \`status\`        VARCHAR(50),
      \`archived_at\`   DATETIME     DEFAULT CURRENT_TIMESTAMP,
      UNIQUE KEY \`uq_result\` (\`session_key\`, \`driver_number\`)
    )
  `);

  await db.query(`
    CREATE TABLE IF NOT EXISTS \`race_weekends\` (
      \`id\`             INT AUTO_INCREMENT PRIMARY KEY,
      \`season_year\`    INT          NOT NULL,
      \`round_number\`   INT          NOT NULL,
      \`race_name\`      VARCHAR(100) NOT NULL,
      \`circuit\`        VARCHAR(100) NOT NULL,
      \`circuit_id\`     VARCHAR(50),
      \`country\`        VARCHAR(100),
      \`locality\`       VARCHAR(100),
      \`lat\`            VARCHAR(20),
      \`lng\`            VARCHAR(20),
      \`race_date\`      DATETIME     NOT NULL,
      \`sessions_json\`  LONGTEXT,
      \`is_completed\`   BOOLEAN      DEFAULT FALSE,
      UNIQUE KEY \`uq_round\` (\`season_year\`, \`round_number\`)
    )
  `);

  console.log('[DB] Migrations complete');
}
```

**Step 3: Commit**

```bash
git add src/server/src/db/ && git commit -m "feat: MySQL connection pool and schema migrations"
```

---

## Phase 2: Backend Services

### Task 4: Cache Service

**Files:**
- Create: `src/server/src/services/cache.ts`

**Step 1: Implement MySQL-backed cache with TTL**

```typescript
import { getPool } from '../db/connection';

export async function getCache<T>(key: string): Promise<T | null> {
  const db = getPool();
  const [rows] = await db.query(
    'SELECT `response_data` FROM `api_cache` WHERE `cache_key` = ? AND `expires_at` > NOW()',
    [key]
  );
  const result = rows as any[];
  if (result.length === 0) return null;
  return JSON.parse(result[0].response_data) as T;
}

export async function setCache(key: string, data: unknown, ttlSeconds: number): Promise<void> {
  const db = getPool();
  const json = JSON.stringify(data);
  await db.query(
    `INSERT INTO \`api_cache\` (\`cache_key\`, \`response_data\`, \`expires_at\`)
     VALUES (?, ?, DATE_ADD(NOW(), INTERVAL ? SECOND))
     ON DUPLICATE KEY UPDATE
       \`response_data\` = VALUES(\`response_data\`),
       \`expires_at\` = VALUES(\`expires_at\`),
       \`created_at\` = NOW()`,
    [key, json, ttlSeconds]
  );
}

export async function clearExpiredCache(): Promise<number> {
  const db = getPool();
  const [result] = await db.query('DELETE FROM `api_cache` WHERE `expires_at` < NOW()');
  return (result as any).affectedRows;
}
```

**Step 2: Commit**

```bash
git add src/server/src/services/cache.ts && git commit -m "feat: MySQL-backed cache service with TTL"
```

---

### Task 5: Circuit Static Data

**Files:**
- Create: `src/server/src/data/circuits.ts`

**Step 1: Create a static lookup table of all current F1 circuits with GPS coordinates, lap count, lap records, and DRS zones**

This is hardcoded reference data. Include all circuits on the 2025/2026 calendar. Each entry matches the `CircuitInfo` type from shared types.

Example entries (include all ~24 circuits):

```typescript
import { CircuitInfo } from '../../../shared/types';

export const CIRCUITS: Record<string, CircuitInfo> = {
  bahrain: {
    circuitId: 'bahrain',
    name: 'Bahrain International Circuit',
    country: 'Bahrain',
    lat: 26.0325,
    lng: 50.5106,
    lapCount: 57,
    lapRecord: '1:31.447',
    lapRecordHolder: 'Pedro de la Rosa',
    lapRecordYear: 2005,
    drsZones: 3,
    circuitLength: '5.412',
  },
  jeddah: {
    circuitId: 'jeddah',
    name: 'Jeddah Corniche Circuit',
    country: 'Saudi Arabia',
    lat: 21.6319,
    lng: 39.1044,
    lapCount: 50,
    lapRecord: '1:30.734',
    lapRecordHolder: 'Max Verstappen',
    lapRecordYear: 2024,
    drsZones: 3,
    circuitLength: '6.174',
  },
  albert_park: {
    circuitId: 'albert_park',
    name: 'Albert Park Circuit',
    country: 'Australia',
    lat: -37.8497,
    lng: 144.968,
    lapCount: 58,
    lapRecord: '1:19.813',
    lapRecordHolder: 'Charles Leclerc',
    lapRecordYear: 2024,
    drsZones: 4,
    circuitLength: '5.278',
  },
  // ... include ALL circuits for the full calendar
  // suzuka, shanghai, miami, imola, monaco, villeneuve,
  // silverstone, spa, hungaroring, zandvoort, monza,
  // baku, marina_bay, americas, interlagos, vegas,
  // lusail, yas_marina, barcelona, spielberg
};

// Map Jolpica circuitId to our lookup key
export function getCircuitInfo(circuitId: string): CircuitInfo | undefined {
  // Jolpica uses IDs like "bahrain", "jeddah", "albert_park"
  // Normalize by replacing hyphens/spaces with underscores and lowercasing
  const key = circuitId.toLowerCase().replace(/[-\s]/g, '_');
  return CIRCUITS[key];
}
```

The implementing engineer should populate ALL circuits with accurate data. Research each circuit's current lap record, DRS zone count, and lap count for the 2025/2026 regulations.

**Step 2: Commit**

```bash
git add src/server/src/data/circuits.ts && git commit -m "feat: static circuit reference data with GPS coords and track info"
```

---

### Task 6: Jolpica API Client (Standings, Schedule, Results)

**Files:**
- Create: `src/server/src/services/jolpica.ts`

**Step 1: Implement the Jolpica/Ergast API client**

```typescript
import {
  DriverStanding,
  ConstructorStanding,
  RaceWeekend,
  RaceResult,
} from '../../../shared/types';
import { getCache, setCache } from './cache';

const BASE = 'https://api.jolpi.ca/ergast/f1';

async function fetchJSON(url: string): Promise<any> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Jolpica API error: ${res.status} ${res.statusText}`);
  return res.json();
}

export async function getDriverStandings(year: number): Promise<DriverStanding[]> {
  const cacheKey = `standings:drivers:${year}`;
  const cached = await getCache<DriverStanding[]>(cacheKey);
  if (cached) return cached;

  const data = await fetchJSON(`${BASE}/${year}/driverStandings.json`);
  const list = data?.MRData?.StandingsTable?.StandingsLists?.[0]?.DriverStandings ?? [];

  const standings: DriverStanding[] = list.map((s: any) => ({
    position: parseInt(s.position, 10),
    points: parseFloat(s.points),
    wins: parseInt(s.wins, 10),
    driverCode: s.Driver.code,
    driverNumber: s.Driver.permanentNumber,
    givenName: s.Driver.givenName,
    familyName: s.Driver.familyName,
    nationality: s.Driver.nationality,
    constructorName: s.Constructors?.[0]?.name ?? '',
    constructorId: s.Constructors?.[0]?.constructorId ?? '',
  }));

  await setCache(cacheKey, standings, 300); // 5 min TTL
  return standings;
}

export async function getConstructorStandings(year: number): Promise<ConstructorStanding[]> {
  const cacheKey = `standings:constructors:${year}`;
  const cached = await getCache<ConstructorStanding[]>(cacheKey);
  if (cached) return cached;

  const data = await fetchJSON(`${BASE}/${year}/constructorStandings.json`);
  const list = data?.MRData?.StandingsTable?.StandingsLists?.[0]?.ConstructorStandings ?? [];

  const standings: ConstructorStanding[] = list.map((s: any) => ({
    position: parseInt(s.position, 10),
    points: parseFloat(s.points),
    wins: parseInt(s.wins, 10),
    constructorId: s.Constructor.constructorId,
    constructorName: s.Constructor.name,
    nationality: s.Constructor.nationality,
  }));

  await setCache(cacheKey, standings, 300);
  return standings;
}

export async function getSchedule(year: number): Promise<RaceWeekend[]> {
  const cacheKey = `schedule:${year}`;
  const cached = await getCache<RaceWeekend[]>(cacheKey);
  if (cached) return cached;

  const data = await fetchJSON(`${BASE}/${year}.json`);
  const races = data?.MRData?.RaceTable?.Races ?? [];

  const schedule: RaceWeekend[] = races.map((r: any) => ({
    season: r.season,
    round: parseInt(r.round, 10),
    raceName: r.raceName,
    circuitName: r.Circuit.circuitName,
    circuitId: r.Circuit.circuitId,
    country: r.Circuit.Location.country,
    locality: r.Circuit.Location.locality,
    lat: r.Circuit.Location.lat,
    lng: r.Circuit.Location.long,
    raceDate: r.date,
    raceTime: r.time || '14:00:00Z',
    sessions: {
      fp1: r.FirstPractice ? { date: r.FirstPractice.date, time: r.FirstPractice.time } : undefined,
      fp2: r.SecondPractice ? { date: r.SecondPractice.date, time: r.SecondPractice.time } : undefined,
      fp3: r.ThirdPractice ? { date: r.ThirdPractice.date, time: r.ThirdPractice.time } : undefined,
      qualifying: r.Qualifying ? { date: r.Qualifying.date, time: r.Qualifying.time } : undefined,
      sprint: r.Sprint ? { date: r.Sprint.date, time: r.Sprint.time } : undefined,
    },
    isCompleted: new Date(`${r.date}T${r.time || '14:00:00Z'}`) < new Date(),
  }));

  await setCache(cacheKey, schedule, 3600); // 1 hour TTL
  return schedule;
}

export async function getRaceResults(year: number, round: number): Promise<RaceResult[]> {
  const cacheKey = `results:${year}:${round}`;
  const cached = await getCache<RaceResult[]>(cacheKey);
  if (cached) return cached;

  const data = await fetchJSON(`${BASE}/${year}/${round}/results.json`);
  const race = data?.MRData?.RaceTable?.Races?.[0];
  if (!race?.Results) return [];

  const results: RaceResult[] = race.Results.map((r: any) => ({
    position: parseInt(r.position, 10),
    driverCode: r.Driver.code,
    driverNumber: r.Driver.permanentNumber,
    givenName: r.Driver.givenName,
    familyName: r.Driver.familyName,
    constructorName: r.Constructor.name,
    constructorId: r.Constructor.constructorId,
    grid: parseInt(r.grid, 10),
    laps: parseInt(r.laps, 10),
    status: r.status,
    time: r.Time?.time ?? null,
    points: parseFloat(r.points),
  }));

  // Cache permanently for completed races (24hr TTL as effectively permanent)
  await setCache(cacheKey, results, 86400);
  return results;
}
```

**Step 2: Commit**

```bash
git add src/server/src/services/jolpica.ts && git commit -m "feat: Jolpica API client for standings, schedule, and results"
```

---

### Task 7: OpenF1 Client (Sessions, Live Detection)

**Files:**
- Create: `src/server/src/services/openf1.ts`

**Step 1: Implement the OpenF1 API client**

```typescript
import { F1Session, F1Meeting } from '../../../shared/types';
import { getCache, setCache } from './cache';

const BASE = 'https://api.openf1.org/v1';

async function fetchJSON(url: string): Promise<any> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`OpenF1 API error: ${res.status} ${res.statusText}`);
  return res.json();
}

export async function getSessions(year: number): Promise<F1Session[]> {
  const cacheKey = `openf1:sessions:${year}`;
  const cached = await getCache<F1Session[]>(cacheKey);
  if (cached) return cached;

  const data = await fetchJSON(`${BASE}/sessions?year=${year}`);
  const sessions: F1Session[] = (data ?? []).map((s: any) => ({
    session_key: s.session_key,
    session_name: s.session_name,
    session_type: s.session_type,
    date_start: s.date_start,
    date_end: s.date_end,
    meeting_key: s.meeting_key,
    circuit_short_name: s.circuit_short_name,
    country_name: s.country_name,
    country_code: s.country_code,
    location: s.location,
    year: s.year,
  }));

  await setCache(cacheKey, sessions, 60); // 1 min TTL
  return sessions;
}

export async function getMeetings(year: number): Promise<F1Meeting[]> {
  const cacheKey = `openf1:meetings:${year}`;
  const cached = await getCache<F1Meeting[]>(cacheKey);
  if (cached) return cached;

  const data = await fetchJSON(`${BASE}/meetings?year=${year}`);
  const meetings: F1Meeting[] = (data ?? []).map((m: any) => ({
    meeting_key: m.meeting_key,
    meeting_name: m.meeting_name,
    meeting_official_name: m.meeting_official_name,
    circuit_key: m.circuit_key,
    circuit_short_name: m.circuit_short_name,
    country_name: m.country_name,
    country_code: m.country_code,
    date_start: m.date_start,
    date_end: m.date_end,
    location: m.location,
    year: m.year,
  }));

  await setCache(cacheKey, meetings, 3600);
  return meetings;
}

/**
 * Find the next upcoming session (or one currently live).
 * Returns { session, meeting, isLive }
 */
export async function getNextSession(year: number) {
  const sessions = await getSessions(year);
  const now = new Date();

  // Sort by date ascending
  const sorted = sessions
    .filter((s) => s.date_start)
    .sort((a, b) => new Date(a.date_start).getTime() - new Date(b.date_start).getTime());

  // Check if any session is LIVE right now
  const live = sorted.find((s) => {
    const start = new Date(s.date_start);
    const end = new Date(s.date_end);
    return now >= start && now <= end;
  });

  if (live) {
    const meetings = await getMeetings(year);
    const meeting = meetings.find((m) => m.meeting_key === live.meeting_key) ?? null;
    return { session: live, meeting, isLive: true };
  }

  // Find next upcoming session
  const next = sorted.find((s) => new Date(s.date_start) > now) ?? null;
  if (next) {
    const meetings = await getMeetings(year);
    const meeting = meetings.find((m) => m.meeting_key === next.meeting_key) ?? null;
    return { session: next, meeting, isLive: false };
  }

  return { session: null, meeting: null, isLive: false };
}

/**
 * Get the next N upcoming sessions across all race weekends.
 */
export async function getUpcomingSessions(year: number, count: number = 5): Promise<F1Session[]> {
  const sessions = await getSessions(year);
  const now = new Date();

  return sessions
    .filter((s) => s.date_start && new Date(s.date_start) > now)
    .sort((a, b) => new Date(a.date_start).getTime() - new Date(b.date_start).getTime())
    .slice(0, count);
}
```

**Step 2: Commit**

```bash
git add src/server/src/services/openf1.ts && git commit -m "feat: OpenF1 API client for sessions and live detection"
```

---

### Task 8: Weather Service

**Files:**
- Create: `src/server/src/services/weather.ts`

**Step 1: Implement Open-Meteo weather client**

```typescript
import { CircuitWeather } from '../../../shared/types';
import { getCache, setCache } from './cache';

const BASE = 'https://api.open-meteo.com/v1/forecast';

export async function getWeather(lat: number, lng: number, circuitId: string): Promise<CircuitWeather> {
  const cacheKey = `weather:${circuitId}`;
  const cached = await getCache<CircuitWeather>(cacheKey);
  if (cached) return cached;

  const url = `${BASE}?latitude=${lat}&longitude=${lng}&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,wind_direction_10m,is_day`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`Open-Meteo error: ${res.status}`);
  const data = await res.json();

  const current = data.current;
  const weather: CircuitWeather = {
    temperature: current.temperature_2m,
    windSpeed: current.wind_speed_10m,
    windDirection: current.wind_direction_10m,
    weatherCode: current.weather_code,
    isDay: current.is_day === 1,
    humidity: current.relative_humidity_2m,
  };

  await setCache(cacheKey, weather, 600); // 10 min TTL
  return weather;
}
```

**Step 2: Commit**

```bash
git add src/server/src/services/weather.ts && git commit -m "feat: Open-Meteo weather service for circuit forecasts"
```

---

### Task 9: Race Result Archiver (Background Job)

**Files:**
- Create: `src/server/src/services/archive.ts`

**Step 1: Implement the background archiver that stores completed race results in MySQL**

```typescript
import { getPool } from '../db/connection';
import { getSchedule, getRaceResults } from './jolpica';

const CURRENT_YEAR = new Date().getFullYear();

/**
 * Checks for any completed races not yet archived, fetches their results
 * from Jolpica, and stores them in MySQL permanently.
 */
export async function archiveCompletedRaces(): Promise<void> {
  const db = getPool();

  try {
    const schedule = await getSchedule(CURRENT_YEAR);
    const now = new Date();

    for (const race of schedule) {
      const raceDateTime = new Date(`${race.raceDate}T${race.raceTime}`);
      if (raceDateTime >= now) continue; // Not completed yet

      // Check if already archived
      const [existing] = await db.query(
        'SELECT 1 FROM `race_weekends` WHERE `season_year` = ? AND `round_number` = ? AND `is_completed` = TRUE',
        [CURRENT_YEAR, race.round]
      );
      if ((existing as any[]).length > 0) continue; // Already archived

      // Upsert race weekend
      await db.query(
        `INSERT INTO \`race_weekends\`
         (\`season_year\`, \`round_number\`, \`race_name\`, \`circuit\`, \`circuit_id\`,
          \`country\`, \`locality\`, \`lat\`, \`lng\`, \`race_date\`, \`sessions_json\`, \`is_completed\`)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, TRUE)
         ON DUPLICATE KEY UPDATE \`is_completed\` = TRUE, \`sessions_json\` = VALUES(\`sessions_json\`)`,
        [
          CURRENT_YEAR, race.round, race.raceName, race.circuitName, race.circuitId,
          race.country, race.locality, race.lat, race.lng,
          raceDateTime, JSON.stringify(race.sessions),
        ]
      );

      // Fetch and archive race results
      try {
        const results = await getRaceResults(CURRENT_YEAR, race.round);
        for (const r of results) {
          await db.query(
            `INSERT INTO \`race_results\`
             (\`session_key\`, \`season_year\`, \`round_number\`, \`race_name\`, \`circuit\`,
              \`session_type\`, \`session_date\`, \`position\`, \`driver_number\`, \`driver_code\`,
              \`driver_name\`, \`team\`, \`finish_time\`, \`points\`, \`laps\`, \`grid\`, \`status\`)
             VALUES (?, ?, ?, ?, ?, 'Race', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON DUPLICATE KEY UPDATE \`position\` = VALUES(\`position\`)`,
            [
              `${CURRENT_YEAR}-R${race.round}`, CURRENT_YEAR, race.round,
              race.raceName, race.circuitName, raceDateTime,
              r.position, r.driverNumber, r.driverCode,
              `${r.givenName} ${r.familyName}`, r.constructorName,
              r.time, r.points, r.laps, r.grid, r.status,
            ]
          );
        }
        console.log(`[Archive] Archived results for Round ${race.round}: ${race.raceName}`);
      } catch (err) {
        console.error(`[Archive] Failed to archive Round ${race.round}:`, err);
      }
    }
  } catch (err) {
    console.error('[Archive] Archiver run failed:', err);
  }
}
```

**Step 2: Commit**

```bash
git add src/server/src/services/archive.ts && git commit -m "feat: background race result archiver for MySQL persistence"
```

---

### Task 10: Express Server & API Routes

**Files:**
- Modify: `src/server/src/index.ts`
- Modify: `src/server/src/routes/api.ts`

**Step 1: Implement the Express server entry point**

`src/server/src/index.ts`:
```typescript
import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import path from 'path';
import cron from 'node-cron';
import { testConnection } from './db/connection';
import { runMigrations } from './db/migrations';
import { archiveCompletedRaces } from './services/archive';
import { clearExpiredCache } from './services/cache';
import apiRouter from './routes/api';

const PORT = parseInt(process.env.PORT || '1950', 10);
const app = express();

app.use(cors());
app.use(express.json());

// API routes
app.use('/api', apiRouter);

// Serve React static files in production
const clientDist = path.join(__dirname, '../../client/dist');
app.use(express.static(clientDist));
app.get('*', (_req, res) => {
  res.sendFile(path.join(clientDist, 'index.html'));
});

async function start() {
  // Connect to MySQL and run migrations
  const connected = await testConnection();
  if (!connected) {
    console.error('[Server] Could not connect to MySQL. Starting without DB features.');
  } else {
    await runMigrations();
  }

  // Background jobs
  // Archive completed races every 30 minutes
  cron.schedule('*/30 * * * *', () => {
    console.log('[Cron] Running race archiver...');
    archiveCompletedRaces();
  });

  // Clear expired cache every hour
  cron.schedule('0 * * * *', () => {
    clearExpiredCache();
  });

  // Run archiver once on startup
  if (connected) {
    archiveCompletedRaces();
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`[Server] F1 Dashboard running on http://0.0.0.0:${PORT}`);
  });
}

start();
```

Note: add `dotenv` to server dependencies: `npm install dotenv --workspace=src/server`

**Step 2: Implement all API routes**

`src/server/src/routes/api.ts`:
```typescript
import { Router, Request, Response } from 'express';
import { getNextSession, getUpcomingSessions } from '../services/openf1';
import {
  getDriverStandings,
  getConstructorStandings,
  getSchedule,
  getRaceResults,
} from '../services/jolpica';
import { getWeather } from '../services/weather';
import { getCircuitInfo, CIRCUITS } from '../data/circuits';
import { getPool } from '../db/connection';

const router = Router();
const YEAR = new Date().getFullYear();

// Health check
router.get('/health', (_req: Request, res: Response) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Next session + countdown data
router.get('/next-session', async (_req: Request, res: Response) => {
  try {
    const data = await getNextSession(YEAR);
    res.json(data);
  } catch (err) {
    console.error('[API] /next-session error:', err);
    res.status(500).json({ error: 'Failed to fetch next session' });
  }
});

// Upcoming sessions (next 5)
router.get('/sessions/upcoming', async (_req: Request, res: Response) => {
  try {
    const sessions = await getUpcomingSessions(YEAR, 5);
    res.json(sessions);
  } catch (err) {
    console.error('[API] /sessions/upcoming error:', err);
    res.status(500).json({ error: 'Failed to fetch upcoming sessions' });
  }
});

// Driver standings
router.get('/standings/drivers', async (_req: Request, res: Response) => {
  try {
    const standings = await getDriverStandings(YEAR);
    res.json({ season: String(YEAR), standings });
  } catch (err) {
    console.error('[API] /standings/drivers error:', err);
    res.status(500).json({ error: 'Failed to fetch driver standings' });
  }
});

// Constructor standings
router.get('/standings/constructors', async (_req: Request, res: Response) => {
  try {
    const standings = await getConstructorStandings(YEAR);
    res.json({ season: String(YEAR), standings });
  } catch (err) {
    console.error('[API] /standings/constructors error:', err);
    res.status(500).json({ error: 'Failed to fetch constructor standings' });
  }
});

// Full calendar (merges Jolpica schedule + MySQL archived race weekends)
router.get('/calendar', async (_req: Request, res: Response) => {
  try {
    const schedule = await getSchedule(YEAR);

    // Check MySQL for completed race status
    try {
      const db = getPool();
      const [rows] = await db.query(
        'SELECT `round_number` FROM `race_weekends` WHERE `season_year` = ? AND `is_completed` = TRUE',
        [YEAR]
      );
      const completedRounds = new Set((rows as any[]).map((r) => r.round_number));
      schedule.forEach((race) => {
        if (completedRounds.has(race.round)) {
          race.isCompleted = true;
        }
      });
    } catch {
      // DB unavailable, use date-based completion check (already set in getSchedule)
    }

    res.json({ races: schedule });
  } catch (err) {
    console.error('[API] /calendar error:', err);
    res.status(500).json({ error: 'Failed to fetch calendar' });
  }
});

// Results for a specific round (from MySQL archive, fallback to API)
router.get('/calendar/:round/results', async (req: Request, res: Response) => {
  try {
    const round = parseInt(req.params.round, 10);

    // Try MySQL first
    try {
      const db = getPool();
      const [rows] = await db.query(
        `SELECT * FROM \`race_results\`
         WHERE \`season_year\` = ? AND \`round_number\` = ?
         ORDER BY \`position\` ASC`,
        [YEAR, round]
      );
      const archived = rows as any[];
      if (archived.length > 0) {
        const results = archived.map((r) => ({
          position: r.position,
          driverCode: r.driver_code,
          driverNumber: String(r.driver_number),
          givenName: r.driver_name?.split(' ')[0] ?? '',
          familyName: r.driver_name?.split(' ').slice(1).join(' ') ?? '',
          constructorName: r.team,
          constructorId: '',
          grid: r.grid ?? 0,
          laps: r.laps ?? 0,
          status: r.status ?? 'Finished',
          time: r.finish_time,
          points: parseFloat(r.points) || 0,
        }));
        res.json({
          raceName: archived[0].race_name,
          round,
          circuitName: archived[0].circuit,
          date: archived[0].session_date,
          results,
        });
        return;
      }
    } catch {
      // DB unavailable, fall through to API
    }

    // Fallback to Jolpica API
    const results = await getRaceResults(YEAR, round);
    const schedule = await getSchedule(YEAR);
    const race = schedule.find((r) => r.round === round);
    res.json({
      raceName: race?.raceName ?? `Round ${round}`,
      round,
      circuitName: race?.circuitName ?? '',
      date: race?.raceDate ?? '',
      results,
    });
  } catch (err) {
    console.error(`[API] /calendar/${req.params.round}/results error:`, err);
    res.status(500).json({ error: 'Failed to fetch results' });
  }
});

// Latest completed race results
router.get('/results/latest', async (_req: Request, res: Response) => {
  try {
    const schedule = await getSchedule(YEAR);
    const completed = schedule.filter((r) => r.isCompleted).sort((a, b) => b.round - a.round);
    if (completed.length === 0) {
      res.json({ raceName: null, round: 0, circuitName: '', date: '', results: [] });
      return;
    }
    const latest = completed[0];
    const results = await getRaceResults(YEAR, latest.round);
    res.json({
      raceName: latest.raceName,
      round: latest.round,
      circuitName: latest.circuitName,
      date: latest.raceDate,
      results: results.slice(0, 10),
    });
  } catch (err) {
    console.error('[API] /results/latest error:', err);
    res.status(500).json({ error: 'Failed to fetch latest results' });
  }
});

// Weather for a circuit
router.get('/weather/:circuitId', async (req: Request, res: Response) => {
  try {
    const info = getCircuitInfo(req.params.circuitId);
    if (!info) {
      res.status(404).json({ error: 'Circuit not found' });
      return;
    }
    const weather = await getWeather(info.lat, info.lng, info.circuitId);
    res.json({ circuitName: info.name, weather });
  } catch (err) {
    console.error(`[API] /weather/${req.params.circuitId} error:`, err);
    res.status(500).json({ error: 'Failed to fetch weather' });
  }
});

// Circuit info (static data)
router.get('/circuit/:circuitId', (req: Request, res: Response) => {
  const info = getCircuitInfo(req.params.circuitId);
  if (!info) {
    res.status(404).json({ error: 'Circuit not found' });
    return;
  }
  res.json(info);
});

export default router;
```

**Step 3: Verify the server starts**

```bash
cd f1-website && npm run dev:server
```

Expected: Server logs `[Server] F1 Dashboard running on http://0.0.0.0:1950` and `[DB] MySQL connected successfully`.

**Step 4: Commit**

```bash
git add src/server/ && git commit -m "feat: Express server with all API routes, cron jobs, and static serving"
```

---

## Phase 3: Frontend Foundation

### Task 11: HTML Entry Point & Global CSS

**Files:**
- Modify: `src/client/public/index.html`
- Modify: `src/client/src/styles/global.css`

**Step 1: Update index.html with Google Fonts, viewport meta, and theme color**

```html
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="theme-color" content="#0A0A0A" />
    <meta name="description" content="F1 Race Countdown Dashboard" />
    <title>F1 Dashboard</title>
    <link rel="preconnect" href="https://fonts.googleapis.com" />
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
    <link
      href="https://fonts.googleapis.com/css2?family=Orbitron:wght@400;500;600;700;800;900&family=Barlow+Condensed:wght@300;400;500;600;700;800&family=DM+Mono:wght@300;400;500&display=swap"
      rel="stylesheet"
    />
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/index.tsx"></script>
  </body>
</html>
```

**Step 2: Write global CSS with McLaren carbon-fiber HUD theme**

`src/client/src/styles/global.css`:

This is a critical file — it defines the ENTIRE visual identity. The implementing engineer should create a comprehensive CSS file including:

- CSS custom properties (all `--carbon-*`, `--papaya`, `--mclaren-blue` colors)
- Carbon fiber background texture using `repeating-linear-gradient`
- Base resets (`*, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }`)
- Body styling: `background: var(--carbon-bg); color: var(--text-primary); font-family: 'DM Mono', monospace;`
- Scrollbar styling (thin, papaya-colored on dark track)
- Selection highlight in papaya
- Card base class with `background: var(--surface); border: 1px solid var(--border-subtle); border-radius: 12px;`
- Hover glow effect class: `box-shadow: 0 0 20px var(--glow-orange);`
- `.live-pulse` animation keyframes (pulsing orange glow)
- Staggered fade-in animation: `@keyframes fadeInUp` with `opacity: 0; transform: translateY(20px)` → `opacity: 1; transform: translateY(0)`
- Delay utility classes `.delay-1` through `.delay-8` (100ms increments)
- Responsive breakpoints: `@media (min-width: 768px)` and `@media (min-width: 1200px)`
- Section heading styling with Barlow Condensed, uppercase, letter-spacing
- A subtle noise/grain overlay for depth (optional CSS-only effect)

**Step 3: Commit**

```bash
git add src/client/public/index.html src/client/src/styles/global.css && git commit -m "feat: HTML entry point with Google Fonts and McLaren carbon HUD global CSS"
```

---

### Task 12: React Entry Point & App Shell

**Files:**
- Modify: `src/client/src/index.tsx`
- Modify: `src/client/src/App.tsx`

**Step 1: Set up React root**

`src/client/src/index.tsx`:
```typescript
import React from 'react';
import ReactDOM from 'react-dom/client';
import App from './App';
import './styles/global.css';

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
```

**Step 2: Create App shell that composes all dashboard sections**

`src/client/src/App.tsx`:
```tsx
import { HeroCountdown } from './components/HeroCountdown';
import { UpcomingStrip } from './components/UpcomingStrip';
import { WeatherWidget } from './components/WeatherWidget';
import { CircuitCard } from './components/CircuitCard';
import { DriverStandings } from './components/DriverStandings';
import { ConstructorStandings } from './components/ConstructorStandings';
import { RaceCalendar } from './components/RaceCalendar';
import { RecentResults } from './components/RecentResults';

export default function App() {
  return (
    <div className="dashboard">
      <HeroCountdown />
      <UpcomingStrip />
      <div className="info-row">
        <WeatherWidget />
        <CircuitCard />
      </div>
      <div className="standings-row">
        <DriverStandings />
        <ConstructorStandings />
      </div>
      <RaceCalendar />
      <RecentResults />
      <footer className="dashboard-footer">
        <span>F1 DASHBOARD</span>
        <span className="footer-accent">// MCLAREN EDITION</span>
      </footer>
    </div>
  );
}
```

Layout classes (`.dashboard`, `.info-row`, `.standings-row`) should be defined in global.css with CSS Grid/Flexbox. The `.dashboard` container should have max-width: 1400px, centered, with padding.

**Step 3: Commit**

```bash
git add src/client/src/index.tsx src/client/src/App.tsx && git commit -m "feat: React entry point and App shell with dashboard layout"
```

---

### Task 13: Custom Hooks (useCountdown, useF1Data)

**Files:**
- Create: `src/client/src/hooks/useCountdown.ts`
- Create: `src/client/src/hooks/useF1Data.ts`

**Step 1: Implement useCountdown hook**

```typescript
import { useState, useEffect } from 'react';

interface CountdownResult {
  days: number;
  hours: number;
  minutes: number;
  seconds: number;
  total: number; // total milliseconds remaining
  isExpired: boolean;
}

export function useCountdown(targetDate: string | null): CountdownResult {
  const [timeLeft, setTimeLeft] = useState<CountdownResult>(calculate(targetDate));

  useEffect(() => {
    if (!targetDate) return;
    const timer = setInterval(() => {
      setTimeLeft(calculate(targetDate));
    }, 1000);
    return () => clearInterval(timer);
  }, [targetDate]);

  return timeLeft;
}

function calculate(targetDate: string | null): CountdownResult {
  if (!targetDate) return { days: 0, hours: 0, minutes: 0, seconds: 0, total: 0, isExpired: true };

  const total = new Date(targetDate).getTime() - Date.now();
  if (total <= 0) return { days: 0, hours: 0, minutes: 0, seconds: 0, total: 0, isExpired: true };

  return {
    days: Math.floor(total / (1000 * 60 * 60 * 24)),
    hours: Math.floor((total / (1000 * 60 * 60)) % 24),
    minutes: Math.floor((total / (1000 * 60)) % 60),
    seconds: Math.floor((total / 1000) % 60),
    total,
    isExpired: false,
  };
}
```

**Step 2: Implement useF1Data hook**

A generic polling hook that fetches from the server API at a configurable interval.

```typescript
import { useState, useEffect, useCallback } from 'react';

interface UseF1DataResult<T> {
  data: T | null;
  loading: boolean;
  error: string | null;
  refetch: () => void;
}

export function useF1Data<T>(endpoint: string, pollInterval?: number): UseF1DataResult<T> {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchData = useCallback(async () => {
    try {
      const res = await fetch(`/api${endpoint}`);
      if (!res.ok) throw new Error(`API error: ${res.status}`);
      const json = await res.json();
      setData(json);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  }, [endpoint]);

  useEffect(() => {
    fetchData();
    if (pollInterval) {
      const timer = setInterval(fetchData, pollInterval);
      return () => clearInterval(timer);
    }
  }, [fetchData, pollInterval]);

  return { data, loading, error, refetch: fetchData };
}
```

**Step 3: Commit**

```bash
git add src/client/src/hooks/ && git commit -m "feat: useCountdown and useF1Data custom hooks"
```

---

## Phase 4: Frontend Components

### Task 14: HeroCountdown Component

**Files:**
- Create: `src/client/src/components/HeroCountdown.tsx`

**Step 1: Build the hero countdown — the centerpiece of the dashboard**

This is the MOST IMPORTANT visual component. It must be spectacular.

Requirements:
- Full-width section with carbon fiber background texture
- Race name and session type displayed prominently (Barlow Condensed, uppercase)
- Four massive countdown digits (Orbitron, 900 weight) for DD : HH : MM : SS
- Each digit unit in its own box/card with a subtle orange border
- Labels under each digit: "DAYS", "HRS", "MIN", "SEC" (DM Mono, muted text)
- When `isLive` is true: replace countdown with the `LiveIndicator` pulsing badge
- Digits should animate with `translateY` slide when the value changes (use a key trick or CSS transition)
- Staggered fade-in animation on page load
- Country flag emoji next to race location
- Mobile responsive: digits should scale down but remain prominent

The component uses `useF1Data('/next-session', 30000)` (poll every 30s) and `useCountdown(session.date_start)`.

**Step 2: Commit**

```bash
git add src/client/src/components/HeroCountdown.tsx && git commit -m "feat: HeroCountdown component with animated digits and live detection"
```

---

### Task 15: LiveIndicator Component

**Files:**
- Create: `src/client/src/components/LiveIndicator.tsx`

**Step 1: Build the pulsing LIVE badge**

- Red/orange circle dot with CSS `box-shadow` pulse animation
- "LIVE" text in Orbitron, uppercase
- Session name displayed next to it
- The entire badge should have a subtle glow effect
- CSS keyframes: `@keyframes pulse { 0%, 100% { box-shadow: 0 0 0 0 rgba(255,128,0,0.7); } 70% { box-shadow: 0 0 0 15px rgba(255,128,0,0); } }`

**Step 2: Commit**

```bash
git add src/client/src/components/LiveIndicator.tsx && git commit -m "feat: LiveIndicator pulsing badge component"
```

---

### Task 16: UpcomingStrip Component

**Files:**
- Create: `src/client/src/components/UpcomingStrip.tsx`

**Step 1: Build the horizontal-scrolling upcoming sessions strip**

- Section heading: "UPCOMING SESSIONS" (Barlow Condensed, with orange accent line)
- Horizontal row of session cards, scrollable on mobile (touch-friendly, `overflow-x: auto`, `scroll-snap-type: x mandatory`)
- Each card shows: session type badge (FP1/FP2/FP3/QUALI/SPRINT/RACE), race name, date + local time
- Local time conversion using `Intl.DateTimeFormat` with the browser's timezone
- Cards have the surface background with subtle border, hover glow
- Use `useF1Data('/sessions/upcoming', 30000)`
- Session type badges should be color-coded: Practice = muted, Qualifying = blue accent, Race = papaya

**Step 2: Commit**

```bash
git add src/client/src/components/UpcomingStrip.tsx && git commit -m "feat: UpcomingStrip horizontal session cards with local times"
```

---

### Task 17: WeatherWidget & CircuitCard Components

**Files:**
- Create: `src/client/src/components/WeatherWidget.tsx`
- Create: `src/client/src/components/CircuitCard.tsx`

**Step 1: Build the weather widget**

- Compact card showing: temperature (large Orbitron number), weather condition text (derived from WMO weather code), wind speed, humidity
- WMO weather code mapping: 0=Clear, 1-3=Partly cloudy, 45-48=Foggy, 51-57=Drizzle, 61-67=Rain, 71-77=Snow, 80-82=Showers, 95-99=Thunderstorm
- Weather icon (use Unicode/emoji for simplicity: sun, cloud, rain, etc.)
- Circuit name displayed at top
- Fetches from `/api/weather/:circuitId` — the circuitId comes from the next race in the calendar
- The widget needs to first get the calendar to find the next race's circuitId, then fetch weather

**Step 2: Build the circuit info card**

- Card showing: circuit name (large), country + flag, lap count, lap record (time + holder), DRS zones, circuit length
- Data comes from `/api/circuit/:circuitId`
- Stats displayed in a grid: 2x3 on desktop, 2x3 on mobile
- Each stat: label (DM Mono, muted, small) + value (Barlow Condensed, white, large)

**Step 3: Commit**

```bash
git add src/client/src/components/WeatherWidget.tsx src/client/src/components/CircuitCard.tsx && git commit -m "feat: WeatherWidget and CircuitCard components"
```

---

### Task 18: DriverStandings & ConstructorStandings Components

**Files:**
- Create: `src/client/src/components/DriverStandings.tsx`
- Create: `src/client/src/components/ConstructorStandings.tsx`

**Step 1: Build the driver standings table**

- Section heading: "DRIVER CHAMPIONSHIP" with season year
- Table rows: position number, driver code (3-letter), full name, team name, points
- Animated horizontal bar behind each row showing relative points (width = driver points / max points * 100%)
- Bars animate from width 0 to final width on mount (CSS transition: `width 1.2s ease-out` with staggered `transition-delay`)
- **Lando Norris row (driver number 4 OR code NOR)** gets a special papaya orange highlight — distinct background, brighter bar, papaya text color
- **McLaren constructor rows** also get subtle papaya tint
- Use `useF1Data('/standings/drivers', 300000)` (poll every 5 min)
- Team colors: map `constructorId` to hex colors for the bars (e.g., red_bull → #3671C6, mclaren → #FF8000, ferrari → #E8002D, mercedes → #27F4D2, etc.)

**Step 2: Build the constructor standings table**

- Same visual style as driver standings
- Rows: position, team name, points, bar
- McLaren row highlighted
- Use `useF1Data('/standings/constructors', 300000)`

**Step 3: Commit**

```bash
git add src/client/src/components/DriverStandings.tsx src/client/src/components/ConstructorStandings.tsx && git commit -m "feat: Driver and Constructor standings with animated bars and McLaren highlight"
```

---

### Task 19: RaceCalendar Component

**Files:**
- Create: `src/client/src/components/RaceCalendar.tsx`

**Step 1: Build the full-year race calendar**

- Section heading: "2026 RACE CALENDAR"
- Grid of race weekend cards (2 columns on desktop, 1 on mobile)
- Each card shows: round number, race name, circuit, country + flag, race date (local time)
- **Completed races**: darker/muted style, green checkmark badge, "VIEW RESULTS" button
- **Next race**: highlighted with papaya border glow, "NEXT" badge
- **Future races**: standard style with session times (FP1, FP2, FP3, Qualifying, Sprint if applicable, Race — all in local timezone)
- Clicking "VIEW RESULTS" on a completed race fetches `/api/calendar/:round/results` and expands an inline results table below the card
- Clicking a future race expands to show all session times
- All times use `Intl.DateTimeFormat` with user's browser timezone
- Use `useF1Data('/calendar', 3600000)` (poll hourly)
- Smooth expand/collapse animation on click

**Step 2: Commit**

```bash
git add src/client/src/components/RaceCalendar.tsx && git commit -m "feat: RaceCalendar with expandable past results and future session times"
```

---

### Task 20: RecentResults Component

**Files:**
- Create: `src/client/src/components/RecentResults.tsx`

**Step 1: Build the recent results section**

- Section heading: "LATEST RACE RESULTS" with the race name
- Top 10 results in a clean table
- Columns: Position, Driver (code + name), Team, Grid position, Time/Status, Points
- Position badges: P1 gets gold, P2 silver, P3 bronze colored badge
- Podium finishers row gets subtle highlight
- If the status is not "Finished", show the status text (e.g., "DNF", "+1 Lap") in red
- McLaren / Norris rows get papaya highlight
- Use `useF1Data('/results/latest', 300000)` (5 min)
- If no results yet (season hasn't started), show a "Season not started yet" placeholder with a countdown to Round 1

**Step 2: Commit**

```bash
git add src/client/src/components/RecentResults.tsx && git commit -m "feat: RecentResults component with podium highlights"
```

---

## Phase 5: Polish & Docker

### Task 21: Page Animations & Visual Polish

**Files:**
- Modify: `src/client/src/styles/global.css`
- Modify: `src/client/src/App.tsx`

**Step 1: Add staggered fade-in animations to all dashboard sections**

In `App.tsx`, wrap each section in a div with the `fade-in-up` class and a `delay-N` class:
```tsx
<div className="fade-in-up delay-1"><HeroCountdown /></div>
<div className="fade-in-up delay-2"><UpcomingStrip /></div>
// ... etc.
```

**Step 2: Add final CSS polish**

- Ensure carbon fiber texture is visible on the hero section
- Add a subtle gradient overlay at the top of the page (papaya → transparent)
- Fine-tune spacing between sections (gap: 2rem on mobile, 3rem on desktop)
- Add loading skeleton styles for when data is being fetched (pulsing surface-colored rectangles)
- Ensure all hover effects are smooth (transition: 0.2s ease)
- Test scrollbar styling
- Add a thin papaya line separator between major sections
- Footer styling: muted text, bottom padding

**Step 3: Test on mobile viewport sizes (Chrome DevTools)**

Verify at 375px (iPhone), 768px (tablet), 1200px+ (desktop).

**Step 4: Commit**

```bash
git add src/client/ && git commit -m "feat: staggered animations, loading skeletons, and visual polish"
```

---

### Task 22: Dockerfile & docker-compose.yml

**Files:**
- Modify: `Dockerfile`
- Create: `docker-compose.yml`

**Step 1: Write the multi-stage Dockerfile**

```dockerfile
# Stage 1: Build
FROM node:20-alpine AS builder
WORKDIR /app

# Copy workspace root
COPY package.json package-lock.json ./
COPY src/client/package.json src/client/
COPY src/server/package.json src/server/

# Install all dependencies
RUN npm ci

# Copy source
COPY src/ src/
COPY tsconfig.json* ./

# Build client (Vite)
RUN npm run build:client

# Build server (tsc)
RUN npm run build:server

# Stage 2: Production
FROM node:20-alpine AS production
WORKDIR /app

# Copy server production deps
COPY src/server/package.json ./src/server/
COPY package.json package-lock.json ./
RUN npm ci --workspace=src/server --omit=dev

# Copy built assets
COPY --from=builder /app/src/client/dist ./src/client/dist
COPY --from=builder /app/src/server/dist ./src/server/dist
COPY --from=builder /app/src/shared ./src/shared

# Non-root user
RUN addgroup -g 1001 f1 && adduser -u 1001 -G f1 -s /bin/sh -D f1
USER f1

EXPOSE 1950

ENV NODE_ENV=production
ENV PORT=1950

CMD ["node", "src/server/dist/index.js"]
```

**Step 2: Write docker-compose.yml**

```yaml
version: '3.8'

services:
  f1-dashboard:
    build: .
    container_name: f1-dashboard
    restart: unless-stopped
    ports:
      - "1950:1950"
    env_file:
      - .env
    environment:
      - NODE_ENV=production
      - PORT=1950
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:1950/api/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s
    labels:
      net.unraid.docker.managed: "true"
      net.unraid.docker.webui: "http://[IP]:[PORT:1950]"
      net.unraid.docker.icon: "https://upload.wikimedia.org/wikipedia/commons/3/33/F1.svg"
```

**Step 3: Test Docker build**

```bash
cd f1-website && docker build -t f1-dashboard .
```

Expected: Successful multi-stage build, image ~150-200MB.

**Step 4: Test Docker run**

```bash
docker run --rm -p 1950:1950 --env-file .env f1-dashboard
```

Expected: Server starts, health check at `http://localhost:1950/api/health` returns `{"status":"ok"}`.

**Step 5: Commit**

```bash
git add Dockerfile docker-compose.yml && git commit -m "feat: multi-stage Dockerfile and docker-compose for Unraid deployment"
```

---

### Task 23: Final Integration Smoke Test

**Step 1: Start the full stack in development mode**

Terminal 1:
```bash
cd f1-website && npm run dev:server
```

Terminal 2:
```bash
cd f1-website && npm run dev:client
```

**Step 2: Verify each API endpoint returns data**

Test these URLs in a browser or curl:
- `http://localhost:1950/api/health` → `{"status":"ok"}`
- `http://localhost:1950/api/next-session` → session data or null
- `http://localhost:1950/api/sessions/upcoming` → array of sessions
- `http://localhost:1950/api/standings/drivers` → driver standings
- `http://localhost:1950/api/standings/constructors` → constructor standings
- `http://localhost:1950/api/calendar` → full race schedule
- `http://localhost:1950/api/results/latest` → latest results or empty
- `http://localhost:1950/api/weather/bahrain` → weather data
- `http://localhost:1950/api/circuit/bahrain` → circuit info

**Step 3: Verify the frontend renders correctly at `http://localhost:5173`**

- Hero countdown is displayed with correct data
- All sections load without console errors
- Responsive design works at mobile/tablet/desktop widths
- Lando Norris / McLaren rows are highlighted in papaya

**Step 4: Run production Docker build and verify**

```bash
docker compose up --build
```

Visit `http://localhost:1950` — the full dashboard should render served from Express.

**Step 5: Final commit**

```bash
git add -A && git commit -m "chore: final integration verification"
```

---

## Summary

| Phase | Tasks | What gets built |
|-------|-------|----------------|
| 1: Foundation | 1–3 | Workspace, types, MySQL setup |
| 2: Backend | 4–10 | Cache, APIs (Jolpica + OpenF1 + weather), archiver, Express routes |
| 3: Frontend Foundation | 11–13 | HTML, CSS theme, React shell, hooks |
| 4: Frontend Components | 14–20 | All 7 dashboard components |
| 5: Polish & Docker | 21–23 | Animations, Dockerfile, docker-compose, smoke test |

Total: **23 tasks** across 5 phases.
