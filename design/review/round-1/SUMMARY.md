# UI review round 1 — consolidated

Method: five independent reviewers, one per screen group, each following
`oil-ui` `references/reviewer-manual.md` §2 (existing-interface alignment, no
scores). Evidence: `design/current/*.png` plus a live preview build
(`node design/mock/server.mjs` → `http://localhost:8099`).

Reports: [`beranda.md`](beranda.md) · [`tanding.md`](tanding.md) ·
[`iuran.md`](iuran.md) · [`turnamen.md`](turnamen.md) ·
[`anggota.md`](anggota.md).

The coordinator re-checked every P0 claim against the running preview and the
source. Where a reviewer's measurement did not reproduce, it is listed in
§4 instead of being carried into the fix list.

---

## 1. P0 — breaks the locked navigation model

### P0.1 Pushed pages leave the shell: no bottom nav on phone, no rail on desktop

One root cause behind five separate "nav is missing" findings.

- `lib/ui/more.dart:96` and `:115` push with `Navigator.push(context, MaterialPageRoute(...))`
  on the root navigator, and `PageScaffold` (`lib/ui/widgets.dart:795`) builds its own `Scaffold`.
  The result is a full-screen route above `HomeShell`.
- Measured on the live build, 390x844: bright pixels in the bottom 100px are
  **3127** on the `Lainnya` tab and **0** after tapping `Kas klub`.
- Measured at 1440x900: the pushed `Kas klub` page has **no rail** and the
  content column re-centers in the full 1440 width instead of the 216–1440 area.
- Consequence for the evidence set: `kas.png`, `kas-terang.png`, `turnamen.png`,
  `statistik.png`, `booking.png`, `kas-desktop.png`, `turnamen-desktop.png`,
  `detail-turnamen-desktop.png` were captured through `?page=`, which renders
  the same shell-less route. Those frames are not stale — they show a real defect.

Target: pushed pages render inside the shell (bottom nav on phone, rail at
≥900px), with the header back arrow kept as the in-page affordance.
Acceptance: from `Lainnya`, open Kas, Turnamen, Statistik, Booking, Pengumuman,
Pengguna, Pengaturan, a team detail and a match detail — every one keeps the nav
or rail, and the content column keeps the same left edge as the tab pages.

### P0.2 Member role is clean, but the write affordances are 34dp

- `anggota-member.png` has no add/edit/delete control at all; search and the
  filter remain. The role rule holds.
- `iconAction` (`lib/ui/widgets.dart:862`) renders a **34x34** box, and paired
  buttons sit 7dp apart (`anggota.png`, `pengguna.png`, `booking.png`).
- Target: hit area ≥44dp in both axes, ≥12dp between a destructive and a
  non-destructive neighbour. Visual box may stay 34dp.

---

## 2. P1 — visible defects, fix before the next screenshot round

| # | Where | Defect | Acceptance |
|---|---|---|---|
| P1.1 | `iuran.png` `payments.dart:224` | Members who have **not** paid carry a check glyph (`Icons.check`, red) while `RIWAYAT PEMBAYARAN` uses the same glyph for **paid** | Unpaid chips carry no check; state comes from the section label and the red outline |
| P1.2 | `iuran.png` `payments.dart:71` | No `Semua` chip, while `Kas` has one (`finance.dart:75` passes `all: true`) | `Semua` is the first chip on both screens |
| P1.3 | `detail-laga.png` `matches.dart:320` | `Pill('$lost kalah', color: bad)` is red even when `lost == 0`; the only red on the page marks a zero | Red only when the count is > 0 |
| P1.4 | `beranda-hp.png` `dashboard.dart:277,286` | The same object type renders as a `RowItem` (`_TournamentRow`, 64px) and as a filled `Panel` (`_LastTournamentCard`, ~105px), both visible at once | One section, one row component; progress stays on one line inside the row |
| P1.5 | `kas.png` `RowItem` vs `Panel` | Two hairline values by construction: `RowItem` uses `border.withValues(alpha: 0.7)` (≈`#19211D` on dark), containers use `#202C25` | One hairline token for row dividers and container borders |
| P1.6 | `anggota.png` toolbar | Header rule and search-field border are 2dp apart, and search (38dp) and filter (41.5dp) do not share a top or bottom edge | ≥16dp below the rule; both controls identical in top and height |
| P1.7 | `anggota.png` `members.dart` | The funnel is the only filter affordance, has no applied-state, and the state is stated in prose in the subtitle | The control itself shows Aktif/Nonaktif |
| P1.8 | `turnamen.png`, `detail-turnamen.png` | The list carries no readable ordering cue (state is a small word at the right edge) and the detail never names the state; its only header action is delete | Group by BERJALAN / AKAN DATANG / SELESAI; the detail states the state and exposes the state-relevant action |
| P1.9 | `statistik.png` | "Semua 11" has no unit and cannot be reconciled with `GOL 12` and the 9 goals on screen; two rows with 3 goals get different bar lengths/colours | Label states the unit, the total reconciles, equal values render equally |
| P1.10 | `login-desktop.png` | The form is the secondary column behind a two-line headline and a `01/02/03` feature list; three field heights (37/57/42) in one form | Form is the first object; one height (44) for both fields and the button |
| P1.11 | `lainnya.png` (320) | The `AKUN` label renders with no content and its first row is cut by the nav; the account card floats at the top instead | AKUN owns the account card; last row ≥16dp above the nav |
| P1.12 | `kas-desktop.png` | 8px-cap row titles at 1440 while `beranda-desktop.png` rows are 13px; description ends at x=443 and the amount starts at x=1070 | Desktop row type scale; the middle of the row carries the date and the member name in their own columns |
| P1.13 | `detail-laga.png`, `tim-detail.png` | Delete is the most repeated and most prominent element (5 and 8 bordered `×` boxes) | Delete moves into the row's edit view; data leads the row |
| P1.14 | `detail-turnamen.png` | `PEMAIN PER TIM` is three bordered panels containing bordered chips with 20+ `×` glyphs | Hairline rows, one border level |

