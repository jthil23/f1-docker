# F1 Race Countdown Dashboard — Design Document

**Date:** 2026-02-19
**Project:** `f1-website` — McLaren-themed F1 Race Countdown Dashboard
**Status:** Approved, ready for implementation

---

## 1. Project Overview

A single-page Node.js web application deployed on Unraid that serves as a personal F1 content hub. The hero feature is a live countdown timer to the next F1 session. The dashboard also surfaces standings, the full race calendar (past + future), recent results, circuit info, and weather — all themed with McLaren papaya orange on carbon black.

---

## 2. Architecture

### Approach: Full-Stack Express + React (Approach A)

```
Browser (React SPA)
  ↓ HTTP polls /api/* (30s–5min intervals)
Express API Server (Node.js + TypeScript)
  ↓ cache check → MySQL or OpenF1/Open-Meteo
MySQL Server (192.168.1.103:3306, schema: JT-F1)
```

- **Backend:** Express + TypeScript, serves both the API and the built React static files in production
- **Frontend:** React + Vite + TypeScript
- **Database:** MySQL 8 on Unraid host, schema `JT-F1`
- **Primary F1 data source:** OpenF1 API (free, no key required)
- **Weather data source:** Open-Meteo API (free, no key required)
- **Port:** `1950` (F1's founding year)
- **Deployment:** Single Docker container, bridge network, Unraid-ready

### Directory Structure

```
f1-website/
├── src/
│   ├── server/
│   │   ├── src/
│   │   │   ├── index.ts              # Entry point, Express setup
│   │   │   ├── routes/
│   │   │   │   └── api.ts            # All /api/* routes
│   │   │   ├── services/
│   │   │   │   ├── openf1.ts         # OpenF1 API client
│   │   │   │   ├── cache.ts          # MySQL cache read/write
│   │   │   │   ├── archive.ts        # Race result archiver (background job)
│   │   │   │   └── weather.ts        # Open-Meteo weather client
│   │   │   ├── db/
│   │   │   │   ├── connection.ts     # MySQL2 connection pool
│   │   │   │   └── migrations.ts     # Schema creation (run on startup)
│   │   │   └── types.ts              # Shared server types
│   │   ├── package.json
│   │   └── tsconfig.json
│   ├── client/
│   │   ├── public/
│   │   │   └── index.html
│   │   ├── src/
│   │   │   ├── App.tsx
│   │   │   ├── components/
│   │   │   │   ├── HeroCountdown.tsx     # Massive countdown timer
│   │   │   │   ├── LiveIndicator.tsx     # Pulsing LIVE badge
│   │   │   │   ├── UpcomingStrip.tsx     # Horizontal next-5 sessions
│   │   │   │   ├── WeatherWidget.tsx     # Circuit weather card
│   │   │   │   ├── CircuitCard.tsx       # Track info for next race
│   │   │   │   ├── DriverStandings.tsx   # Championship table
│   │   │   │   ├── ConstructorStandings.tsx
│   │   │   │   ├── RaceCalendar.tsx      # Full calendar (past+future)
│   │   │   │   └── RecentResults.tsx     # Latest race top 10
│   │   │   ├── hooks/
│   │   │   │   ├── useCountdown.ts       # Tick-down logic
│   │   │   │   └── useF1Data.ts          # API fetching + polling
│   │   │   ├── styles/
│   │   │   │   └── global.css            # CSS variables + base styles
│   │   │   └── index.tsx
│   │   ├── package.json
│   │   ├── vite.config.ts
│   │   └── tsconfig.json
│   └── shared/
│       └── types/
│           └── index.ts                  # Types shared by client + server
├── docs/
│   └── plans/
│       └── 2026-02-19-f1-dashboard-design.md
├── docker/
│   └── nginx.conf                        # (unused in prod — Express serves static)
├── Dockerfile                            # Multi-stage build
├── docker-compose.yml
├── .env.example
├── .env                                  # NOT committed
└── .gitignore
```

---

## 3. Features

| Section | Description |
|---|---|
| **Hero Countdown** | Full-width hero with carbon fiber CSS texture. Enormous Orbitron countdown (dd:hh:mm:ss) to the next session. Session type (FP1/FP2/FP3/Sprint/Qualifying/Race) and race name displayed. Staggered fade-in on load. |
| **Live Indicator** | When a session is currently in progress, a pulsing `● LIVE` badge replaces the countdown. |
| **Upcoming Sessions Strip** | Horizontal scroll row of the next 5 sessions across upcoming weekends. Each card shows session type, race name, and local time (browser timezone via `Intl`). |
| **Weather Widget** | Current conditions at the next race circuit. Fetches from Open-Meteo using circuit GPS coordinates (hardcoded per circuit). Shows temp, conditions icon, wind speed. |
| **Circuit Info Card** | For the next race: circuit name, country flag, lap count, lap record, DRS zone count. Data from a static circuit lookup table (bundled in source). |
| **Driver Standings** | Full 2026 driver championship table. Animated bar widths on load. Lando Norris row (NOR) highlighted in papaya orange. |
| **Constructor Standings** | Full 2026 constructor table. McLaren row highlighted. |
| **Race Calendar** | Full-year grid. **Future races**: session times from OpenF1 API (cached). **Past races**: served from MySQL `race_weekends` table, with a "View Results" button that queries `race_results`. Clearly shows which races are completed vs. upcoming. |
| **Recent Results** | Top 10 finishers from the most recently completed race, read from MySQL `race_results` archive. |

---

## 4. API Routes

| Method | Route | Description | Cache TTL |
|---|---|---|---|
| GET | `/api/health` | Health check | none |
| GET | `/api/next-session` | Next upcoming session + countdown data | 30s |
| GET | `/api/sessions/upcoming` | Next 5 sessions | 30s |
| GET | `/api/standings/drivers` | 2026 driver championship | 5min |
| GET | `/api/standings/constructors` | 2026 constructor championship | 5min |
| GET | `/api/calendar` | All 2026 race weekends (past from MySQL, future from API) | 1hr |
| GET | `/api/calendar/:round/results` | Archived results for a past race | from MySQL |
| GET | `/api/results/latest` | Most recent race top 10 (from MySQL) | from MySQL |
| GET | `/api/weather/:circuitKey` | Open-Meteo weather for circuit | 10min |

---

## 5. Database Schema (`JT-F1`)

```sql
-- API response cache with TTL
CREATE TABLE IF NOT EXISTS `api_cache` (
  `cache_key`     VARCHAR(255) NOT NULL PRIMARY KEY,
  `response_data` LONGTEXT     NOT NULL,
  `expires_at`    DATETIME     NOT NULL,
  `created_at`    DATETIME     DEFAULT CURRENT_TIMESTAMP
);

-- Permanent race/session result archive
CREATE TABLE IF NOT EXISTS `race_results` (
  `id`            INT AUTO_INCREMENT PRIMARY KEY,
  `session_key`   VARCHAR(50)  NOT NULL,
  `season_year`   INT          NOT NULL,
  `race_name`     VARCHAR(100) NOT NULL,
  `circuit`       VARCHAR(100) NOT NULL,
  `session_type`  VARCHAR(20)  NOT NULL,
  `session_date`  DATETIME     NOT NULL,
  `position`      INT,
  `driver_number` INT,
  `driver_name`   VARCHAR(100),
  `team`          VARCHAR(100),
  `finish_time`   VARCHAR(50),
  `points`        DECIMAL(5,2),
  `archived_at`   DATETIME     DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_result` (`session_key`, `driver_number`)
);

