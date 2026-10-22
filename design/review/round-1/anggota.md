# Round 1 review — Anggota + admin pages

Reviewer: independent (did not build this UI). Method: `oil-ui` reviewer manual §2 (existing-UI alignment to spec, no scoring).
Evidence: static PNGs in `design/current/`. No interaction, no running preview, no source read.
Frames read: `anggota.png` (390x844@2x, admin), `anggota-terang.png` (390x844@2x, light), `anggota-member.png` (390x844@2x, member), `pengguna.png` (390x844@2x), `pengumuman.png` (390x844@2x), `booking.png` (390x844@2x), `pengaturan.png` (320x800@2x), `lainnya.png` (320x800@2x), `lainnya-320.png` (320x800@2x).

Measured from the pixels, not estimated: header rule y142–143; search field x40–619 (290dp) y148–223 (38dp); filter button x640–739 (50dp) y145–227 (41.5dp); jersey badge 38dp; list row pitch 122px (61dp); icon buttons 33–34dp square, 7dp apart; phone numbers start at x=208 / 223 / 240 / 288 across rows; booking action cluster ends at x=559 against a content edge of x=739; `pengaturan.png` cards 280dp wide on a 20dp page margin; `lainnya.png` AKUN rule at y1415 with its first row cut at y1480.

**Evidence note:** `lainnya.png` and `lainnya-320.png` are the same file (identical MD5, both 640x1600). There is no 390-wide capture of the Lainnya page in this set, so every Lainnya claim below is a 320px claim only.

---

## 1. Quick checklist

### Problems (highest impact first)

