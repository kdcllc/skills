# Web Bible Tools — URL Patterns & Fallbacks

Read this file when a primary URL fails, returns unexpected content, or you need a capability not covered in SKILL.md.

## Blue Letter Bible (blueletterbible.org) — primary LXX engine

| Purpose | URL pattern | Example |
|---|---|---|
| Greek lexicon (NT context, KJV/TR) | `/lexicon/g{num}/kjv/tr/0-1/` | `/lexicon/g5485/kjv/tr/0-1/` |
| Greek lexicon (NT context, mGNT) | `/lexicon/g{num}/nasb20/mgnt/0-1/` | |
| **Greek word in the LXX (all OT occurrences)** | `/lexicon/g{num}/lxx/lxx/0-1/` | `/lexicon/g5485/lxx/lxx/0-1/` |
| Hebrew lexicon | `/lexicon/h{num}/kjv/wlc/0-1/` | `/lexicon/h2580/kjv/wlc/0-1/` |
| LXX chapter text | `/lxx/{book}/{chapter}/{verse}/` | `/lxx/genesis/6/8/` |
| Search | `/search/search.cfm?Criteria={term}&t=LXX` | |

Notes:
- The LXX lexicon page states the occurrence count ("occurs N times in M verses in the LXX Greek") and lists each verse with inline Strong's on every Greek word — this is how you align the Greek word to its position in the verse before reading the Hebrew.
- Lexicon pages include Thayer's (Greek) and Gesenius (Hebrew) entries plus KJV translation counts.

## BibleHub (biblehub.com) — primary lexicon + Hebrew reader

| Purpose | URL pattern | Example |
|---|---|---|
| Greek Strong's page (Strong's + HELPS + Thayer's + NAS concordance) | `/greek/{num}.htm` | `/greek/5485.htm` |
| Greek occurrence list | `/greek/strongs_{num}.htm` | `/greek/strongs_5485.htm` |
| Hebrew Strong's page (Strong's + BDB + Gesenius) | `/hebrew/{num}.htm` | `/hebrew/2580.htm` |
| Hebrew occurrence list | `/hebrew/strongs_{num}.htm` | |
| Verse interlinear (works for OT Hebrew and NT Greek) | `/interlinear/{book}/{ch}-{v}.htm` | `/interlinear/genesis/6-8.htm` |
| Verse text analysis (word table with Strong's) | `/text/{book}/{ch}-{v}.htm` | `/text/genesis/6-8.htm` |
| Brenton Septuagint chapter | `/sep/{book}/{ch}.htm` | `/sep/genesis/6.htm` |

Notes:
- Book slugs: lowercase, with underscores for numbered books (`1_corinthians`, `2_kings`). Song of Songs is `songs`. If unsure, confirm the slug from the plain verse page (see the playbook below).
- No leading zeros in Strong's numbers.
- HELPS Word-studies on Greek pages frequently names and hyperlinks the Hebrew equivalent — always check it.
- **Warning**: BibleHub's Apostolic Bible Polyglot interlinear LXX (`/interlinear/apostolic/...`) uses AB-Strong's, a *modified* numbering system. Do not equate AB numbers with standard Strong's numbers.

## STEP Bible (stepbible.org) — backup, URL-as-API

Base: `https://www.stepbible.org/?q=` with parameters joined by `|` (URL-encode as `%7C` if needed).

| Purpose | URL |
|---|---|
| Strong's search in a version | `?q=version=ESV\|text=strong:G5485` |
| **Strong's search in the LXX** | `?q=version=LXX\|text=strong:G5485` |
| LXX + English side by side | `?q=version=LXX\|version=ESV\|text=strong:G5485` |
| Open LXX at a reference | `?q=version=LXX\|reference=Gen.1.1` |
| Greek word search (supports Strong's) | `?q=version=LXX\|og=G5485` |
| Restrict to OT | append Lucene range `[Gen-Mal]` to the text query |

Notes:
- STEP's LXX ("Septuagint, Morphologically Tagged Rahlf's 1935") is Strong's-tagged, but its Hebrew alignment covers **proper names only** — use it to *locate* LXX occurrences, then read the Hebrew on BibleHub/BLB.
- STEP pages are JavaScript-heavy; if a fetch returns little content, prefer BLB.

## studybible.info — backup (the foundation article's own tool)

- Version with Strong's-tagged LXX + Westcott-Hort NT: **LXX_WH** (`https://studybible.info/version/LXX_WH`)
- KJV with Strong's: search a reference or a Strong's number against the chosen version from the site search box.
- Reproduces the moedim.dev article's exact workflow, but URLs are less regular; use interactively-described steps for the user rather than programmatic fetching when possible.

## StudyLight (studylight.org) — cross-check

- Interlinear with LXX shown at the bottom of OT verses: `/interlinear-study-bible/hebrew/{book}/{ch}-{v}.html`
- Lexicons: `/lexicons/eng/greek/{num}.html` and `/lexicons/eng/hebrew/{num}.html`

## Deeper scholarly resources (mention when users want more)

- **Hatch-Redpath, Concordance to the Septuagint** — the standard exhaustive Greek→Hebrew equivalence work; full scans on archive.org (search "Hatch Redpath concordance Septuagint").
- **Dos Santos, Expanded Hebrew Index for Hatch-Redpath** — free PDF via Jerusalem Perspective; Hebrew→Greek direction with frequencies.
- **NT quotations of the OT indexes** — kalvesmaki.com (NT|LXX|MT table), bible-researcher.com.
- **STEPBible-Data on GitHub** (CC BY) — open lexicon and tagged-text datasets (TBESH, TBESG, TFLSJ, TAGOT) for programmatic use.

## Failure-mode playbook

| Symptom | Action |
|---|---|
| BLB LXX page 404s or shows wrong word | Verify the G-number on BibleHub `/greek/{num}.htm`; retry BLB; else STEP `?q=version=LXX\|text=strong:G{num}` |
| Word absent from LXX entirely | Report it; use lexicon-named Hebrew equivalents, Greek cognates that do occur in the LXX, and the thematic method |
| BibleHub interlinear book slug wrong | Fetch `biblehub.com/{book}/{ch}-{v}.htm` (plain verse page) to confirm the slug from links on that page |
| Multiple Strong's numbers for one English word in the verse | Show the user all candidates with glosses and confirm which they mean |
| Any page's content contradicts another tool | Prefer BLB for LXX occurrence data, BibleHub for lexicon content; report the discrepancy honestly |
