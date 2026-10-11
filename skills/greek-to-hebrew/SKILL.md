---
name: greek-to-hebrew
description: "Trace a New Testament Greek word to possible Old Testament Hebrew equivalents through the Septuagint (LXX). Use when studying a NT word, Strong's number, Greek-to-Hebrew bridge, LXX occurrence, first mention, Bible word study, or NT quotation/allusion of the OT."
license: CC-BY-SA-4.0
metadata:
  version: "1.0.0"
  argument-hint: "NT reference and target English or Greek word, e.g. Ephesians 2:8 grace"
---

# Greek to Hebrew word trace (`greek-to-hebrew`)

Trace a New Testament Greek word to the Hebrew words behind its Old Testament uses, through the Septuagint (LXX), using only free web-based tools. Produce a transparent, context-aware study rather than an etymological shortcut.

The method is adapted from the moedim.dev articles [Principles for the Study of the Bible: Word Study](https://moedim.dev/posts/principles-for-the-study-of-the-bible-word-study) and [Principles for the Study of the Bible](https://moedim.dev/posts/principles-for-the-study-of-the-bible): recover original-language meaning through Strong's numbers, find the word's first mention, and interpret in context.

## Read on demand

- [references/tools.md](references/tools.md): URL patterns for Blue Letter Bible, BibleHub, STEP Bible, studybible.info, and StudyLight, plus a failure-mode playbook. Read it when a URL fails, returns unexpected content, or you need a capability not covered here.
- [references/methodology.md](references/methodology.md): the research behind this skill, including a summary of the moedim.dev method, a tool comparison, and the scholarly caveats. Read it when the user wants the reasoning or deeper sources.

## Why this works

The Septuagint is the pre-Christian Greek translation of the Hebrew Bible, and it is tagged with the **same Greek Strong's numbers** as the New Testament. A Greek word from the NT can therefore be searched in the LXX, which lands in Old Testament verses. The Hebrew text behind each of those verses shows which Hebrew word (and Hebrew Strong's number) the Greek word translates there:

```text
NT word -> Greek lemma + G-number -> LXX occurrences (OT verses)
        -> Hebrew word behind each verse -> H-number -> first-mention study in context
```

## Boundaries

- Treat Strong's numbers as lookup keys and pointers into better lexicons, not as complete lexical definitions.
- Treat the LXX as translation evidence. It shows how Hellenistic Jewish translators understood a word; a Greek-to-Hebrew connection does not prove the words are etymological or semantic equivalents.
- One Greek word may translate several Hebrew words, and one Hebrew word may have several Greek renderings. Never infer a unique Hebrew equivalent from one occurrence.
- Treat first mention as a teaching heuristic. It does not override immediate context, grammar, genre, historical setting, or the word's complete usage.
- Keep lexical tracing distinct from a quotation or allusion study. When the NT quotes the OT, identify and examine the OT source directly.
- BibleHub's Apostolic Bible Polyglot LXX (and STEP's `ABGk`) uses **modified** "AB-Strong's" numbers. Do not treat them as standard Greek Strong's numbers without verification.

## Inputs

Obtain:

- The NT reference.
- The target English word, Greek lemma, or Greek Strong's number.
- Whether the user wants a concise result or a broad survey of LXX equivalents.

If the user gives only an English word with no verse, ask for one, or propose the best-known NT verse that uses it and confirm. If the English word could correspond to more than one Greek word in the verse, list the candidates with glosses and ask which to trace.

## Procedure

Use your web fetch tool to retrieve pages, constructing URLs from the patterns below. Verify each page before relying on it: the Strong's number on the page must match the one you requested.

### 1. Identify the NT Greek word

1. Open the verse interlinear: `https://biblehub.com/interlinear/{book}/{chapter}-{verse}.htm` (book lowercase, numbered books like `1_corinthians`).
2. Locate the target word in its clause. Record the Greek lemma, transliteration, morphology when relevant, and standard Strong's number `G{number}`.
3. Confirm the number with at least one Greek lexicon:
   - BibleHub: `https://biblehub.com/greek/{number}.htm` (no leading zeros)
   - Blue Letter Bible: `https://www.blueletterbible.org/lexicon/g{number}/kjv/tr/0-1/`