---

## 3. P2 — consistency debt (decide once, apply everywhere)

1. **Light-theme tokens drift from the design note.** `theme.dart:38-39` uses
   `pitchLight = #0A7D43` and `amberLight = #7A5C00`; `design/README.md`
   specifies `#0E7C48` and `#8A5A00`. Both spec values pass AA on `#F2F5F1`
   (4.78:1 and 5.39:1). Pick one pair and update the other.
2. **Money colour grammar.** Iuran amounts are amber, Kas income is green,
   Kas expense is neutral, and `MASUK`/`KELUAR` in the home strip are neutral
   while `IURAN`/`SALDO` are amber. One rule, applied to every money class.
3. **`StatStrip` is outline-only while `Panel` fills with `card`** — same role,
   two treatments. Either fill the strip or document it as a rule.
4. **Row titles inside one capture.** Kas row titles are not smaller than Iuran
   row titles (see §4); the real issue is that the *amount* outweighs the title
   in Kas because the title is one word. Consider making the transaction type
   the row's anchor instead of the date line.
5. **Icon and control scale**: 33–34dp icon buttons, 24dp theme switch, three
   secondary-action styles on `detail-laga.png`, and no `Pill` on any of the
   five screen groups. One secondary-action style, one `Pill` usage.
6. **Header geometry**: `pengumuman.png` is the only page with no subtitle, so
   its title, `+` button and divider sit at different y than its siblings.
7. **Uppercase section labels**: `AKUN` has no content, `DAFTAR TURNAMEN`
   repeats the page title, `Tim klub • klasemen per grup` explains a feature.

---

## 4. Claims that did not reproduce

- **"Kas row title is 8px cap vs 11px in Iuran"** (`iuran.md` problem 2).
  Re-measured: `kas.png` title band is 10px tall (1x capture) and `iuran.png`
  is 17px (2x capture → 8.5 logical). The two are the same size. The reviewers
  compared absolute pixels across captures at different device scale factors
  (the live build renders 390 logical px into a 474px image, factor 1.215), so
  every cross-file cap-height comparison in the five reports is unreliable.
  Within-capture comparisons (row vs row, control vs control) remain valid.
- **"Bottom nav has no top hairline"** (`beranda.md` D6). `shell.dart:136-139`
  draws `Border(top: ...)` with `colorScheme.border`. It exists; at 1px on
  `#080B09` it renders as a single row of `(28,30,29)` and is effectively
  invisible. The fix is contrast, not structure.
- **"`kas.png` / `turnamen.png` / `statistik.png` are stale captures."** They
  are current; they were taken through `?page=`, which reproduces P0.1.

---

## 5. Evidence limits

- Static frames only. Motion, tap feedback, delete confirmation, the funnel's
  behaviour, the `Hasil ⌄` expansion and scroll-end states are **not verified**.
- `tanding.png` (18:41) and `tanding-terang.png` (11:31) come from different
  builds: 4 sections vs 2, 3 stat tiles vs 5, result tags only in the light
  frame. Both were reviewed as-is; the light frame predates the dark one.
- No member-role frame exists for Pengguna, Pengumuman, Booking, Pengaturan,
  or any match/team detail. Only `anggota-member.png` proves the role rule.
- No 390-wide `Lainnya` frame (`lainnya.png` and `lainnya-320.png` are the same
  640x1600 file), and no desktop frame for Anggota, Pengguna, Pengumuman,
  Booking, Pengaturan.

---

## 6. Suggested order

1. P0.1 (shell on pushed routes) — it invalidates every desktop and phone
   screenshot of those pages, so re-capture after it lands.
2. P0.2 + P1.6 + P1.7 (toolbar and touch targets) — one component change.
3. P1.1–P1.5 (data-state and component duplication) — small, verifiable.
4. P1.8–P1.14 (per-page structure) — one page at a time, re-capture each.
5. P2 — token and grammar decisions, recorded in `design/README.md`.
