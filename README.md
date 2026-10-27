# Alert Ledger

**Paste your Nigerian bank alerts. Ask your money questions in plain English.**

Most Nigerians already have a complete record of their spending. It sits in hundreds of debit and credit alerts from GTBank, Access, Zenith, OPay, Moniepoint and the rest, and nobody can search it. Alert Ledger turns those alerts into a structured ledger and lets you ask things like:

- *How much did I spend on fuel in September?*
- *Show transfers to Emeka*
- *How many times did I buy suya?*

Runs on **Android, iOS and the web** from one Flutter codebase, with a landing page at `/` and the web app at `/app/`.

Built solo for the [Appwrite Databases Hackathon](https://hackathon.appwrite.io) (Oct 19–31, 2026).

## What's in the app

| Screen | What it does |
|---|---|
| **Home** | Greeting with an illustration, a *Getting started* guide (add alerts → ask a question → teach it one merchant) that ticks itself off as you go, a month summary with a month switcher, a one-line insight ("Fuel took 41% of your spending"), category bars you can tap, and recent transactions. |
| **Activity** | Every transaction grouped by day. Filter by money in/out and by category, or by name, merchant or bank. |
| **Ask** | Plain-English questions. Each answer shows the total, how the question was understood, and the transactions behind it, with a match score for meaning-based hits. |
| **Add alerts** | Paste one or many alerts. Directions for copying an alert on Android, iPhone and email, with your platform listed first. Sample alerts for a quick try. It reports what was saved, what was a duplicate, and what couldn't be read. |
| **Transaction sheet** | Fix the category (the app learns from it), see the original alert, delete. |

The layout adapts: bottom navigation on phones, a navigation rail with centred content on tablets and the web. Light and dark themes. Illustrations are drawn in code, so there are no image assets to ship and they follow the theme.

## How it uses Appwrite Databases

Two database types, each doing the job it's best at:

| | **TablesDB**: the ledger of record | **VectorsDB**: the meaning layer |
|---|---|---|
| Holds | One row per transaction: amount (kobo, integer), direction, date, category, how it was categorised, bank, counterparty, original alert | `tx_vectors`: one 768-dim embedding per transaction + metadata (`userId`, `date`, `direction`, `category`) |
| Also holds | | `category_seeds`: labelled examples (built-in ones, plus each user's own corrections) that teach the app what unknown merchants mean |
| Answers | Exact filters and sums: *fuel in September* | Fuzzy matches: *Emeka* → `NIP/MONIEPOINT/EMEKA OKAFOR`, *suya* → `OBONG SUYA SPOT EWET` |
| Indexes | `userId+txDate`, `userId+direction+txDate`, `userId+category+txDate` | HNSW cosine on `embeddings` |

**Why both:** totals must be exact, so money is never summed from a vector search result alone. Vectors find *which* rows match; TablesDB supplies the numbers.

### The flow

```
Paste alerts ─▶ Function /ingest
                 1. parse amount, direction, date, bank, counterparty  (regex, no AI)
                 2. category: keyword rules ─▶ else nearest-neighbour vote over category_seeds
                    (built-in examples + this user's corrections, which count double)
                 3. embed "money spent · POS PURCHASE OBONG SUYA SPOT · to OBONG SUYA SPOT · food"
                 4. TablesDB.createRow  +  VectorsDB.createDocument  (same id → trivial join)

Ask a question ─▶ Function /ask
                 1. parse intent, direction, date range, category, topic  (deterministic)
                 2. category?  → TablesDB rows filtered by category column
                 3. topic?     → embed topic → VectorsDB vectorCosine + metadata filters (user, dates, direction)
                 4. fetch matched rows from TablesDB, sum in kobo, return answer + rows + how each matched

Fix a category ─▶ Function /recategorize
                 1. update the row (categorySource = "user") and re-store its vector
                 2. save the merchant as a personal seed in category_seeds
                 3. report other rows from the same counterparty; "Move all" fixes them too

Delete ─▶ Function /delete: removes the row, its vector and any seed it taught
```

Embeddings come from Appwrite's built-in **Embeddings** service (`nomic-embed-text`), so there is no outside AI provider.

**Privacy.** Every row, vector and personal seed carries `Permission.read(Role.user(userId))`. Every vector query is filtered by `metadata.userId`. The function checks ownership before changing or deleting a row. One user's corrections never change another user's categories (there's a test for this).

**Onboarding progress** is stored in Appwrite account preferences, so the guide remembers where you are on every device.

## Repo layout

```
landing/index.html       Landing page (static, no build step)
app/                     Flutter app for Android, iOS and web
  lib/app_shell.dart     Responsive navigation
  lib/screens/           Home, Activity, Ask, Add alerts
  lib/widgets/           Getting-started guide, transaction tile and sheet, illustrations
  lib/state/             App state (plain ChangeNotifier)
  lib/services/          Appwrite calls
functions/ledger/        Appwrite Function (Node 22)
  src/parser.js          alert → transaction (pure, tested)
  src/question.js        question → intent / dates / category / topic (pure, tested)
  src/categories.js      keyword rules + built-in seed examples
  src/vector.js          VectorsDB + Embeddings calls
  src/main.js            /ingest, /ask, /recategorize, /delete
  scripts/setup.mjs      provisions both databases, indexes and seeds (idempotent)
  test/                  parser tests + end-to-end tests against in-memory fakes
scripts/build_site.sh    Landing page + web app → one static site
.github/workflows/       Builds Android, web and iOS, runs backend tests
```

## Setup

1. **Appwrite project.** Create one on Appwrite Cloud. Under Auth → Settings, enable **Anonymous** sessions. Add platforms:
   - Android: package `app.alertledger.alert_ledger`
   - iOS: bundle ID `app.alertledger.alertLedger`
   - Web: your site's hostname (and `localhost` for development)
2. **API key** with scopes for databases, tables, columns, indexes, rows, collections, documents and `embeddings.write`.
3. **Provision databases:**
   ```bash
   cd functions/ledger && npm install
   APPWRITE_ENDPOINT=https://<REGION>.cloud.appwrite.io/v1 \
   APPWRITE_PROJECT_ID=<id> APPWRITE_API_KEY=<key> npm run setup
   ```
4. **Deploy the function.** Function ID `ledger`, runtime Node 22, entrypoint `src/main.js`, build command `npm install`. Execute access: **Users**. Give its dynamic key: rows read/write, documents read/write, `embeddings.write`.
5. **Run the app.** Put your endpoint and project ID in `app/lib/config.dart`, then:
   ```bash
   cd app
   flutter create . --platforms=android,ios,web --project-name alert_ledger --org app.alertledger
   flutter pub upgrade --major-versions
   flutter run -d chrome      # or an Android/iOS device
   ```
   Tap **Add alerts → Load sample alerts → Save**, then follow the guide on Home.
6. **Publish the site.** `./scripts/build_site.sh` produces `site/` with the landing page at `/` and the web app at `/app/`. Deploy that folder to Appwrite Sites and add the domain as a Web platform. Attach the APK from the CI build to a GitHub release so the landing page's Android button works.

### Tests and builds

```bash
cd functions/ledger && npm test     # 15 tests
```

The end-to-end tests run every route against in-memory fakes of TablesDB, VectorsDB and Embeddings. They cover isolation between users, learning from corrections, and deletion removing data from both databases.

Every push runs `.github/workflows/build.yml`: backend tests, `flutter analyze`, a web build, a release APK (both uploaded as artifacts), and an unsigned iOS build on macOS.

## Tech stack

Flutter (Android, iOS, web) · `appwrite` Flutter SDK · `google_fonts` (Bricolage Grotesque, Figtree) · `intl` · Appwrite Auth (anonymous, account prefs) · Appwrite TablesDB · Appwrite VectorsDB · Appwrite Embeddings (`nomic-embed-text`) · Appwrite Functions (Node 22, `node-appwrite`) · Appwrite Sites · GitHub Actions

---

## Build plan (Oct 26 → Oct 31)

The deadline is **Oct 31, 11:59 PM PT = Sun Nov 1, 7:59 AM in Lagos**. Aim to submit **Saturday evening**.

| Day | Goal | Done when |
|---|---|---|
| **Mon 26 (tonight)** | Push to a new public GitHub repo, so the commit history starts inside the hackathon window. Create the Appwrite project, run `setup`, deploy the function. | CI is green on all three platforms; `npm run setup` prints all ✓. |
| **Tue 27** | Run on a real Android phone and in Chrome. Load samples, finish the getting-started guide. **Tune** `MAX_SEARCH_DISTANCE` and `MAX_CATEGORY_DISTANCE` in `config.js` against real embeddings (log `$distance`). Collect 20–30 real alert formats (blank out account digits) and add them to `test/fixtures.js`. | The six suggested questions all answer correctly. |
| **Wed 28** | iPhone run (a Mac or a friend's). Fix anything that looks off on small screens and in dark mode. Check that the correction loop teaches "ROYAL GAS STATION" as fuel. | Same experience on all three platforms. |
| **Thu 29** | Publish the site (landing + web app) on Appwrite Sites. Make a GitHub release with the CI APK. **Stretch, Android only:** "Import from SMS". | Landing page buttons all work. |
| **Fri 30** | Record the demo (≤3 min). Final README. | Video uploaded. |
| **Sat 31** | Buffer, then **submit by evening** (Lagos time). | Submission confirmed. |

**Cut list if you fall behind** (in this order): SMS import → iOS device testing (CI still proves it builds) → web hosting. Never cut: samples flow, the questions working, the video.

## Demo video script (≈2:40)

1. **0:00 Landing page (15s).** Scroll the landing page once. "Your bank alerts already know where your money went."
2. **0:15 The problem (15s).** A real SMS inbox full of bank alerts. "I can't answer a simple question: how much did I spend on fuel last month?"
3. **0:30 First run (30s).** Open the app on a phone. Point at the getting-started guide. Add alerts → Load sample alerts → Save. Home fills in: month summary, insight line, category bars.
4. **1:00 Ask (50s).** *Fuel in September* (exact sum). *Show transfers to Emeka* (two banks, two formats, both matched by meaning; point at the match score). *How many times did I buy suya?*
5. **1:50 It learns (25s).** Open `ROYAL GAS STATION`, pick Fuel, tap Move all. The guide's last step ticks.
6. **2:15 Under the hood (20s).** The architecture table, then the same app running in a browser to show it's one codebase.
7. **2:35 Close (5s).** "Your bank already wrote your budget. Alert Ledger lets you read it."

## How this maps to the judging criteria

- **Idea and innovation:** a very local problem (Nigerian alert formats, naira, kobo) with a universal pattern, and an app that learns each user's merchants.
- **Technical execution:** parsing is deterministic and tested, money is summed from TablesDB and never guessed by a model, and CI builds for three platforms.
- **Design and experience:** paste → ask. A guided first run, plain-language insights, illustrations, responsive from phone to desktop, light and dark.
- **Usage of Appwrite Databases:** two database types used for what each does best, built-in Embeddings, HNSW index, metadata-filtered vector search, per-user seed vectors that change future results, row-level security, account prefs, and an idempotent setup script.

## Submission checklist

- [ ] Public GitHub repo; every commit dated Oct 27 or later
- [ ] README tech stack lists every library used
- [ ] Demo video, 3 minutes or less
- [ ] Live demo link (landing page + web app on Appwrite Sites)
- [ ] Submitted at hackathon.appwrite.io before Oct 31, 11:59 PM PT
