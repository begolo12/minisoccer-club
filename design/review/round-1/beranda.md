# Round 1 review — Beranda + Login

Reviewer: independent (did not build this UI). Method: `oil-ui` reviewer manual §2 (existing-UI alignment to spec, no scoring).
Evidence: static PNGs in `design/current/`. No interaction, no running preview, no source read.
Frames read: `beranda-hp.png` (390x844@2x), `beranda-320.png` (320x800), `beranda-desktop.png` (1440x900), `beranda-terang.png` (390x844), `login-hp.png` (390x844@2x), `login-desktop.png` (1440x900).

Measured from the pixels (not estimated): hero card fill `#0C1A12`, hero border `#1F6C43` (dark) / fill `#EAF6EE`, border `#9BCCB2` (light); light accent `#0A7D43`; light money `#7A5C00`; stat-strip fill = page bg; desktop rail divider at x=215; content column x=359→1293; login inputs 37px / 57px / button 42px.

---

## 1. Quick checklist

### Problems (highest impact first)

- **[problem 1]** `beranda-hp.png`, `beranda-terang.png` / bottom of page, "KAS BULAN INI" block: the block's bottom hairline never appears — it runs under the bottom nav, and the nav has no top hairline and no surface of its own (nav bg = page bg `#080B09` dark, `#F2F5F1` light), so the last row is cut with no boundary. -> Acceptance: at 390x844 in both themes the Kas block's full border is visible with ≥16px of clear space above a nav that has a 1px `#202C25` / `#D8E0D9` top hairline.
- **[problem 2]** `beranda-hp.png`, `beranda-320.png`, `beranda-terang.png`, `beranda-desktop.png` / "TURNAMEN BERIKUTNYA" + "TURNAMEN TERAKHIR": the same object type is rendered twice, in two different components — a 64px hairline row above and a ~100–110px filled card below — so the home reads as a fixture list and the club numbers are pushed down. -> Acceptance: one "Turnamen" section; each tournament is a RowItem of equal height (~64px) with no card fill; the "4/6 laga" progress survives as one line inside the row.
- **[problem 3]** `login-desktop.png` / left half: the only task on the screen (the form) is the secondary column — a 356px card at x=833 behind a marketing column whose two-line display headline and `01/02/03` list carry more weight than the form. -> Acceptance: the form is the first thing the eye lands on at 1440x900; the `01/02/03` list is gone (see §5), leaving the headline + one support line as the left column.
- **[problem 4]** `beranda-desktop.png` / "AKSI CEPAT": a three-column grid of shortcut tiles whose visible labels repeat destinations already in the left rail (`Tim`, `Tanding`, `Turnamen`), and its second row is sliced in half by the 900px fold. -> Acceptance: block removed; at 1440x900 the left column ends on the Kas block with ≥24px below it and no row is cut by the viewport edge.
- **[problem 5]** `beranda-desktop.png` / right column: three lists share one column but use four different left anchors — names at x=933 ("Belum Bayar"), 965 ("Top Skor"), 967 ("Klasemen"), and the rank gutter at 936 vs 949 between the two ranked lists — and Klasemen is the only one boxed inside a Panel while the other two are open hairline rows. -> Acceptance: names share one anchor (933) and the rank gutter is one x for both ranked lists; all three lists use the same open hairline-row treatment.

### Improvements