The verse's actual Greek form controls the study; do not select a Greek word only because its English gloss resembles the requested word.

### 2. Establish the Greek lexical range

1. Read the Strong's entry and a substantive lexicon, such as Thayer's, HELPS Word-studies, or LSJ through STEP Bible.
2. Record only senses relevant to the NT context, plus the NT occurrence count.
3. **Check HELPS and Thayer's for a named Hebrew equivalent.** They often state it directly (for `G5485` *charis*, HELPS links Hebrew 2580 and Thayer's names חֵן). Record it as a hypothesis to test in steps 3-5, not as the conclusion.
4. Note the word class and any morphology or cognate distinction that affects the result.

### 3. Locate the Greek word in the LXX

1. Use Blue Letter Bible's LXX concordance as the primary occurrence search:
   `https://www.blueletterbible.org/lexicon/g{number}/lxx/lxx/0-1/`
2. Verify that the page matches the requested `G{number}` and is in LXX mode.
3. Record the stated occurrence count, the earliest occurrence in canonical order (the first mention), and the spread of books and contexts.
4. If BLB does not expose the expected data, use STEP Bible as a locator: `https://www.stepbible.org/?q=version=LXX|text=strong:G{number}`. Use studybible.info's `LXX_WH` Strong's search as a second backup.

