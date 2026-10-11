# Building an AI Skill to Trace New Testament Words Back to the Old Testament: Methodology, Web Tools, and a Reusable Procedure

## TL;DR
- The moedim.dev "Principles for the Study of the Bible" article's core word-study workflow — find a NT English word's Greek Strong's number, then find that same Greek Strong's number in the Septuagint (LXX) Greek Old Testament, then read the tagged Hebrew word behind that LXX verse to arrive at the Hebrew Strong's number — is fully reproducible on the free web without e-Sword, and **Blue Letter Bible (BLB) is the single best primary tool** because its Greek lexicon page has a dedicated LXX concordance tab that lists every Septuagint occurrence of a Greek Strong's number with inline Strong's tagging, via a clean, programmatically constructible URL (`blueletterbible.org/lexicon/g5485/lxx/lxx/0-1/`).
- **Use a two-tool combination:** BLB for the Greek→LXX occurrence search and Hebrew confirmation, plus **BibleHub** for the fastest Greek→Hebrew "bridge" — its HELPS Word-studies and Thayer's entries on each Greek page frequently name the corresponding Hebrew Strong's number directly (e.g., the G5485 page hyperlinks to Hebrew H2580, and Thayer's states "Hebrew חֵן, grace"), and its parallel interlinear OT pages expose the Hebrew word for any verse. STEP Bible and studybible.info are strong free backups; StudyLight and Bible Gateway are weaker for this specific task.
- The scholarly method (LXX-based lexical bridging) is real and standard, but has a critical limitation the skill must encode: **one Greek word can translate several different Hebrew words** (and vice versa), so a single "first-mention" LXX hit is a starting hypothesis, not proof — the skill should cross-check with a lexicon that cites Hebrew equivalents (Thayer's/HELPS/BDB), the Hatch-Redpath Septuagint concordance for the full equivalence list, and the separate discipline of NT-quotes-the-OT indexes.

## Key Findings

### The moedim.dev article and its e-Sword dependencies
The article ("Principles for the Study Of the Bible," Jan 24 2016) frames Bible study around a **literal-historical hermeneutic**, the **first-mention principle**, and the **law of context**, and demonstrates a concrete word-tracing method using the word "grace" (Greek *charis*, G5485) traced back to Noah (Hebrew *chen*/*hen*, H2580, Genesis 6:8). It recommends studybible.info, stepbible.org, and blueletterbible.org online, and e-Sword as the desktop option. Its actual worked example uses **studybible.info, not e-Sword**, so the workflow is already web-native; e-Sword is only mentioned as an alternative. The steps that touch a specific tool can all be replaced with web equivalents.

### The best web tools for the Greek→LXX→Hebrew mapping
- **Blue Letter Bible** is the strongest single tool. Its Greek lexicon pages carry a **switchable version context that includes "LXX"**, and when set to LXX the page states verbatim, "Strong's Number G5485 matches the Greek χάρις (charis), which occurs 76 times in 74 verses in the LXX Greek," then lists each OT verse with **inline Strong's numbers on every Greek word** (Gen 6:8 shows `Νωε G3575 δὲ G1161 εὗρεν G2147 χάριν G5485 ἐναντίον G1726 κυρίου G2962`). The same lexicon set to the NT text reports that charis "occurs 155 times in 147 verses in the MGNT Greek" (156×/147 verses in the TR) and that "The KJV translates Strong's G5485 in the following manner: grace (130x), favour (6x), thanks (4x), thank (4x), thank (with G2192) (3x), pleasure (2x), miscellaneous (7x)." URL pattern: `blueletterbible.org/lexicon/g{num}/lxx/lxx/0-1/`.
- **BibleHub** gives the fastest conceptual bridge: its Greek Strong's pages (`biblehub.com/greek/{num}.htm`) include a HELPS Word-studies note that often explicitly maps the Greek to a Hebrew Strong's number with a live hyperlink — the G5485 page says *charis* "answers directly to the Hebrew (OT) term 2580 /Kaná" and links to `biblehub.com/hebrew/2580.htm`. Thayer's on the same page also names the Hebrew, opening "χάρις, χάριτος... ἡ (χαίρω), from Homer down, Hebrew חֵן, grace." BibleHub's interlinear OT pages (`biblehub.com/interlinear/genesis/6-8.htm`) and text pages show the Hebrew word and its Strong's number.
- **STEP Bible** (Tyndale House, Cambridge) supports a URL-as-API Strong's search and carries a Strong's-tagged LXX, but does not offer general Hebrew-word alignment for the LXX.
- **studybible.info** is the tool the article itself uses; it has a Strong's-tagged LXX + Westcott-Hort and supports searching a Strong's number across a chosen version.
- **StudyLight** offers an interlinear with LXX at the bottom of OT verses and lexicons, but is weaker for occurrence-list searching by Strong's number.
- **Bible Gateway** has no Strong's/LXX word-search capability suited to this workflow and should not be relied on for it.

## Details

### Part 1 — Full summary of the moedim.dev article's principles and workflow

**Framing and audience.** The article is the opening methodology chapter of a "Discovering Moses" men's Bible study on the Messianic Judaism blog moedim.dev. It opens with the example of Moses as a leader and exhorts readers to become disciplined "People of the Book," citing Ed Stetzer's Christianity Today piece "The Epidemic of Bible Illiteracy in Our Churches," which reports a LifeWay Research finding that "only 45 percent of those who regularly attend church read the Bible more than once a week. Over 40 percent of the people attending read their Bible occasionally, maybe once or twice a month," and almost 1 in 5 churchgoers say they never read the Bible. It grounds the discipline in Psalm 119:11.

**Set-up goals.** Before studying, the reader is told to pray through four questions: Why do I study the Bible? What are my general goals? What are my group-study objectives? Do I have room to grow? 

**Recommended tools and the philosophy behind them.** Because "none of us are well versed in the original languages," the article says readers should use **Biblical dictionaries keyed to the original words** to recover meaning. This is the linchpin: the whole method is a way for non-specialists to reach original-language meaning through Strong's numbers and tools.

**The concept of 1st Mention.** The article's central interpretive principle: words change meaning over time (it gives the etymology of English "stench," once neutral/positive, now only negative), so "to understand the original biblical word meaning, we must go back to where it was 1st mentioned and based on the context of the text we can understand its meaning." The first occurrence of a word/concept in Scripture sets its foundational meaning.

**The worked example — "grace" (charis → chen).** The article demonstrates first-mention with Ephesians 2:8–9's "grace":
1. Go to studybible.info; select the **KJV with Strong's Numbers** version.
2. Search "Ephesians 2:8-9." Strong's numbers appear in green above the English words; "grace" = **G5485** (*charis*). Click G5485 for the Greek definition.
3. The article observes that searching G5485 across the KJV+Strong's returns **only New Testament** hits — "an incomplete search because the Bible wasn't originally written in Greek." It explains the Septuagint (LXX): the pre-Christian Jewish Greek translation of the Hebrew, which the NT writers knew and used.
4. To get the "1st mention" meaning it then does the **LXX bridge**:
   - On studybible.info, select the **Septuagint OT + Westcott-Hort NT** version.
   - Search **G5485**. This returns 30+ results **all from the Old Testament** (because the LXX is tagged with the same Greek Strong's numbers). The first is **Genesis 6:8** (Noah).
   - Genesis 6:8 in the LXX is in Greek and can't be read directly, so switch the search box to **KJV with Strong's Numbers** and search Genesis 6:8.
   - The result exposes the Hebrew word for grace — **"Hen" (chen), H2580**.
5. Interpretive payoff: the first mention of "grace" is Noah "finding grace/favor in the eyes of the LORD," so Ephesians 2's grace-through-faith is shown to be an Old Testament principle (Noah saved through faith by God's favor), reinforcing Paul's Jew-and-Gentile "one body" theme.

**Context principles.** After the word method, the article lays out interpretation rules: the **literal-historical method**; **Dr. David L. Cooper's "Golden Rule of Interpretation"** ("When the plain sense of Scripture makes common sense, seek no other sense; therefore, take every word at its primary, ordinary, usual, literal meaning unless the facts of the immediate context, studied in the light of related passages and axiomatic and fundamental truths, indicate clearly otherwise."); the **Law of Context** ("A text apart from its context is a pretext for anything anyone wants it to be"); attention to grammar, verb tense, and the journalistic questions (Who/What/When/Where/Why/How); and historical-cultural context.

**The e-Sword-dependent (or specific-tool-dependent) steps and their web replacements.** The article's method is tied to studybible.info, with e-Sword named as the offline alternative "with all of the online tools, plus many more." Each tool-specific step maps cleanly to a generic web equivalent:

| Article step (tool-specific) | Generic web-based replacement |
|---|---|
| Load "KJV with Strong's Numbers" and read Strong's number above English word | BLB verse interlinear, BibleHub interlinear (`/interlinear/{book}/{ch}-{v}.htm`), or STEP interlinear |
| Click Strong's number to get Greek definition | BLB lexicon (`/lexicon/g{num}/...`), BibleHub (`/greek/{num}.htm`), studybible.info Strong's page |
| Search G-number across KJV to see NT occurrences | BLB lexicon page's default concordance list; BibleHub `/greek/strongs_{num}.htm` |
| Switch to "Septuagint OT + Westcott-Hort" and search the G-number to find OT/LXX occurrences | **BLB LXX lexicon tab** (`/lexicon/g{num}/lxx/lxx/0-1/`) — the cleanest replacement; or STEP `text=strong:G{num}` with the LXX version loaded; or studybible.info LXX_WH |
| Re-search the resulting OT verse in KJV+Strong's to read the Hebrew word | BibleHub interlinear/text OT page for that verse; BLB OT verse interlinear; StudyLight interlinear |
| e-Sword desktop for offline lexicons/commentaries | Any of BLB, BibleHub, STEP, studybible.info in the browser |

### Part 2 — Tool comparison with URL patterns an AI agent can construct

**Blue Letter Bible (blueletterbible.org).**
- (a) Strong's lookup, Greek and Hebrew: `blueletterbible.org/lexicon/g{num}/{translation}/{textform}/0-1/` for Greek and `.../h{num}/...` for Hebrew. Example: `/lexicon/g5485/kjv/tr/0-1/`. Includes Strong's definition, Thayer's, Gesenius (facsimiles), KJV translation counts, and outline of biblical usage.
- (b) Find a Greek word in the LXX: **Yes — this is BLB's decisive advantage.** Set the lexicon context to LXX: `/lexicon/g5485/lxx/lxx/0-1/`. The page reports the LXX occurrence count ("76 times in 74 verses in the LXX Greek") and lists every LXX verse with inline Strong's on each Greek word.
- (c) Greek→Hebrew mapping via LXX: done **by reading**, not by an automatic cross-map. On the LXX occurrence list, you identify the OT verse (e.g., Gen 6:8), then open that verse's OT interlinear/lexicon to read the Hebrew word and its H-number. BLB's lexicon pages also carry Thayer's/Gesenius, and Thayer's for G5485 itself names the Hebrew ("Hebrew חֵן, grace").
- (d) Concordance/occurrence lists: yes, both NT (mGNT/TR) and LXX, filterable by book range via the Advanced Options selector.
- (e) URL patterns: highly regular and agent-friendly — `/lexicon/g{num}/{ver}/{textform}/0-1/`; LXX chapter pages `/lxx/{book}/{ch}/{v}/`; search results `/search/search.cfm?Criteria={term}&t=LXX`.
- (f) Morphology/interlinear: yes; the interlinear tool shows the LXX Greek at the bottom of OT verses and TR/mGNT for NT verses; "↑" arrows flag when multiple Strong's numbers map to one English word.

**BibleHub (biblehub.com).**
- (a) Strong's lookup: `biblehub.com/greek/{num}.htm` and `biblehub.com/hebrew/{num}.htm`. Rich stack per page: Strong's, HELPS Word-studies, NAS Exhaustive Concordance, Thayer's, and Englishman's Concordance.
- (b) Find a Greek word in the LXX: partial. BibleHub hosts Brenton's Septuagint (`/sep/{book}/{ch}.htm`) and an **Apostolic Bible Polyglot interlinear Septuagint** (`/interlinear/apostolic/{book}/{ch}.htm`) keyed to AB-Strong's numbers, but it does not offer a one-click "all LXX occurrences of G{num}" concordance the way BLB does; the AB-Strong's numbering is a modified system.
- (c) Greek→Hebrew mapping: **BibleHub is the fastest bridge for the mapping itself.** The HELPS Word-studies note on many Greek pages names the Hebrew equivalent and hyperlinks it (G5485 → "the Hebrew (OT) term 2580," linked to `/hebrew/2580.htm`); Thayer's frequently names the Hebrew (חֵן). For any specific OT verse, the interlinear (`/interlinear/{book}/{ch}-{v}.htm`) and text-analysis (`/text/{book}/{ch}-{v}.htm`) pages give the Hebrew word and H-number.
- (d) Concordance/occurrence lists: yes — `/greek/strongs_{num}.htm` ("157 Occurrences") and Englishman's Concordance.
- (e) URL patterns: the most stable and predictable on the web — `/greek/{num}.htm`, `/hebrew/{num}.htm`, `/interlinear/{book}/{ch}-{v}.htm`, `/text/{book}/{ch}-{v}.htm`, `/sep/{book}/{ch}.htm`. These have been stable for many years (one reviewer notes `biblehub.com/john/3-16.htm` "has not moved in fifteen years").
- (f) Morphology/interlinear: yes, full parsing per word.

**STEP Bible (stepbible.org).**
- (a) Strong's lookup: hover/click any word in the interlinear; Greek and Hebrew dictionaries built in (TBESG Greek/Abbott-Smith + LSJ; TBESH Hebrew/BDB).
- (b) Find a Greek word in the LXX: **Yes.** STEP carries a Strong's-tagged LXX (version code `LXX`, "Septuagint, Morphologically Tagged Rahlf's (1935)," tagging upgraded by Tyndale House to line up with the Tyndale Full LSJ lexicon; plus `ABGk`, the Apostolic Bible Polyglot Greek "coded to an extended Strong's lexicon"). A Strong's search returns LXX hits when an LXX version is loaded.
- (c) Greek→Hebrew via LXX: **limited** — per STEP's own data repository, the LXX dataset (TAGOT) is "tagged to LSJ using disambiguated Hebrew numbers for names only in the OT," i.e. Hebrew Strong's cross-tags exist **for proper names only**, not general vocabulary. STEP is therefore not a full MT↔LXX word-alignment tool; use it to locate LXX occurrences, then read the Hebrew elsewhere. STEP's FAQ likewise warns, "Not every word in the NT can be tied up with a Hebrew word easily."
- (d) Concordance/occurrence lists: yes, via search.
- (e) URL patterns (URL-as-API): base `https://www.STEPBible.org/?q=...`, sub-params joined by `|` (encoded `%7C`). STEP's docs state "STEP Bible uses the URL as an API... The link can be as simple as: `https://www.STEPBible.org/?q=reference=John.3.16-20`." Strong's search prefix is documented as "strong (strong:H0001): runs a search for a particular Strong number." Concrete examples: Strong's search `?q=version=ESV|text=strong:G5485`; load LXX + search `?q=version=LXX|version=ESV|text=strong:G5485`; alternative Greek-word prefix (which "Supports... Strong numbers") `?q=version=LXX|og=G5485`; restrict to OT with the Lucene range `[Gen-Mal]`; open LXX at a reference `?q=version=LXX|reference=Gen.1.1`.
- (f) Morphology/interlinear: excellent — any version can set word order; hover highlights all occurrences on screen.

**studybible.info** (the article's own tool).
- Strong's-tagged KJV+Strong's, LXX (LXX_WH: "Septuagint LXX Greek Old Testament keyed to Strong's numbers with complete parsing information, and Wescott and Hort 1881 Greek New Testament... keyed to Strong's numbers"), Vulgate, interlinear, TSK cross-references, Thayer's/BDB/Vine's. Free, no login. Searching a Strong's number against the LXX_WH version reproduces the article's exact step. Weakness: utilitarian UI, less regular URL scheme for programmatic construction than BLB/BibleHub.

**StudyLight (studylight.org).** Interlinear study Bible shows the LXX Greek at the bottom of each OT verse (`/interlinear-study-bible/hebrew/{book}/{ch}-{v}.html`) and provides individual Greek↔Hebrew word correspondences and BDB/Gesenius + Thayer's lexicons. Useful as a cross-check and for reading the Hebrew of a target verse, but its by-Strong's-number LXX occurrence search is weaker than BLB's.

**Bible Gateway.** Excellent for reading many modern translations, but it lacks the Strong's-number LXX concordance search this workflow depends on; not recommended as a primary or secondary tool here.

**Recommendation.** Use **BLB as the primary engine** for the Greek→LXX occurrence search (its LXX lexicon tab is the single cleanest, most agent-constructible replacement for the article's e-Sword/studybible.info step) and **BibleHub as the companion** for (i) the fast Greek→Hebrew conceptual bridge (HELPS/Thayer's naming the Hebrew number) and (ii) reading the Hebrew word and H-number of any specific OT verse via its interlinear. Keep **STEP** and **studybible.info** as free, no-login backups, and consult the **Hatch-Redpath** concordance when you need the exhaustive list of Hebrew words a Greek word renders.

### Part 3 — The scholarly method for tracing a NT Greek word to its OT Hebrew equivalent

**Why the LXX is the bridge.** The Septuagint (LXX) is the pre-Christian Greek translation of the Hebrew Bible; the NT authors quoted it heavily. Because the LXX renders known Hebrew words with Greek words, a Greek NT word can be mapped to the Hebrew word(s) the LXX translators used for it. This is exactly the article's method, and it is a recognized (if informal) lexical technique. As one Messianic-study reviewer of Strong's-keyed interlinear Septuagints puts it: "When used alongside a Hebrew text, it is possible to determine what Greek word was used to translate the Hebrew word, and then to find that same Greek root word in the New Testament."

**The core procedure (concordance/LXX method):**
1. Start with the NT Greek word and its Strong's number (from the NT interlinear).
2. Find that same Greek Strong's number's occurrences in the LXX (the Greek OT).
3. For each LXX occurrence, identify the Hebrew word it translates in that verse (read the Hebrew interlinear/text of that OT verse).
4. Collect the Hebrew Strong's number(s). The most frequent equivalent is the "normal" gloss; rare ones are exceptions.

**Handling multiple Hebrew equivalents.** This is the method's key caveat. One Greek word often translates several Hebrew words (e.g., *kyrios* commonly renders YHWH but also *adon*), and one Hebrew word can be rendered by several Greek words. Therefore:
- Do not treat the "first mention" in the LXX as the definitive Hebrew equivalent; treat it as one hypothesis.
- Survey **all** LXX occurrences and note the distribution of Hebrew words behind them.
- Use a resource that gives the full equivalence set: the **Hatch-Redpath Concordance to the Septuagint** (the standard scholarly work; three volumes plus a Supplement volume, all with full scans on the Internet Archive) and **Dos Santos's "Expanded Hebrew Index for the Hatch-Redpath Concordance"** (a free ~230-page PDF via Jerusalem Perspective, which "enables users to determine what Greek equivalents were used to translate a given Hebrew term and also the frequency with which these equivalents occurred") or Muraoka's Hebrew/Aramaic index keyed to Hatch-Redpath.
- Cross-check with a lexicon that cites Hebrew equivalents (Thayer's, HELPS Word-studies, BDB).

**Complementary approaches (the skill should support all three):**
1. **LXX lexical bridge** (above) — word-level.
2. **Thematic/conceptual connections** — trace an idea (grace, covenant, redemption) rather than a single lexeme; the article's Noah conclusion is really conceptual.
3. **NT quotations/allusions of the OT** — where the NT explicitly quotes the OT, the OT source (and its Hebrew) is given directly. Use published indexes: the tables at kalvesmaki.com and bible-researcher.com (NT | LXX | MT columns) and the quotation appendix in *The Greek New Testament* (UBS, 4th ed., pp. 891–901). Easton's Bible Dictionary counts "two hundred and eighty-three [283] direct quotations from the Old Testament in the New." On the LXX's predominance in those quotations, Gleason Archer and Gregory Chirichigno's *Old Testament Quotations in the New Testament: A Complete Survey* "list 340 places where the New Testament cites the Septuagint but only 33 places where it cites from the Masoretic Text rather than the Septuagint"; and Natalio Fernández Marcos (*The Septuagint in Context*, 2000) reports that NT quotations "diverge from the Masoretic text in 212 cases, whereas they differ from the Septuagintal text in only 185 cases."

**Standard free online lexical resources:**
- **Thayer's** Greek lexicon — on BLB and BibleHub Greek pages.
- **BDB (Brown-Driver-Briggs)** and **Gesenius** Hebrew lexicons — on BibleHub Hebrew pages, StudyLight, BLB (Gesenius facsimile).
- **LSJ (Liddell-Scott-Jones)** — via STEP (Tyndale's formatted full LSJ, "TFLSJ") and Perseus.
- **HELPS Word-studies** — BibleHub (often names the Hebrew equivalent).
- **TDNT (Kittel), abridged** — BibleHub/BLB link Greek numbers to Kittel ("Theological Dictionary of the New Testament"); the full TDNT is not free, but summary/keyed data is surfaced on these sites.
- **Hatch-Redpath Concordance to the Septuagint** — full scans on the Internet Archive (Vol. 1 Α–Ι, Vol. 2 Κ–Ω, and the Supplement with the Hebrew index); Dos Santos's Expanded Hebrew Index free PDF via Jerusalem Perspective.
- **STEPBible-Data** (GitHub, CC BY) — open lexicons TBESH (Hebrew/BDB), TBESG (Greek/Abbott-Smith), TFLSJ (LSJ), and the TAGOT tagged Greek OT, for programmatic use.

## Recommendations

**Encode this staged procedure into the skill file:**

**Stage 0 — Identify the Greek word.** Given a NT reference and target English word, fetch the NT interlinear (`biblehub.com/interlinear/{book}/{ch}-{v}.htm` or BLB verse interlinear) and read off the Greek word and its Strong's number G{num}.

**Stage 1 — Understand the Greek word.** Fetch `biblehub.com/greek/{num}.htm` (Strong's + HELPS + Thayer's) and/or `blueletterbible.org/lexicon/g{num}/kjv/tr/0-1/`. **Capture any Hebrew equivalent the lexicon names directly** (HELPS/Thayer's often give the H-number — for G5485, HELPS names H2580 and Thayer's names חֵן — this can shortcut Stages 2–4 and should always be recorded as corroboration).

**Stage 2 — Find the word in the LXX.** Fetch `blueletterbible.org/lexicon/g{num}/lxx/lxx/0-1/`. Record the LXX occurrence count and the full list of OT verses (each with inline Strong's). Backup: STEP `https://www.STEPBible.org/?q=version=LXX|text=strong:G{num}` or studybible.info LXX_WH search.

**Stage 3 — Read the Hebrew behind each LXX occurrence.** For the first mention and for the most frequent occurrences, open the OT verse's Hebrew interlinear (`biblehub.com/interlinear/{book}/{ch}-{v}.htm`) or text analysis (`biblehub.com/text/{book}/{ch}-{v}.htm`) and read the Hebrew word aligned to the target Greek word; record its Strong's H{num}.

**Stage 4 — Resolve multiple equivalents.** Tabulate the Hebrew word(s) across all (or a representative sample of) LXX occurrences. Report the dominant Hebrew equivalent plus notable alternates. For exhaustive equivalence, consult Hatch-Redpath (Internet Archive) / Dos Santos index.

**Stage 5 — Corroborate.** Confirm the Greek↔Hebrew link three ways where possible: (a) lexicon citation (HELPS/Thayer's/BDB), (b) LXX distribution (Stage 4), (c) if the NT verse quotes/alludes to an OT passage, check an NT-OT quotation index (kalvesmaki.com, bible-researcher.com) and read that OT passage's Hebrew directly.

**Stage 6 — Interpret (first-mention + context).** Apply the article's principles: read the full context of the first-mention OT passage, apply the literal-historical method and Cooper's Golden Rule, and state the conceptual/thematic thread from OT to NT.

**Benchmarks that change the approach:**
- If the lexicon (Stage 1) already names a single Hebrew equivalent and the LXX distribution (Stage 4) is dominated by that same word → high confidence; you can stop.
- If the LXX shows **several roughly equally frequent** Hebrew equivalents → do not assert one Hebrew word; report the range and lean on the NT-quotation method or thematic method instead.
- If the Greek word is rare or absent in the LXX → the LXX bridge fails; fall back to (a) lexicon Hebrew citations, (b) cognate/root analysis, (c) thematic study.
- If BLB's LXX tab is unavailable for a number → use STEP's `text=strong:G{num}` with `version=LXX`, then studybible.info.

## Caveats
- **Strong's is a KJV-era index, not a modern critical lexicon.** It groups word forms crudely; treat Strong's numbers as pointers into better lexicons (BDB, LSJ, Thayer's), not as final semantic authorities.
- **The LXX bridge is directional and lossy.** The LXX is a translation with its own interpretive choices; a Greek word's LXX Hebrew source is evidence of how Hellenistic Jews understood a word, not proof of an etymological identity. One-to-many and many-to-one Greek↔Hebrew mappings are the norm, so a single first-mention hit can mislead.
- **AB-Strong's ≠ Strong's.** The Apostolic Bible Polyglot LXX (used on BibleHub and as STEP's ABGk) uses a *modified* numbering system created because "Strong's concordance doesn't have numbering for the Greek O.T."; do not assume its numbers equal standard Greek Strong's numbers without checking.
- **STEP's LXX Hebrew alignment covers proper names only**, per STEP's own data documentation — it is not a general MT↔LXX word-alignment engine.
- **NT quotations rarely match the LXX verbatim** and sometimes align closer to the Masoretic Text; the "~2/3 of quotes come from the LXX," "283/~300 OT quotations," and the Archer-Chirichigno "340 vs. 33" and Marcos "212 vs. 185" figures come from different counting methods and definitions of what counts as a quotation, so present them as competing estimates rather than a single settled number.
- **The moedim.dev article is a popular Messianic-Judaism devotional piece (2016), not a peer-reviewed scholarly method.** Its "first mention" principle is a teaching heuristic, not an established rule of academic exegesis; the skill should present it as a productive starting frame, balanced by the context and multiple-equivalents cautions above.
- **URL patterns can change.** BibleHub and BLB patterns have been stable for years, but an AI skill should fetch and verify (check the occurrence count and that the returned Strong's number matches) rather than trust a constructed URL blindly.