- **[improvement 1]** `login-hp.png`, `login-desktop.png` / form: username field is 37px tall, password field 57px, submit button 42px — three heights in one form, because the eye-icon sets the password field's intrinsic height. -> Target: all three at one height (44px) with the icon constrained inside it.
- **[improvement 2]** `beranda-hp.png`, `beranda-320.png` / three-number strip: the third value ("Rp 1.950.000") has a cap height of ~10px against ~26px for "31" and "4", so the money reads as a caption under two hero numbers. -> Target: one numeral size across the three tiles.
- **[improvement 3]** `beranda-hp.png`, `beranda-terang.png` / tournament progress bar: the track is `#141D18` on `#0E1512` (1.07:1) in dark and `#E7EDE6` on `#FFFFFF` (1.19:1) in light — effectively invisible, so the bar has no visible total. -> Target: track at hairline colour, so "4/6" is readable from the bar alone.
- **[improvement 4]** `beranda-hp.png` / section titles: the three rules in one column end at three different x positions — 370 (content edge) for "TURNAMEN BERIKUTNYA", 291 for "TURNAMEN TERAKHIR", 304 for "KAS BULAN INI" — because each action link has a different width. -> Target: one rule endpoint per column (the action sits at the right edge, the rule stops at a fixed x).
- **[improvement 5]** `login-hp.png`, `login-desktop.png` / background graphic: the pitch circle/centre-line is drawn under the card — on phone its arc enters the card's top corners at y≈155 as two stray diagonal hairlines; on desktop the centre line runs edge to edge at y≈377 and stops dead at the card's left edge (x=833) and resumes at x=1190. -> Target: the graphic is clipped outside the card's bounds so no line appears to enter or leave the card.

**Clean / not a problem:** red appears only on the five overdue amounts in `beranda-desktop.png` — the "red = failure/overdue only" rule holds. No horizontal overflow at 320 in `beranda-320.png` (the hero meta wraps to two lines instead). Light-theme green (`#0A7D43` on `#F2F5F1` = 4.74:1) and amber (`#7A5C00` on `#F2F5F1` = 5.69:1, on `#FFFFFF` = 6.25:1) pass — see §2 for the light-theme items that do fail.

**Not verifiable from this set (not counted as defects):** no-match hero state (every Beranda frame has an ongoing match); login error/validation state (neither login frame shows an error, hint slot, or invalid field); light-theme login (not captured); login at 320px (not captured); "Aksi Cepat" at 320px — the block does not exist in any phone frame (`beranda-hp.png`, `beranda-320.png`, `beranda-terang.png` all end after Kas), so the 320px fit question cannot be answered; member role (no member frame in this set).

---

## 2. Spec deviations

Colors sampled directly from the PNGs; where a value matched the spec exactly it is not listed.

| # | Deviation | Where |
|---|---|---|
| D1 | Hero card border is accent green `#1F6C43`, not the hairline `#202C25`; card fill is a green tint `#0C1A12`, not `#0E1512`. | `beranda-hp.png`, `beranda-320.png`, `beranda-desktop.png` |
| D2 | Same card in light: border `#9BCCB2` (1.62:1 against its own fill, effectively invisible) instead of `#D8E0D9`; fill `#EAF6EE` instead of card `#FFFFFF`. | `beranda-terang.png` |
| D3 | Light accent is `#0A7D43` everywhere (score, "Semua"/"Buka" links, progress fill, "Isi hasil" fill, "BERJALAN" label) — spec light accent is `#0E7C48`. | `beranda-terang.png` |
| D4 | Light money is `#7A5C00` — spec light money is `#8A5A00`. | `beranda-terang.png` |
| D5 | Panel has two treatments on the same screen: the tournament card is filled (`#0E1512` / `#FFFFFF`) while the three-number strip and the Kas block are unfilled (page bg `#080B09` / `#F2F5F1`) with the same hairline. Same component name, two fills. | `beranda-hp.png`, `beranda-terang.png` |
| D6 | Bottom nav has no surface of its own and no top hairline — nav bg equals page bg in both themes (`#080B09`, `#F2F5F1`). | `beranda-hp.png`, `beranda-320.png`, `beranda-terang.png` |
| D7 | Nav active state introduces a colour outside the palette: pill `#0E261A` (dark) / `#D1E4D8` (light). The desktop rail's active item uses yet another tint, `#0C1F15` — same state, two tints. | `beranda-hp.png` vs `beranda-desktop.png`; `beranda-terang.png` |
| D8 | Lists are not hairline rows here: "Turnamen Terakhir" is a filled, bordered card, and the Klasemen table is wrapped in a Panel while the two lists above and below it in the same column are open rows. Spec: lists are hairline rows, never stacked cards. | `beranda-hp.png`, `beranda-320.png`, `beranda-terang.png`, `beranda-desktop.png` |
| D9 | Text set in the condensed score face: "Halo, Admin" and the login headline "Kelola klub dalam satu papan." are set noticeably narrower (glyph advance ≈0.6 of cap height) than the list titles, e.g. "Turnamen Akhir Pekan" (≈0.9). Spec assigns Barlow Condensed to numerals/score and Inter to text, and the two heading treatments here do not match each other. Confirm whether the display use is intended; if yes, at minimum the greeting and the login headline should share one face. | `beranda-hp.png`, `beranda-desktop.png`, `login-hp.png`, `login-desktop.png` |
| D10 | Money colour applied selectively: "IURAN Rp 1.950.000" and "SALDO Rp 2.670.000" are amber, but "MASUK Rp 3.700.000" and "KELUAR Rp 1.030.000" — same money class, same strip — are neutral white. | `beranda-hp.png`, `beranda-terang.png`, `beranda-desktop.png` |
| D11 | Section title rule does not run to the right edge where an action link exists: in `beranda-hp.png` the first section's rule reaches the 370px content edge, but the other two stop at 291 and 304 because the link widths differ. Spec asks for a rule running to the right edge, and at minimum the endpoint should be one fixed x per column. | `beranda-hp.png`, `beranda-desktop.png` |