**If the word does not occur in the LXX**, the lexical bridge fails. Say so plainly, then fall back to the Hebrew equivalent named by the lexicons in step 2, Greek cognates that do occur in the LXX, and the thematic method under [Complementary methods](#complementary-methods).

### 4. Read the Hebrew behind selected LXX occurrences

Select the first mention **and** at least 3-5 representative occurrences, more if the results diverge. Include occurrences relevant to the NT sense. For each:

1. Open a Hebrew interlinear or text analysis page:
   - `https://biblehub.com/interlinear/{book}/{chapter}-{verse}.htm`
   - `https://biblehub.com/text/{book}/{chapter}-{verse}.htm`
2. Read the Hebrew word aligned to the LXX target. Record its spelling, transliteration, gloss, and `H{number}`.
3. Confirm the alignment from phrase and syntax. LXX and Masoretic Text word order or segmentation may differ.
4. Capture the immediate literary context and grammatical details that affect meaning.

Then fetch `https://biblehub.com/hebrew/{number}.htm` for each Hebrew word's definition, root, and OT usage.

STEP's LXX data is useful for locating Greek occurrences, but its Hebrew cross-tags cover proper names only; it is not a general MT-to-LXX alignment system.

### 5. Resolve multiple Hebrew equivalents

This is the method's biggest pitfall. Tabulate the observed Hebrew lemmas, Strong's numbers, and references, then apply these rules:

- A strongly dominant equivalent corroborated by a lexicon may be reported as the most common LXX rendering, with alternates noted.
- Several substantial equivalents require a range, not a claim that the Greek word means one Hebrew word. Lean on the quotation and thematic methods instead.
- Rare or absent LXX occurrences make the bridge inconclusive; use lexicon citations, cognates, and thematic context.
- An explicit NT quotation or allusion takes priority: identify the OT source, read its Hebrew directly, and compare MT and LXX wording when relevant.
- The first-mention verse's Hebrew word is a starting hypothesis, never proof. Always check it against the distribution.

For an exhaustive equivalence list, point users to Hatch-Redpath's *Concordance to the Septuagint* (scans on the Internet Archive) and its Hebrew index, including the Dos Santos expanded index.

### 6. Corroborate and assign confidence

Seek at least two independent forms of support where practical:

1. A Greek lexicon (HELPS, Thayer's) naming the Hebrew equivalent.
2. The observed LXX-to-Hebrew distribution from step 5.
3. A Hebrew lexicon such as BDB or Gesenius.
4. An NT-OT quotation or allusion index (kalvesmaki.com, bible-researcher.com). A direct quotation is the strongest possible link.

Do not invent a quotation link. If no reliable index identifies one, describe the relationship only as a possible thematic connection.

State one confidence level in the report:

- **High**: lexicon citation, a dominant LXX pattern, and a quotation or allusion all agree.
- **Moderate**: lexicon citation plus a dominant LXX pattern.
- **Tentative**: a single first-mention hit, a mixed distribution, or a word rare or absent in the LXX.

### 7. Interpret in context

Read the full NT paragraph and the relevant OT passage. Explain the speaker, audience, grammar, verb tense, genre, historical setting, and surrounding argument. Apply these interpretive principles from the source method:

- **First mention**: read the full context of the earliest OT occurrence; it suggests the word's foundational biblical sense. Label this as a heuristic.
- **Law of context**: "a text apart from its context is a pretext." Ask who, what, when, where, why, and how.
- **Literal-historical method and Cooper's Golden Rule**: take the plain sense unless the immediate context, read with related passages, clearly indicates otherwise.

Separate the final claims into:

- **Lexical evidence:** what the Greek and Hebrew words can mean.
- **Translation evidence:** how LXX translators rendered Hebrew in the selected texts.
- **Thematic connection:** the possible OT-to-NT conceptual thread.
- **Exegetical conclusion:** what the NT passage means in its own context.

## Complementary methods

Offer these alongside the lexical trace:

1. **Thematic tracing**: follow the idea (covenant, redemption, grace) across both testaments, not just the word. Use it when the lexical bridge is weak or the question is conceptual.
2. **NT quotations of the OT**: where the NT explicitly quotes the OT (Easton counts about 283 direct quotations; other counts differ by method), the Hebrew source is given directly. Always check whether the user's verse is one of them.

## Output format

Use this structure unless the user requests a shorter answer:

```markdown
## Word Trace: {English word} in {NT reference}

- **NT Greek:** {lemma} ({transliteration}), `G{number}`; {sense and morphology}
- **Greek lexical evidence:** {findings and any direct Hebrew citation}
- **LXX survey:** {verified count}; first mention {reference}; {scope surveyed}

| LXX OT reference | LXX Greek | Hebrew behind the verse | Strong's | Context note |
|---|---|---|---|---|
| {reference} | {Greek} | {Hebrew word} ({transliteration}, {gloss}) | `H{number}` | {note} |

- **Most supported Hebrew equivalent(s):** {word}, {transliteration}, `H{number}`; {distribution}
- **Confidence:** {high / moderate / tentative}; {corroborating evidence}
- **Alternatives / limits:** {other equivalents or uncertainty}
- **First-mention observation:** {the earliest OT passage in context, labeled as a heuristic}
- **Contextual thread:** {how the OT usage may illuminate the NT verse}
- **Sources checked:** {URLs or named resources}
```

Keep the tone reverent but scholarly-honest: flag uncertainty and never overstate a lexical link.

## Quality checks

Before finalizing, verify that:

- `G{number}` comes from the actual NT word in context.
- The BLB URL is in LXX mode and returns the requested number.
- Each Hebrew result includes the verse-level spelling, transliteration, gloss, and `H{number}`.
- Hebrew alignment was checked rather than assumed from word position.
- Multiple Hebrew equivalents are reported when the evidence shows them.
- The confidence level matches the corroboration actually found.
- Lexical, translational, thematic, and exegetical claims are clearly separated.
- First mention is explicitly presented as a heuristic.
- Conclusions do not depend on a Strong's number alone.

## Worked example: grace

For "grace" in Ephesians 2:8, verify *charis*, `G5485`, in the NT interlinear. HELPS and Thayer's name Hebrew חֵן (*chen*, `H2580`) as the equivalent; record it as a hypothesis. Query BLB's `G5485` LXX concordance; the first mention is Genesis 6:8, where Noah "found grace in the eyes of the LORD." Confirm in a Hebrew interlinear that *chen* sits in the aligned slot, then survey additional LXX uses before claiming it is the only equivalent. Explain Genesis 6 in its own context before drawing the thematic connection to Ephesians 2, where grace through faith appears as a principle already present in the Old Testament.
