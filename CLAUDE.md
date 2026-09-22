# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this project is

LumiGuide is a luminescence (OSL/TL) dating workflow assistant. It visualizes the analysis
pipeline and helps researchers pick a statistical age model (CAM / MAM / FMM, and related
models) from the equivalent-dose (De) distribution.
The statistics are done by the R `Luminescence` package — the project deliberately does
**not** reimplement them.

Communication with the user is in Korean; source comments are Korean.

## Direction reset (2026-09-22)

After a meeting with the domain researchers and the package review that followed, the
project restarts on these decisions (made by the user):

1. **The Streamlit frontend is retired.** The whole ver.1.0 app was moved, unchanged, from
   `app/` to `version1_streamlit/`. It still runs; read it for reference, do not extend it.
2. **`Luminescence` is the reference implementation.** Other packages are added only for a
   concrete gap, per the conditional-adoption table below — never speculatively.
3. **Analysis first, but not strictly sequential.** `R/Analysis.R` (renamed from
   `pipeline.R` on 2026-09-22) carries the priority, since nearly all unresolved risk is
   there. The order is:
   0. Fix the contract (the three decisions under Open engineering decisions) and prove it
      with the thinnest end-to-end slice on the real server.
   1. Harden `Analysis.R` against that contract **in parallel with** a frontend prototype
      built on mock data shaped by the same contract. Without step 0 the two sides would be
      guessing the interface, which is exactly the integration cost that made parallel work
      a loss before (`멀티에이전트_계획.txt` §5).
   2. Integrate and confirm the requested features end to end.
4. **The end product is a web application** hosted on a server the user provides. Server
   details are still to come — do not assume a stack, OS, or deployment model.

Decision 4 is consistent with the old plan, not a reversal: `멀티에이전트_계획.txt` §3 said
to revisit a backend layer when (a) several researchers need concurrent access, (b) the
analysis server and the screen are physically separate, or (c) the frontend moves off
Streamlit. All three now hold.

## Private context and sources

The repository is public. Requested features, the requirement source, pending inputs from
the researchers, and the list of local-only documents live in **`CLAUDE.local.md`**
(gitignored, loaded automatically). If it is missing, ask the user. **Never copy its
contents** — links, institution names, meeting-derived requirements or figures — into this
file, `README.md`, code comments, or commit messages.

- **Never open a Notion page titled "회의록", nor the local folder `회의록&자료/회의록/`.**
  Both contain personal information. This holds even when they look relevant; ask the user
  instead.
- Local-only documents (`회의록&자료/`, `멀티에이전트_계획.txt`) are gitignored — never
  commit them. Keep one issue list (the planning doc); do not start dated note files.

The target data is **single-grain** (one grain per hole on a multi-hole disc, hundreds to
thousands of grains per sample), which the current code blocks (see Current state). "Single aliquot" in
the requirements means a *multi-grain* aliquot: one De per disc. SAR is the protocol for
both.

## Package review conclusions

From `루미네선스_분석패키지_검토.html` (Luminescence 1.2.1 installed; CRAN latest 1.3.1).

- **Luminescence covers nearly every requested feature.** It ships 10 De-distribution
  models (`calc_CentralDose`, `calc_MinDose`, `calc_FiniteMixture`, `calc_CommonDose`,
  `calc_MaxDose`, `calc_AverageDose`, `calc_IEU`, `calc_FuchsLang2001`,
  `calc_WodaFuchs2008`, `calc_EED_Model`), 2 fading corrections, 3 distribution
  diagnostics, single-grain helpers (`subset_SingleGrainData`, `verify_SingleGrainData`,
  `convert_SG2MG`, `plot_SingleGrainDisc`), and all dashboard plots.
- **Package choice does not decide accuracy.** The same estimator (e.g. Galbraith 1999
  CAM) gives the same answer in any package. Accuracy is decided by three researcher
  judgments — integral choice (~15% De shift), which grains are kept, and which model
  is applied. Each added package adds a fourth: "which package was used".
- **Conditional adoption** (add only when the condition actually occurs):

  | Condition | Add |
  |---|---|
  | Model choice needs quantitative backing | numOSL `sensSAM` |
  | ML estimates insufficient for MAM/FMM uncertainty | numOSL `mcMAM`, `mcFMM` |
  | Medium/slow component contamination found in real data | `OSLdecomposition` (works on Luminescence objects) |
  | DRAC's external transfer is not allowed | numOSL `calDA` (offline) |

  numOSL has its own BIN loader and S3 classes, so it needs a conversion layer.
  **DRAC is a web service, not a package**: `use_DRAC()` sends sample data to Durham's
  server — check the institution's data policy first. RLumShiny is a GUI layer (a design
  reference for which parameters to expose), not an analysis supplement.