Within spec and worth noting as correct: base `#080B09` / `#F2F5F1`, card `#0E1512` / `#FFFFFF`, hairline `#202C25` / `#D8E0D9`, accent `#35D07F`, money `#F5B841`, red `#FF5A5A`; rail 216px; content 934px (≤980); two columns at ≥900; flat surfaces, no gradients or drop shadows anywhere in the six frames.

---

## 3. Top 3 layout / structure problems

### T1 — The page has no bottom boundary (`beranda-hp.png`, `beranda-terang.png`)

**Location:** the last block on the phone home ("KAS BULAN INI") and the bottom nav.
**Evidence:** in `beranda-terang.png` the Kas card's top hairline sits at y=713 and the number row at y≈747–760; the nav's active pill begins at y=789 and no bottom hairline for the card is drawn anywhere below it. In `beranda-hp.png` the same block's top hairline is at y=712 and a column scan through it finds no bottom border before the nav at y=788. The nav itself never draws a top rule (nav bg = page bg), so the content does not stop — it just gets covered.
**Impact:** the last thing on the screen looks clipped rather than scrolled; a treasurer reading the saldo cannot tell whether the number is complete or cut, and the column ends without any terminator.
**Target result:** the Kas block ends with a visible bottom border, ≥16px of clear space above a nav that is separated by a 1px hairline.
**How to verify:** screenshot 390x844 in both themes at scroll-top and at scroll-end; the Kas card's four borders are all visible and the gap to the nav hairline is ≥16px.

### T2 — Tournament content is doubled and mis-weighted (`beranda-hp.png`, `beranda-320.png`, `beranda-terang.png`, `beranda-desktop.png`)