- **[problem 1]** `lainnya.png` / AKUN group at the bottom: the section label and its rule render with no content — the group's first row starts at y≈1477 and is cut at y≈1480 by the bottom nav's opaque background (only the top 3px of a 34dp icon box survives, x47–100), while the account card that belongs to that group floats at the top of the page above KELOLA KLUB. -> Acceptance: at 320x800 and 390x844 the AKUN group shows its row(s) whole, the account card lives inside AKUN, and no element is painted beneath the nav (last row bottom ≥16dp above the nav's top edge).
- **[problem 2]** `anggota.png`, `pengguna.png`, `pengumuman.png`, `booking.png` / every icon-only control: 33–34dp square (e.g. trash x672–739 y275–342 in `anggota.png`; key + trash x593–658 and x673–738 in `pengguna.png`), with 7dp between paired buttons; and the `pengaturan.png` theme switch is only 24dp tall (44x24dp). -> Acceptance: every tappable icon control is ≥44dp in both axes (visual box may stay 34dp, hit area must not), and adjacent destructive/non-destructive pairs are ≥12dp apart.
- **[problem 3]** `anggota.png`, `anggota-terang.png` / toolbar row: the header rule sits at y142–143 and the search field's own top border at y148–149 — a 2dp gap that reads as one doubled hairline; the filter button is 41.5dp tall (y145–227) against a 38dp search field (y148–223), so the two controls do not share a top or bottom edge. -> Acceptance: one hairline only, ≥16dp between the header rule and the toolbar, and both controls identical in top y and height.
- **[problem 4]** `anggota.png`, `anggota-member.png` / filter affordance: the funnel is the only filter control and is painted accent green in both roles with no label, count, or on/off state; the fact that the list is filtered to "Aktif" is carried only by the header subtitle word "Aktif" ("Aktif • ketuk untuk edit" / "Aktif • hanya baca"). -> Acceptance: the control itself shows the applied state (and changes visibly between Aktif and Nonaktif), so the header no longer has to state it in prose.
- **[problem 5]** `pengguna.png` / rows 1–2: the role line repeats the display name — "admin (kamu)" over "Admin", "bendahara" over "Bendahara" — so 2 of 4 rows spend their second line saying nothing; the same file lowercases the state ("Anggota • nonaktif") while `anggota.png` capitalises it ("Aktif"). -> Acceptance: no row's role line repeats its name (render the role only when it differs, or move it onto the name line), and one casing for the state word across both screens.

### Improvements

- **[improvement 1]** `booking.png` / per-row action cluster: three equal-weight outline buttons (✓ x333–399, ⊘ x413–479, 🗑 x493–559, each 33.5dp) sit on the price baseline and stop at x=559 — 180px (90dp) short of the content edge at x=739 where every other screen puts its trailing control (`anggota.png` trash at 672–739, `pengguna.png` 673–738, `pengumuman.png` 672–739). -> Target: cluster right-aligned to x=739, one primary action distinguished from the rest, destructive action demoted to overflow; history row keeps a single trailing control on the same anchor.
- **[improvement 2]** `anggota.png` / row subtitle: position and phone share one bulleted line, so the phone numbers start at four different x (208 "Bek", 223 "Kiper", 240 "Striker", 288 "Gelendang") — a 40dp ragged edge down 12 rows. -> Target: phone numbers share one x, or the position token gets a fixed width so the column is real.
- **[improvement 3]** `pengaturan.png` / page order: the page is ordered for whoever built it — SERVER (170dp card of host and credential explanation) and TENTANG (Flutter + shadcn + Neon credits) bracket the admin's own block, which comes third, and "Keluar" is buried inside the identity card under the ADMIN tag. -> Target: AKUN precedes SERVER; TENTANG is the version line only; sign-out is separated from the identity block by a hairline inside the same card.
- **[improvement 4]** `lainnya.png` / 320px rows: wrapped subtitles make the Anggota row ~95dp and the Statistik row ~79dp against 61dp for Kas and Booking, so the menu has three different row heights in one column. -> Target: subtitles that fit one line at 320 (no wrap), one row height within 2dp.
- **[improvement 5]** `pengumuman.png` / header: it is the only page in this set with no subtitle line, and the geometry drifts with it — title top y47 vs y38 in `anggota.png`/`booking.png`, + button y28–95 vs y39–106, header divider y120 vs y142. -> Target: one header block height, title top and + button y identical across the five pages, divider on one y.

**Clean / passes:** `anggota-member.png` contains **no** add, edit, or delete control — the + add-member button at x684–751 y39–106 in `anggota.png` is absent, and the entire per-row trailing column (trash x672–739) is absent; only the search field and the funnel remain, and the row pitch is unchanged at 61dp, so nothing is left half-removed. Red `#FF5A5A` appears **zero** times in every frame in this set — "red = failure/overdue only" holds, including the delete controls, which stay neutral grey. Lists are hairline rows with no stacked cards in `anggota.png`, `pengguna.png`, `pengumuman.png`, `booking.png`; in `lainnya.png` the only non-row object is the account card, which is problem 1. No truncation or ellipsis anywhere at 320 (`pengaturan.png`, `lainnya.png`); text wraps instead.

**Not verifiable from this set (not counted as defects):** motion and interaction (see §4); the 390-wide state of Lainnya (`lainnya.png` and `lainnya-320.png` are byte-identical); member role for Pengguna, Pengumuman, Booking and Pengaturan (only Anggota has a member frame); desktop ≥900px for all five pages (no such frame); scroll-end state of any list; search no-result state; whether the funnel opens a sheet or toggles in place; delete confirmation.

---

## 2. Spec deviations

Colors sampled directly from the PNGs; values that matched the spec exactly are not listed.

| # | Deviation | Where |
|---|---|---|
| D1 | Row separator hairline is `#18221D` (dark) / `#E0E6E0` (light), while container borders use `#202C25` / `#D8E0D9`. Two hairline values in one system; spec defines one. | `anggota.png`, `pengguna.png`, `pengumuman.png`, `booking.png`, `lainnya.png`, `anggota-terang.png` |
| D2 | Light accent is `#0A7D43` (filter icon, jersey numerals), not the spec's `#0E7C48`. Dark accent `#35D07F` is exact. | `anggota-terang.png` |
| D3 | Two container fills for the same "panel" role: `pengaturan.png` blocks are `#0E1512` on `#202C25`; the `booking.png` stat block (x40–739, y176–373) is unfilled `#080B09` behind the same `#202C25` border. Spec card is `#0E1512`. | `pengaturan.png`, `booking.png` |
| D4 | Two control heights in one toolbar row: search 38dp, filter 41.5dp. | `anggota.png`, `anggota-terang.png` |
| D5 | 2dp between the header rule and the toolbar's top border (y142–143 vs y148–149) — a doubled hairline, not a spacing step. | `anggota.png`, `anggota-terang.png` |
| D6 | Icon-only targets 33–34dp, below the 44dp minimum; paired buttons 7dp apart. Theme switch 24dp tall. | `anggota.png`, `pengguna.png`, `pengumuman.png`, `booking.png`, `pengaturan.png` |
| D7 | Jersey badge border is an accent tint — `#1F6D44` dark / `#7EB99A` light — that exists in no spec token. It is applied consistently across both themes, so this is an undocumented token rather than a mistake: add it to the spec or change it, but do not fix one theme only. | `anggota.png`, `anggota-terang.png` |
| D8 | Header geometry differs from every sibling: title top y47 (vs 38), + button y28–95 (vs 39–106), divider y120 (vs 142). | `pengumuman.png` |
| D9 | Trailing controls do not share an anchor: x=559 in booking rows against x=739 everywhere else. | `booking.png` vs `anggota.png`, `pengguna.png`, `pengumuman.png` |
| D10 | State-word casing is split: `Aktif` in the member list header (`anggota.png`, `anggota-member.png`), `nonaktif` inside the user row. | `anggota.png`, `anggota-member.png`, `pengguna.png` |

Within spec and worth noting as correct: base `#080B09` / `#F2F5F1`; card `#0E1512` in `pengaturan.png`; hairline `#202C25` on all container borders; accent `#35D07F`; money `#F5B841` on the booking total; flat surfaces with no gradients and no drop shadows in any frame; section labels as small uppercase text with a rule running to the right edge (`AKAN DATANG`, `RIWAYAT`, `KELOLA KLUB`, `KOMPETISI`, `INFORMASI`, `AKUN`, `TAMPILAN`, `SERVER`, `TENTANG`); consistent 20dp page margin at both widths (content x40–739 of 780, x40–599 of 640); lists built from hairline rows, never cards.

---

## 3. Top 3 layout / structure problems

### T1 — The AKUN group is empty and its content is under the nav (`lainnya.png`)

**Location:** the AKUN section at the bottom of the more-menu, and the account card at the top of the same page.
**Evidence:** the AKUN label and its rule are drawn at y1415–1416, then nothing — the next visible mark is a 47px-wide rounded arc at y1477–1479 (x47–100) which is the top edge of the group's first 34dp icon box, and it stops dead at y1480 where the nav's opaque `#080B09` background begins (nav pill y1489–1552, labels y1566–1586). Meanwhile the identity card — avatar "A", "admin", "Bisa mengubah data", `ADMIN`, chevron — sits at y≈170–301, above KELOLA KLUB, i.e. outside the group named after it.
**Impact:** the group's own destinations are unreachable at 320x800 — the section header that should hold them points at a 3px sliver — and the account card is orphaned at the top where it reads as a page title rather than a row.
**Target result:** AKUN is the last group and contains the account row(s), including the one currently cut; the list ends above the nav with visible clearance; the top of the page starts with the page title, then KELOLA KLUB.
**How to verify:** capture 320x800 and 390x844; the AKUN group's first row is fully visible with its hairline separator, the gap between the last row's bottom edge and the nav's top edge is ≥16dp, and no pixel of any row is painted between the nav's top edge and the nav's labels.

### T2 — Pengaturan is ordered for the developer, not the club admin (`pengaturan.png`)

**Location:** section order TAMPILAN → SERVER → AKUN → TENTANG, and the inside of the AKUN card.
**Evidence:** SERVER is the largest block on the page (card x40–599, y440–779, i.e. 170dp) and contains "Host web ini (same-origin)" plus a two-line explanation of where credentials are stored; TENTANG (card y1324–1583, the tallest block after SERVER) explains the tech stack ("Dibuat dengan Flutter + shadcn UI + Neon Postgres", "Data tersimpan langsung di database Neon kamu"). The admin's own identity and the only destructive action — "Keluar", a 263x40dp full-width button at y1040–1120 — are inside a card that starts at y924, below both.
**Impact:** the page reads as a deployment status screen. The one thing a club admin opens it for (who am I, switch theme, sign out) is sandwiched between infrastructure copy, and sign-out sits directly under the `ADMIN` tag so a mis-tap ends the session while the eye is reading a role badge.
**Target result:** AKUN first (identity + Keluar, separated by a hairline inside the card), TAMPILAN second, SERVER third and reduced to the connection test, TENTANG reduced to the version line.
**How to verify:** at 320x800 the AKUN block's top edge is above y=300 and the first viewport contains the theme switch and the account block; the SERVER card contains no explanatory sentence longer than one line; the TENTANG card is one line tall.

### T3 — The toolbar is glued to the header rule and the filter says nothing (`anggota.png`, `anggota-terang.png`, `anggota-member.png`)

**Location:** the search + funnel row directly under the page header.
**Evidence:** the header rule spans the full width at y142–143; the search field's border starts at y148–149, 2dp below it, and the funnel's box runs y145–227 — so three horizontal lines stack inside 85px and the two controls' edges miss each other by 3.5dp. The funnel is filled accent green in the admin frame, in the light frame, and in the member frame; the only statement of the current filter is the word "Aktif" in the header subtitle, which is also where the permission hint lives ("Aktif • ketuk untuk edit", "Aktif • hanya baca").
**Impact:** the first control row on the primary list screen looks like a rendering seam rather than a toolbar, and the filter has no perceivable state — a user cannot tell whether they are seeing all members or only active ones without reading a sentence that is doing two jobs at once.
**Target result:** one rule, then ≥16dp, then a toolbar whose two controls share one height and one top edge; the funnel carries its own state (visibly different between Aktif and Nonaktif) and the subtitle is left to say only what the role can do.
**How to verify:** at 390x844 in both themes there is exactly one hairline between the title block and the search field; the search field and filter button have the same y-top and height within 1px; the funnel's rendering differs between the two filter states.

---

## 4. Motion

Motion and interaction are **not verified** — only static PNGs were supplied, with no running build and no interaction. Nothing here claims anything about the funnel opening, row tap-to-edit, the theme switch transition, the "Tes koneksi" result, sign-out, delete confirmation, list scroll or nav active-state changes.

---

## 5. Deletable text and elements

| String / element | Screenshot |
|---|---|
| `ketuk untuk edit` (header subtitle) — an instruction compensating for an affordance that is not visible; once the row shows an edit affordance the sentence goes | `anggota.png`, `anggota-terang.png` |
| the per-row 🗑 button repeated on all 12 visible rows — a destructive control repeated on every row; delete belongs inside the row's edit view, which the header already promises | `anggota.png`, `anggota-terang.png` |
| `Nyaman dipakai malam hari` — filler under "Mode gelap" | `pengaturan.png` |
| `Host web ini (same-origin)` — jargon; adds nothing beside "Neon Postgres" | `pengaturan.png` |
| `Kredensial database hanya ada di server. Aplikasi tidak menyimpannya.` — an implementation note written to the reader | `pengaturan.png` |
| `Dibuat dengan Flutter + shadcn UI + Neon Postgres.` and `Data tersimpan langsung di database Neon kamu.` — stack credits; keep only `Minisoccer Club v1.6.0` | `pengaturan.png` |
| `Bisa mengubah data` — repeats the `ADMIN` tag on the same card | `pengaturan.png`, `lainnya.png` |
| `Sewa lapangan — ` prefix on every booking row — the page is already titled "Booking lapangan"; the rows reduce to `latihan rutin` and `uji coba` | `booking.png` |
| `uji coba` — a test booking sitting in a production-looking list | `booking.png` |

---

## 6. Keep

- **The jersey-number badge column.** `anggota.png` / `anggota-terang.png`: a 38dp rounded square, accent numeral, accent-tint border, one per row, forming a single vertical column down the list. This is the one element that makes the roster read as a scoreboard rather than a contacts app; do not flatten it into initials or avatars while fixing the row spacing.
- **The flat hairline rows and the AKAN DATANG / RIWAYAT split.** `booking.png`: one hairline per row, no card fill, no per-row container, and the upcoming/history division carried by a section label and a rule. Fix the action cluster inside this language; do not promote the rows into cards.