- **CSV import is not supported by Luminescence** (`import_Data` reads BIN/BINX, XSYG,
  Daybreak, PSL, RF, SPE, TIFF, HeliosOSL). A CSV of computed De values is trivial
  (`read.csv` → any `calc_*`); a raw Risø CSV export needs a rebuild into `RLum.Analysis`.
  Don't start either until the file type is known.

Several pieces of work wait on inputs from the researchers (listed in `CLAUDE.local.md`) —
notably the source dose rate, without which De stays in seconds. Do not guess them.

## Open engineering decisions

Decide these before hardening `Analysis.R`'s public functions, since each one changes their
signatures:

- **Output contract.** Current functions take a file *path* and write *PNGs* to disk. A web
  dashboard may instead need plot *data* (to draw client-side) or served images. Pick one
  before polishing the plotting functions.
- **R bridge.** Python backend + `rpy2` (in-process, single-threaded R — needs a lock or one
  R process per worker) vs an R-native HTTP layer (e.g. `plumber`, one R process per
  worker). This decides whether `r_runner.py` survives.
- **Execution model.** SAR runs serially per POSITION. At single-grain scale (thousands of
  grains) the runtime is unmeasured; if it is minutes, the web layer needs background jobs
  with progress.
- **Frontend stack.** Open; wait for the server details.
- **LLM layer.** RAG over an OCR'd luminescence-literature corpus that *explains* the
  rule-picked model with citations. Its interaction shape (free prompt vs structured
  narration) is not decided — do not assume a chat UI.

## Commands

The project virtualenv (Python 3.14) is still used for the legacy code and the self-checks:

```bash
source venv/bin/activate
venv/bin/python version1_streamlit/utils/r_runner.py        # R + Luminescence self-check (~2 s)
venv/bin/python version1_streamlit/utils/model_recommend.py
venv/bin/python version1_streamlit/utils/file_utils.py
venv/bin/python version1_streamlit/utils/state_manager.py   # Streamlit-specific
streamlit run version1_streamlit/main.py                    # legacy ver.1.0 UI, reference only
```

There is no test suite or linter. `r_runner.py`'s self-check is currently the only
automated test of `Analysis.R`; it generates its own R fixture from the installed package,
so it needs no committed data. `rpy2` needs a working R with `Luminescence` installed.

## Code as it stands

```
R/Analysis.R                     analysis functions inside Luminescence  ← the focus now
version1_streamlit/              the ver.1.0 app, moved intact (imports are relative to it)
  utils/r_runner.py              the only crossing point into R (rpy2)   ← fate depends on the R bridge
  utils/file_utils.py            sample_id + per-sample folder layout, CSV output
  utils/model_recommend.py       deterministic CAM/MAM/FMM rules (pure Python)
  main.py, tabs/, utils/state_manager.py   Streamlit UI
```

`r_runner.py` resolves `R/Analysis.R` as `parents[2]` of itself, so keep
`version1_streamlit/` directly under the repo root or that path breaks.

### `R/Analysis.R` — things that bite

It reads Risø `.bin` / `.rda` / `.rdata` into `Risoe.BINfileData` (`load_bin_data`,
LRU-cached), summarizes positions/records, plots curves, runs SAR, and analyses the De
distribution. Validation and error messages live in R and surface as exceptions.

- **macOS quartz png writes the file only at `dev.off()`.** Close the device right after
  drawing, then check `file.exists()`; keep `on.exit` only as a leak guard.
- **`analyse_SAR.CWOSL()` takes vectors**: `signal_integral = c(1, 2)`,
  `background_integral = c(900, 1000)` — not the old `signal.integral.min/max` form.
- **De comes out in seconds, not Gy.** Regeneration doses (`IRR_TIME`) are in seconds and no
  `dose_rate_source` is passed. Passing the source dose rate (Gy/s) to
  `analyse_SAR.CWOSL(dose_rate_source=)` converts De and the dose-response x-axis together.
  Five `Gy` labels in the code (`sar_tab.py`, `de_tab.py`, `r_runner.py`, `Analysis.R`) are
  currently wrong.
- **`Risoe.BINfileData2RLum.Analysis()` returns a list per GRAIN, not per record.** With
  several GRAINs under one POSITION, `length(obj)` is the GRAIN count.
  `.load_position_records()` validates this in one place and `stop()`s — **multi-GRAIN
  (single-grain) files are blocked, not supported.** This is the first thing to unblock:
  both measurement modes depend on it (`convert_SG2MG()` builds aliquot mode on top).