**Location:** the two consecutive sections "TURNAMEN BERIKUTNYA" and "TURNAMEN TERAKHIR".
**Evidence:** the first is a 64px hairline RowItem (icon, title, "Sen, 26 Okt • 19.00 • 6 hari lagi", chevron); the second is a ~100–110px filled card with its own border, a status label, a dropdown ("Hasil ⌄") and a progress bar. Two sections, two components, one object type. In `beranda-320.png` the pair occupies y=277–560, i.e. most of the middle of the screen, while the club-level numbers start at y=570.
**Impact:** the home answers "what is happening in tournaments" before it answers "how is the club doing", which is the opposite of the brief; and a card next to a row makes the card look more important than it is (it is last week's tournament, not the active one).
**Target result:** one tournament section built only from RowItems — the ongoing tournament first, the next one second — with the progress expressed on one line inside the row, so the section is ~130px instead of ~290px and the club numbers move up.
**How to verify:** the section contains no filled/bordered container; the two tournament rows are the same height within 2px; at 320x800 the Kas block's first row is visible above the nav.

### T3 — Login puts the task second (`login-desktop.png`, `login-hp.png`)

**Location:** `login-desktop.png` left column vs the card at x=833; `login-hp.png` brand block above the card.
**Evidence:** desktop: 1440px wide, the form card is 356px at x=833–1189, while the left column carries a two-line display headline plus a numbered feature list running to x≈590. The `01/02/03` list is the largest text mass on the screen after the headline, and it describes the product to someone who has already installed it. Phone: logo + two-line headline + subtitle occupy y=125–300 before the card starts at y=318, and the button lands at y=600–645 of an 844px screen.
**Impact:** the only action on the screen is not the first thing the eye finds; on a phone the form starts a third of the way down. This is the "big title left, form right" default split rather than a login built around one field pair.
**Target result:** on desktop the form is the first element in reading order (or the left column reduces to a logo + one support line so the card becomes the only heavy object); on phone the brand block is one line of lockup + one line of support text, and the card starts within the first 200px.
**How to verify:** at 1440x900 and 390x844, the form card is the highest-contrast, first-fixated object; the `01/02/03` block is absent.

---

## 4. Motion

Motion and interaction are **not verified**: only static PNGs were provided, no running build, no interaction. Nothing in this report claims anything about transitions, the nav active-state change, the "Isi hasil" flow, the "Hasil ⌄" expansion, the refresh affordance in the header, or focus/error behaviour of the login fields.

---

## 5. Deletable text and elements

| String / element | Screenshot |
|---|---|
| `LAPANGAN CIMAHI` (hero, top-right eyebrow) — the same venue is already in the line below: "Sel, 20 Okt 2026 • 20.00 • Lapangan Cimahi" | `beranda-hp.png`, `beranda-320.png`, `beranda-terang.png`, `beranda-desktop.png` |
| `20 menit/laga` (right end of the tournament progress row) — no decision depends on match length here | `beranda-hp.png`, `beranda-320.png`, `beranda-terang.png`, `beranda-desktop.png` |
| `Hasil ⌄` (dropdown inside the tournament card) — a filter inside a summary card, competing with the section's own `Semua` link | `beranda-hp.png`, `beranda-terang.png`, `beranda-desktop.png` |
| `AKSI CEPAT` and its shortcut tiles (`Tim`, `Tanding`, `Turnamen`, …) — repeats the rail's own destinations | `beranda-desktop.png` |
| `MASUK` (green eyebrow above "Masuk ke klub") — the card already says "Masuk ke klub" and the button says "Masuk" | `login-hp.png`, `login-desktop.png` |
| `Password` (placeholder inside the password field) — duplicates the `PASSWORD` label directly above it | `login-hp.png`, `login-desktop.png` |
| `01 Jadwal & hasil` / `Sesi per babak, pemenang dihitung dari skor`, `02 Kas klub` / `Iuran bulanan, siapa yang belum, total terkumpul`, `03 Turnamen internal` / `Empat tim round-robin, klasemen otomatis` | `login-desktop.png` |
| `Anggota, jadwal tanding, iuran, dan turnamen internal.` — on desktop it restates the `01/02/03` list; delete together with it (keep it on phone, where it is the only support line) | `login-desktop.png` |

---

## 6. Keep

- **The score as the single largest object.** `beranda-hp.png` / `beranda-desktop.png`: "1–1" in tabular condensed green, flanked by team names, with the `SEDANG BERLANGSUNG` / venue eyebrow above and the date line below — this is the one element that reads as a stadium scoreboard and not as a dashboard. Its proportion (the score's digit height ≈31px against the greeting's cap height ≈19px) must survive every fix in §3.
- **The flat row rhythm of "TURNAMEN BERIKUTNYA".** `beranda-hp.png`: icon, title, meta, chevron, no fill, one hairline below — the correct list treatment per spec. Do not convert it into a card while making the two tournament blocks consistent; convert the other one down to this.