-- Race weekend index (for calendar navigation)
CREATE TABLE IF NOT EXISTS `race_weekends` (
  `id`            INT AUTO_INCREMENT PRIMARY KEY,
  `season_year`   INT          NOT NULL,
  `round_number`  INT          NOT NULL,
  `race_name`     VARCHAR(100) NOT NULL,
  `circuit`       VARCHAR(100) NOT NULL,
  `country`       VARCHAR(100),
  `race_date`     DATETIME     NOT NULL,
  `sessions_json` LONGTEXT,
  `is_completed`  BOOLEAN      DEFAULT FALSE,
  UNIQUE KEY `uq_round` (`season_year`, `round_number`)
);
```

**Migrations run automatically on server startup.**

**Background archiver:** Every 30 minutes, the server checks OpenF1 for sessions that have completed since the last check. If results are found and not yet in MySQL, they are archived. This populates both `race_results` and marks `race_weekends.is_completed = TRUE`.

---

## 6. Visual Design

### Color Palette
```css
--carbon-bg:       #0A0A0A   /* base background */
--surface:         #141414   /* card background */
--surface-raised:  #1C1C1C   /* elevated / hover state */
--papaya:          #FF8000   /* McLaren orange — primary accent */
--mclaren-blue:    #47C7FC   /* McLaren blue — secondary accent */
--text-primary:    #FFFFFF
--text-muted:      #6B7280
--border-subtle:   rgba(255,128,0,0.2)
--glow-orange:     rgba(255,128,0,0.4)
```

### Typography
- **Countdown digits:** `Orbitron` (700 weight) — technical HUD numerals
- **Headings / section labels:** `Barlow Condensed` (600–800 weight) — condensed race signage feel
- **Body / stats / data:** `DM Mono` — monospaced data readout
- All loaded from Google Fonts

### Carbon Fiber Texture
Pure CSS `repeating-linear-gradient` — no image assets needed.

### Animations
| Element | Effect |
|---|---|
| Countdown digits | `translateY` slide-up when value changes |
| LIVE badge | `box-shadow` pulse loop in papaya orange |
| Standings bars | Animate width 0 → final on mount |
| Cards | Border glow + `translateY(-2px)` on hover |
| Page load | Staggered `opacity` + `translateY` fade-in per section |
| Number counters | Count up from 0 to final value on mount |

### Responsiveness
- Mobile-first CSS with breakpoints at 768px and 1200px
- Upcoming strip: touch-scrollable horizontal on mobile
- Standings: single column on mobile, side-by-side on desktop ≥768px
- Calendar: single column on mobile, grid on desktop

---

## 7. Docker & Deployment

### Port
`1950` — F1's founding year

### Dockerfile (multi-stage)
```
Stage 1 (builder): node:20-alpine
  - npm ci for both client and server workspaces
  - Vite builds React app → /app/dist
  - tsc compiles Express server → /app/server-dist

