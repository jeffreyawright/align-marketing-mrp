#!/usr/bin/env python3
"""
Fit the marketing-funnel MRP models on GPU and poststratify onto the ACS frame.

Ported from demographai-platform/r-scoring/run_marketing_mrp_jax.py, with the
recoding removed: this reads the cleaned per-question CSVs produced by
R/process_anes_2024.R instead of re-deriving demographics from the raw ANES
file. The platform script carried its own copy of every recode, which is how it
ended up with a separate instance of the `hispanic < 7` defect.

Usage:
    python python/fit.py basic_facts
    python python/fit.py election_efficacy --include-cd
    python python/fit.py congress_approval --draws 500 --tune 500   # smoke test

Model spec matches the prior platform run by default (no `cd` term) so the
posteriors stay comparable. See CLAUDE.md, "Is (1 | cd) worth including?".
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path

import numpy as np
import pandas as pd

REPO = Path(__file__).resolve().parent.parent

# Canonical levels -- must stay identical to .CANONICAL_* in R/utils.R. Survey
# recode and ACS frame have to agree exactly or poststratification misaligns
# silently, and this contract crosses a language boundary.
CANONICAL = {
    "age_group": ["18-24", "25-29", "30-34", "35-39", "40-44", "45-49",
                  "50-54", "55-59", "60-64", "65-69", "70-74", "75-79", "80 plus"],
    "sex":       ["Male", "Female"],
    "race":      ["White", "Black", "Hispanic", "Asian", "Other"],
    "educ":      ["HS or less", "Some College", "BA/BS", "Postgrad"],
    "region":    ["Northeast", "Midwest", "South", "West", "DC"],
}

BASE_FACTORS = ["age_group", "sex", "race", "educ", "region", "state"]

VALID_QUESTIONS = ["basic_facts", "election_efficacy", "congress_approval",
                   "social_trust", "country_track"]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("question", choices=VALID_QUESTIONS)
    p.add_argument("--include-cd", action="store_true",
                   help="add (1|cd). Off by default: sigma_state is 0.05-0.17, so the "
                        "cd term adds 435 weakly-identified parameters for little gain.")
    p.add_argument("--exclude", nargs="*", default=[], choices=BASE_FACTORS,
                   help="drop grouping factors from the model AND the poststratification "
                        "(sensitivity testing). Dropping a factor marginalises it out of "
                        "the frame, which is not the same as it being absent from the "
                        "output -- every factor is already marginalised out of the "
                        "per-district estimates.")
    p.add_argument("--frame", default=str(REPO / "data" / "frames" / "synthetic_frames_combined.rds"))
    p.add_argument("--frame-year", type=int, default=2024,
                   help="the frame stacks multiple ACS vintages; poststratifying over "
                        "all of them at once double-counts population.")
    p.add_argument("--draws", type=int, default=1500)
    p.add_argument("--tune", type=int, default=1500)
    p.add_argument("--chains", type=int, default=4)
    p.add_argument("--target-accept", type=float, default=0.99)
    p.add_argument("--seed", type=int, default=1203)
    p.add_argument("--chunk", type=int, default=10_000, help="frame cells per GPU batch")
    p.add_argument("--no-poststrat", action="store_true", help="fit only, skip step 3")
    p.add_argument("--no-lookup", action="store_true",
                   help="skip the progressive-disclosure lookup table")
    return p.parse_args()


def load_survey(question: str) -> pd.DataFrame:
    path = REPO / "data" / "cleaned" / f"{question}.csv"
    if not path.exists():
        sys.exit(f"Cleaned data not found: {path}\nRun: Rscript R/process_anes_2024.R")

    df = pd.read_csv(path)
    before = len(df)
    df = df[df["target_binary"].notna()].copy()
    df["target_binary"] = df["target_binary"].astype(int)
    if before != len(df):
        print(f"  dropped {before - len(df)} rows with no binary coding (excluded midpoint)")

    for col, levels in CANONICAL.items():
        unknown = set(df[col].dropna().unique()) - set(levels)
        if unknown:
            sys.exit(f"Non-canonical {col} levels in survey data: {sorted(unknown)}")
        df[col] = pd.Categorical(df[col], categories=levels)
    df["state"] = pd.Categorical(df["state"])
    df["cd"] = pd.Categorical(df["cd"])

    print(f"  {len(df)} respondents, {df['cd'].nunique()} districts, "
          f"{df['state'].nunique()} states, {100 * df['target_binary'].mean():.1f}% positive")
    return df


def load_frame(path: str, year: int, include_cd: bool) -> pd.DataFrame:
    import pyreadr

    if not os.path.exists(path):
        sys.exit(f"Poststratification frame not found: {path}\n"
                 "Port it from demographai-platform/data/census_tables/ first.")

    frame = pyreadr.read_r(path)[None]
    required = {"state", "cd", "region", "age_group", "sex", "race", "educ", "pop"}
    missing = required - set(frame.columns)
    if missing:
        sys.exit(f"Frame is missing required columns: {sorted(missing)}")

    if "year" in frame.columns:
        vintages = sorted(frame["year"].dropna().unique())
        if len(vintages) > 1:
            if float(year) not in vintages:
                sys.exit(f"Frame has vintages {vintages}, none matching --frame-year {year}")
            print(f"  frame stacks vintages {vintages}; selecting {year} "
                  f"(pooling them would double-count population)")
            frame = frame[frame["year"] == float(year)].copy()

    for col, levels in CANONICAL.items():
        unknown = set(frame[col].dropna().astype(str).unique()) - set(levels)
        if unknown:
            sys.exit(f"Non-canonical {col} levels in frame: {sorted(unknown)}")

    print(f"  {len(frame):,} cells, population {frame['pop'].sum():,.0f}, "
          f"{frame['cd'].nunique()} districts")
    return frame


def fit_model(df: pd.DataFrame, args: argparse.Namespace):
    import bambi as bmb

    factors = [f for f in BASE_FACTORS if f not in args.exclude]
    if args.include_cd:
        factors.append("cd")
    terms = ["1"] + [f"(1|{f})" for f in factors]
    if args.exclude:
        print(f"  EXCLUDED: {', '.join(args.exclude)} (sensitivity run, not the production spec)")
    formula = "target_binary ~ " + " + ".join(terms)
    print(f"  formula: {formula}")

    model = bmb.Model(
        formula, df, family="bernoulli", link="logit",
        priors={"Intercept": bmb.Prior("Normal", mu=0, sigma=1.5),
                "common": bmb.Prior("Exponential", lam=1.0)},
    )
    t0 = time.time()
    idata = model.fit(
        inference_method="numpyro",
        draws=args.draws, tune=args.tune, chains=args.chains,
        nuts_sampler_kwargs={"chain_method": "vectorized"},
        target_accept=args.target_accept,
        random_seed=args.seed,
    )
    print(f"  fit completed in {time.time() - t0:.1f}s")
    return model, idata


def group_effects(idata, factor: str, frame_levels: list[str], rng) -> np.ndarray:
    """(draws, n_frame_levels) matrix of group effects, aligned to frame levels.

    Levels the model never saw (e.g. a district with no respondents) get a draw
    from the group's own prior predictive, Normal(0, sigma) -- the correct
    treatment for a new group, rather than silently assuming zero.
    """
    post = idata.posterior
    var = post[f"1|{factor}"]
    dim = [d for d in var.dims if d not in ("chain", "draw")][0]
    fitted_levels = [str(x) for x in post.coords[dim].values]
    vals = var.stack(sample=("chain", "draw")).transpose("sample", dim).values  # (D, L)

    sigma = post[f"1|{factor}_sigma"].stack(sample=("chain", "draw")).values     # (D,)
    lookup = {lvl: i for i, lvl in enumerate(fitted_levels)}

    out = np.empty((vals.shape[0], len(frame_levels)), dtype=np.float32)
    unseen = []
    for j, lvl in enumerate(frame_levels):
        if lvl in lookup:
            out[:, j] = vals[:, lookup[lvl]]
        else:
            out[:, j] = sigma * rng.standard_normal(vals.shape[0])
            unseen.append(lvl)
    if unseen:
        print(f"    {factor}: {len(unseen)} level(s) absent from survey, drawn from "
              f"Normal(0, sigma_{factor}): {unseen[:5]}{'...' if len(unseen) > 5 else ''}")
    return out


def poststratify(idata, frame: pd.DataFrame, factors: list[str],
                 group_col: str, chunk: int, seed: int) -> pd.DataFrame:
    """Per-draw population-weighted aggregation of cell probabilities.

    The platform script collapsed draws to a posterior mean *before* writing
    cells, which makes district-level credible intervals impossible to recover.
    Aggregating per draw and summarising afterwards is what MRP actually
    requires, and it is the step the GPU is genuinely useful for: this is
    ~n_cells x n_draws probability evaluations per question.
    """
    import jax
    import jax.numpy as jnp

    rng = np.random.default_rng(seed)

    alphas, idxs = [], []
    for f in factors:
        levels = sorted(frame[f].astype(str).unique())
        alphas.append(jnp.asarray(group_effects(idata, f, levels, rng)))
        idxs.append(np.searchsorted(np.array(levels), frame[f].astype(str).values))

    intercept = jnp.asarray(
        idata.posterior["Intercept"].stack(sample=("chain", "draw")).values.astype(np.float32)
    )
    n_draws = intercept.shape[0]

    groups = sorted(frame[group_col].astype(str).unique())
    gidx = np.searchsorted(np.array(groups), frame[group_col].astype(str).values)
    pop = frame["pop"].values.astype(np.float32)
    denom = np.bincount(gidx, weights=pop, minlength=len(groups)).astype(np.float32)

    @jax.jit
    def cell_block(alpha_cols, w, g):
        # alpha_cols: tuple of (D, chunk) slices already gathered
        logit = intercept[:, None] + sum(alpha_cols)
        p = jax.nn.sigmoid(logit) * w[None, :]            # (D, chunk)
        return jax.ops.segment_sum(p.T, g, num_segments=len(groups)).T  # (D, G)

    numer = jnp.zeros((n_draws, len(groups)), dtype=jnp.float32)
    t0 = time.time()
    for start in range(0, len(frame), chunk):
        sl = slice(start, min(start + chunk, len(frame)))
        cols = tuple(a[:, jnp.asarray(ix[sl])] for a, ix in zip(alphas, idxs))
        numer = numer + cell_block(cols, jnp.asarray(pop[sl]), jnp.asarray(gidx[sl]))
    numer.block_until_ready()
    est = np.asarray(numer) / denom[None, :]              # (D, G)
    print(f"    {len(frame):,} cells x {n_draws:,} draws aggregated in {time.time() - t0:.1f}s")

    return pd.DataFrame({
        group_col: groups,
        "estimate": est.mean(axis=0),
        "sd": est.std(axis=0),
        "q025": np.quantile(est, 0.025, axis=0),
        "q975": np.quantile(est, 0.975, axis=0),
        "pop": denom,
    }).sort_values(group_col)


LOOKUP_DIMS = ["state", "age_group", "sex", "race", "educ"]


def build_lookup(idata, frame: pd.DataFrame, survey: pd.DataFrame, factors: list[str],
                 chunk: int, seed: int) -> pd.DataFrame:
    """One estimate per combination of demographics a user might have supplied.

    The funnel discloses attributes progressively -- the user answers the poll,
    then gives state, then age, and so on -- and each step should return a
    tighter comparison. So every *subset* of the disclosure dimensions is
    precomputed, with ALL standing for "not yet supplied", which covers every
    path through the funnel in any order. Five dimensions give up to
    52 x 14 x 3 x 6 x 5 = 65,520 slices; 58,701 are populated, the rest being
    combinations with no population in the frame. Every slice of two or fewer
    dimensions exists, so the realistic funnel path never misses -- but consumers
    still need a fallback. The all-ALL row is the national figure.

    n_survey is the number of ANES respondents actually falling in the slice.
    It is reported because it is the honest measure of how thin the direct
    evidence is -- and because a cell with 3 respondents and a stable estimate
    is the clearest possible demonstration of what poststratification buys.
    """
    import itertools

    dims = [d for d in LOOKUP_DIMS if d in factors]
    frame = frame.copy()
    for d in dims:
        frame[d] = frame[d].astype(str)

    out = []
    t0 = time.time()
    for r in range(len(dims) + 1):
        for subset in itertools.combinations(dims, r):
            if subset:
                key = frame[list(subset)].agg("\x1f".join, axis=1)
            else:
                key = pd.Series(["ALL"] * len(frame), index=frame.index)
            frame["_key"] = key
            res = poststratify(idata, frame, factors, "_key", chunk, seed)

            parts = (res["_key"].str.split("\x1f", expand=True)
                     if subset else pd.DataFrame(index=res.index))
            for i, d in enumerate(subset):
                res[d] = parts[i]
            for d in dims:
                if d not in subset:
                    res[d] = "ALL"

            if subset:
                counts = (survey.groupby(list(subset), observed=True).size()
                          .rename("n_survey").reset_index())
                for d in subset:
                    counts[d] = counts[d].astype(str)
                res = res.merge(counts, on=list(subset), how="left")
                res["n_survey"] = res["n_survey"].fillna(0).astype(int)
            else:
                res["n_survey"] = len(survey)

            out.append(res.drop(columns="_key"))

    lookup = pd.concat(out, ignore_index=True)
    lookup["ci_width"] = lookup["q975"] - lookup["q025"]
    # Plain-language reliability, driven by absolute interval width. Absolute is
    # the right unit because the deliverable is marketing copy, not inference:
    # what matters is whether the sentence stays true across the interval.
    #   < 0.15  -> +/- 7.5 points. "About N in 10" holds at any base rate, so the
    #              figure can be stated as a number.
    #   < 0.25  -> +/- 12.5 points. The rounded fraction starts to move; hedge it.
    #   else    -> do not personalise.
    # These were originally 0.10/0.20, which sat BELOW the median width of every
    # question (11.5-17.2 points) and so left `high` nearly empty everywhere --
    # social_trust got 2.1%. The tiers are placed where the data is, not tuned
    # until a particular question passed.
    RELIABILITY_BREAKS = (0.15, 0.25)
    lookup["reliability"] = np.where(lookup["ci_width"] < RELIABILITY_BREAKS[0], "high",
                            np.where(lookup["ci_width"] < RELIABILITY_BREAKS[1], "medium", "low"))
    cols = dims + ["estimate", "sd", "q025", "q975", "ci_width",
                   "reliability", "pop", "n_survey"]
    lookup = lookup[cols].sort_values(dims).reset_index(drop=True)
    print(f"  {len(lookup):,} slices built in {time.time() - t0:.1f}s "
          f"({(lookup.reliability == 'low').mean() * 100:.0f}% flagged low reliability)")
    return lookup


def main() -> None:
    args = parse_args()
    suffix = ("_no_" + "_".join(args.exclude)) if args.exclude else ""
    print(f"\n=== MRP: {args.question}{suffix} ===")

    print("\n[1/4] Loading cleaned survey data...")
    df = load_survey(args.question)

    print("\n[2/4] Fitting model on GPU...")
    import jax
    print(f"  jax devices: {jax.devices()}")
    model, idata = fit_model(df, args)

    import arviz as az
    summary = az.summary(idata)
    out_models = REPO / "models" / "marketing"
    out_models.mkdir(parents=True, exist_ok=True)
    summary_path = out_models / f"{args.question}{suffix}_mrp_summary_jax.csv"
    summary.to_csv(summary_path)

    max_rhat = summary["r_hat"].max()
    min_ess = summary["ess_bulk"].min()
    n_div = int(idata.sample_stats["diverging"].sum()) if "diverging" in idata.sample_stats else -1
    n_post = args.draws * args.chains
    print(f"\n[3/4] Diagnostics -> {summary_path}")
    print(f"  max r_hat {max_rhat:.4f} (need < 1.05)   "
          f"min ess_bulk {min_ess:.0f} (need > 400)   "
          f"divergences {n_div}/{n_post} ({100 * n_div / n_post:.2f}%, need < 1%)")
    if max_rhat >= 1.05 or min_ess <= 400 or (0 <= n_div and n_div > 0.01 * n_post):
        print("  WARNING: convergence criteria in CLAUDE.md not met.")

    if args.no_poststrat:
        print("\n[4/4] Skipped (--no-poststrat).")
        return

    print("\n[4/4] Poststratifying...")
    frame = load_frame(args.frame, args.frame_year, args.include_cd)
    factors = [f for f in BASE_FACTORS if f not in args.exclude]
    if args.include_cd:
        factors.append("cd")

    out_dir = REPO / "data" / "estimates"
    out_dir.mkdir(parents=True, exist_ok=True)
    for group_col in ("cd", "state"):
        res = poststratify(idata, frame, factors, group_col, args.chunk, args.seed)
        path = out_dir / f"{args.question}{suffix}_estimates_{group_col}.csv"
        res.to_csv(path, index=False)
        print(f"  {group_col}: {len(res)} estimates, range "
              f"{100 * res['estimate'].min():.1f}-{100 * res['estimate'].max():.1f}% -> {path}")

    if args.no_lookup or args.exclude:
        print("\nDone.")
        return

    print("\n[5/5] Building progressive-disclosure lookup...")
    lookup = build_lookup(idata, frame, df, factors, args.chunk, args.seed)
    lookup_path = out_dir / f"lookup_{args.question}.csv"
    lookup.to_csv(lookup_path, index=False)

    nat = lookup[(lookup[LOOKUP_DIMS] == "ALL").all(axis=1)].iloc[0]
    print(f"  national: {100 * nat['estimate']:.1f}% "
          f"[{100 * nat['q025']:.1f}, {100 * nat['q975']:.1f}]  "
          f"(n_survey {nat['n_survey']:,})")
    print(f"  -> {lookup_path}")

    print("\nDone.")


if __name__ == "__main__":
    main()