- **The `.bin_cache` key is `path + mtime + size` only.** If an object picker is added (an
  `.rda` may hold several `Risoe.BINfileData`), `object_name` must join the key.
- **Batch stages collect per-item failures instead of aborting.** `run_sar_analysis`
  returns `failed_position` + `failed_reason`, so one bad aliquot doesn't discard the rest.
- **Integral defaults are file-dependent.** `900:1000` assumes 1000 channels; read
  `NPOINTS` instead.

### `r_runner.py` (while rpy2 is the bridge)

`Analysis.R` is `source()`d once (`_ANALYSIS_LOADED` + `R_LOCK`); every R call runs under
`R_LOCK` inside `default_converter.context()`. rpy2 is not thread-safe — never call
`rpy2.robjects.r[...]` from elsewhere.

**Unpack R vectors through the `r_*_list` / `r_scalar_*` helpers**, never a bare
`int(x) if x is not None`: rpy2 returns per-type NA sentinels, not `None` — `NA_integer_`
arrives as `-2147483648`, `NA_character_` as the string `"NA_character_"` (a `str`
subclass, so `isinstance` won't catch it; `is_r_na()` compares by identity), `NA_real_` as
`nan`.

### Legacy Streamlit layer

The one idea worth carrying into the web build is `state_manager.py`'s invalidation rule:
stages declare `depends_on`, and a changed input invalidates that stage and everything that
depends on it **transitively — by dependency, not by order**. Everything else there
(widget-key rules, `st.session_state` flattening) is Streamlit-specific.

## Design principles (carry into the new build)

- **Reproducibility decides model selection.** Same input → same model, or the age is not
  publishable. Rules select CAM/MAM/FMM; the LLM (RAG) only explains the pick with
  literature citations and may offer a second opinion near a rule's boundary. A design where
  the LLM itself chooses reopens this and needs its own justification.
- **Classify, don't silently filter.** SAR marks aliquots accepted/rejected (all six
  `rejection.criteria` rows per POSITION) and keeps both. Narrowing the grains to a final
  subset fits this: keep every grain with its verdict, present the accepted list
  separately. An automatic drop is a judgment that changes the result and leaves no record.
- **Stamp the judgment parameters onto results.** Integrals are written onto every SAR row
  because they shift De ~15% and are not in the data file. Anything else that changes the
  result (dose rate, sigmab, model thresholds) follows the same rule. So do the **name and
  version of every analysis package** that produced a result — Luminescence included, not
  only supplements (installed 1.2.1 vs CRAN 1.3.1 can differ). Store them in the result
  file itself, and show them in the frontend below the result they belong to.
- **Results are written to disk**, not only held in memory (project requirement).
  `file_utils.py` defines `outputs/samples/{sample_id}/{raw,inspect,curve_plot,analysis_results}/`;
  a new SAR run deletes the previous CSVs first, so a file never mixes two runs.
- **Measurement data is never committed** (`*.bin`, `*.rda`, … in `.gitignore`).

## Current state

Implemented in ver.1.0 (Streamlit): upload, signal analysis, SAR (De, QC classification,
dose-response plots, CSV), De distribution (OD, skewness, FMM BIC, radial/abanico) with
rule-based recommendation in `model_recommend.py`.

Known defects to resolve in the analysis-first phase:

- **Single-grain files are blocked** (above) — yet they are the target data.
- **De unit** is seconds (above) — needs the dose rate.
- **Recommendation gate order is wrong for multimodal data.** The positive-skew (MAM) gate
  runs before the multimodality (FMM) gate, and skewness is computed on raw De, where a
  lognormal is always right-skewed — so genuine 2–3 component mixtures are classified MAM.
  Do not reorder without expert review (it changes published ages); until then, do not
  trust MAM/FMM separation on multimodal data. Negative/zero De stops explicitly (the
  unlogged path is not implemented).
- **Scale is untested**: 24 POSITIONs today vs thousands of grains.

**Verification baseline** (for spotting drift): `ExampleData.BINfileData`
(`CWOSL.SAR.Data`) has 24 POSITIONs; a clean SAR run gives 24/24 analysed, 22 passing QC
(POSITIONs 8 and 11 fail), De 684–1905 **s** (seconds — see the unit note), CV ~17%.
`r_runner.py`'s self-check asserts per-POSITION De ranges from this baseline, regenerating
the fixture from the installed package. Local test inputs (`test_data/`, including
hand-made multi-GRAIN and subset `.bin` files) are gitignored and for manual testing only.