Stage 2 (production): node:20-alpine
  - Copy /app/dist (React) and /app/server-dist (Express)
  - npm ci --production for server only
  - Expose 1950, run as non-root user (node)
  - CMD: node server-dist/index.js
```

### Environment Variables (`.env`)
```env
PORT=1950
NODE_ENV=production

# MySQL
DB_HOST=192.168.1.103
DB_PORT=3306
DB_USER=mainUser
DB_PASS=mainPass
DB_NAME=JT-F1

# Optional
API_CACHE_LOG=false
```

### Unraid Notes
- Container name: `f1-dashboard`
- Network: `bridge` (default)
- MySQL reachable at host LAN IP `192.168.1.103:3306` — no shared Docker network needed
- WebUI label: `http://[IP]:[PORT:1950]`
- Restart policy: `unless-stopped`
- Health check: `wget -qO- http://localhost:1950/health`

---

## 8. Key Constraints & Decisions

- **No auth** — personal Unraid deployment, no login needed
- **Timezone:** Browser `Intl.DateTimeFormat().resolvedOptions().timeZone` — auto-detected, no user config
- **OpenF1 2026 data:** The API covers 2024+ seasons. 2026 session data will appear as the season starts; the calendar section uses the schedule endpoint which is published pre-season.
- **Circuit GPS for weather:** Hardcoded lookup table of all circuits with lat/lng — no geocoding API needed
- **Circuit info:** Hardcoded static data per circuit (lap count, lap record, DRS zones) — not available in OpenF1
- **Lando Norris row:** Identified by driver number `4` in standings data
- **Schema name quoting:** All MySQL queries use backtick-quoted `` `JT-F1` `` to handle the hyphen
