# Design inputs — recovered artifacts

Two HTML artifacts recovered on 2026-08-17 from `/mnt/R/align-platform`, a stale
snapshot of `demographai-platform` whose last commit was 2026-04-29. Both were
authored on **2026-05-04**, five days after that commit, and were never tracked
in any repository — they survived only as untracked working-tree files in a repo
that was a candidate for deletion.

They are committed here so the reasoning behind the funnel demo is recoverable
without anyone having to reconstruct it.

| File | Status |
|---|---|
| `move-funnel-storyboard-2026-05-04.html` | **Superseded in function** by `demo/index.html` + `demo/funnel_bundle.json`. Kept for the design rationale those don't record. |
| `move-proportion-explorer-2026-05-04.html` | **Not superseded.** Nothing in this repo replaces it. |

## Why they live here

The proportion explorer is unambiguously in scope: it runs on ANES weighted
estimates and implements the "Agree on basic facts" cell-refinement mechanic
that the funnel five later generalised. It is the earliest working expression of
that interaction.

The storyboard is a judgement call worth flagging. It describes *platform*
acquisition UX — promo video, landing, OTP verification, address validation,
profile — rather than marketing modelling. It lives here because the funnel demo
it informed lives here, and splitting the two would separate the design intent
from the thing built from it. If the platform ever needs it back, this is where
it is.

## Read the provenance headers

Each file opens with an HTML comment recording origin, date, what it is, and
what not to trust in it. Two things in particular:

- The storyboard's typography uses **Playfair Display**, which the platform
  design system later replaced with **Fraunces**. Its styling is not current.
- The explorer's numbers **predate the fits in this repo**. They illustrate the
  interaction, not current values. `data/estimates/` is authoritative.
