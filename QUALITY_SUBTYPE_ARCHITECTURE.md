# Quality Workout Subtype System

## Why this exists

Before this change, every quality workout in SmarterTraining was a threshold-interval session. "Quality day" effectively meant "4 x 5 min @ 95–100% FTP." That collapsed a meaningful coaching dimension into a single template and made the app feel mechanical to anyone who trained more than a few weeks.

A real coach doesn't only choose *whether* today is a hard day — they also choose *which kind* of hard. Today's freshness, time, history, and recent stimulus all shape that choice. This system lifts that dimension into the model and into the recommendation engine so the app can serve a coherent variety of quality work without exposing extra complexity to the user.

The product still feels calm. The user sees a workout, a reason, and a button. The subtype lives in the title ("VO2 Max Intervals", "Tempo Ride"), shows up as a small pill in the workout summary, and threads through analytics, history, and the trainer runtime.

---

## The five subtypes

| Subtype             | Power zone           | Coaching purpose                                      | Recovery cost |
|---------------------|----------------------|-------------------------------------------------------|---------------|
| **VO2 Max**         | 106–115% FTP         | Raise the ceiling. Short, sharp above-threshold work. | High (3)      |
| **Threshold**       | 95–100% FTP          | Build the ceiling itself. Sustained at-threshold.     | High (3)      |
| **Over/Unders**     | alternating 105% / 88% | Lactate management; ride through surges.            | Mod-high (2)  |
| **Muscular Endurance** | 88–95% FTP        | Durability. Long sub-threshold blocks.                | Moderate (2)  |
| **Tempo**           | 80–87% FTP           | Repeatable quality dose. Productive, low hole-digging.| Low-mod (1)   |

Recovery cost is encoded on `QualitySubtype.recoveryCost` and read by `TrainingIntentBuilder.buildFromFeedback` when shaping the next day:

- **Cost 3** (VO2, Threshold) → day1 forced to `.recovery`.
- **Cost 2** (Over/Unders, ME) → day1 is `.endurance` unless the workout landed `.hard` / `.tooMuch` / perceived effort ≥ 8.
- **Cost 1** (Tempo) → day1 is `.endurance` unless the workout landed hard.

A tempo session that landed "right" no longer mandates the same recovery as a VO2 session that landed "right" — which matches how a real coach would actually think about it.

---

## Selection heuristics

`RecommendationEngine.chooseQualitySubtype(for:)` is only called *after* the engine has decided the type is `.quality`. Its job is just to pick *which* quality.

Priority order:

1. **Honor explicit intent — only when active today.** If a `ShortTermTrainingIntent` carries a `qualitySubtype` *and* today is the intent's day1 or day2, use it. Expired intents and intents outside their active window are ignored.
2. **Load down-shift.** If the week already shows real load (`hardDayCount7d ≥ 2` or `recentIntensityLoadEstimate ≥ 8` or `hasHighRecentLoad`), the priority order is replaced with `[ME, tempo, threshold]`. VO2 and over-unders are withheld — the body needs sub-threshold work, not more max-cost stimulus.
3. **VO2 gating.** Outside of load down-shift, VO2 still requires *all* of: peak readiness, willingness ≥ 1, history ≥ 2 entries, and not returning after a break. This keeps brand-new users and returning athletes off the highest-cost option.
4. **Build the eligibility list** in priority order (hardest first):
   - VO2 → if all VO2 gates pass + time ≥ 25.
   - Over/Unders → good readiness + time ≥ 35.
   - Threshold → good readiness + time ≥ 25.
   - Muscular Endurance → time ≥ 35 (forgiving readiness; sub-threshold is repeatable).
   - Tempo → always eligible.
5. **Variety filter (3 layers):**
   - Drop any subtype with 2+ uses in the last 7 days (`recentQualitySubtypes7d`).
   - Prefer subtypes never used this week over subtypes used once.
   - Drop the immediately-prior subtype (`lastQualitySubtype`) when more than one candidate remains.
6. **Pick the first.** Fallback to tempo if the list is somehow empty.

This is a coach's decision tree, not a scoring function. There's no opaque math; you can read the code and know what got picked and why.

### How the heuristic plays across a week

Empty memory, peak readiness, 60 min/day, very-consistent athlete:

| Day | recentQualitySubtypes7d | lastSubtype | Picked |
|-----|-------------------------|-------------|--------|
| 1   | []                      | nil         | VO2    |
| 2   | [VO2]                   | VO2         | Over/Unders (VO2 dropped, ME/threshold/tempo neverUsed-tier with over-unders) |
| 3   | [VO2, Over/Unders]      | Over/Unders | Threshold (top of neverUsed tier) |
| 4   | [..., Threshold]        | Threshold   | ME (only ME and tempo never-used) |
| 5   | [..., ME]               | ME          | Tempo (only tempo never-used) |

Four to five sessions before the week-level filter starts recycling — and even then it prefers the least-used subtypes first.

---

## Workout templates

Each subtype has three time variants (≤30 min, ~45 min, ≥60 min). Examples:

**VO2 Max — 45 min**
```
Warm-up    10 min  Build from easy to steady, include 2 x 30 sec openers
Main Set    5 x 3 min  106–112% FTP with 3 min easy between reps
Cool down   5 min   Easy spin
```

**Muscular Endurance — 60 min** (the "3 x 12" the spec calls out)
```
Warm-up    10 min  Build from easy to steady
Main Set    3 x 12 min  88–95% FTP with 4 min easy between reps
Cool down   8 min   Easy spin
```

**Tempo — 60 min**
```
Warm-up    10 min  Build from easy to steady
Main Set    2 x 20 min  80–87% FTP with 5 min easy between reps
Cool down   8 min   Easy spin
```

**Over/Unders — 60 min**
```
Warm-up    12 min  Build from easy to steady, include 2 x 1 min openers
Main Set    4 x 6 min  Alternate 2 min @ 105% FTP / 1 min @ 88% FTP, 4 min easy between sets
Cool down   8 min   Easy spin
```

---

## Trainer runtime: over/under expansion

The display-layer `WorkoutStep` for over/unders uses a compact "4 x 6 min" durationText with the alternating pattern described in `targetText`. `WorkoutConverter` inspects `recommendation.qualitySubtype` — when it sees `.overUnders` on a primary interval step, it routes to `expandOverUnders`, which generates alternating sub-steps:

```
Over (Set 1 of 4)   2 min  @ 105% FTP
Under (Set 1 of 4)  1 min  @ 88%  FTP
Over (Set 1 of 4)   2 min  @ 105% FTP
Under (Set 1 of 4)  1 min  @ 88%  FTP
Recovery            4 min  @ 55%  FTP
Over (Set 2 of 4)   2 min  @ 105% FTP
...
```

The runtime already executes steps sequentially, so no runtime changes were needed. ERG transitions between over and under happen on the existing ramp controller.

---

## What ships with this

- `QualitySubtype` enum (Models.swift) — top-level, codable, with `label` and `recoveryCost`.
- `WorkoutRecommendation.qualitySubtype` — set by the engine, persisted with the recommendation.
- `WorkoutHistoryEntry.qualitySubtype` — recorded when the entry is appended, so memory can read it back. Backwards-compatible decoder for existing history.
- `TrainingMemorySummary.lastQualitySubtype` + `recentQualitySubtypes7d` — feeds the variety filter.
- `RecommendationEngine.chooseQualitySubtype(for:)` and five subtype-specific builders.
- `WorkoutConverter` over/under expansion path.
- UI: subtype pill in `WorkoutDetailView` header; `Quality · VO2 Max`-style label in `HistoryRowView`. The hero card already carries the subtype implicitly via the workout title.
- Analytics: `recommendationGenerated` now includes `quality_subtype`.
- Tests in `SmarterTrainingTests.swift`:
  - `QualitySubtypeSelectionTests` — proves VO2 is selected at peak readiness, ME/threshold/over-unders rotate, tempo is the fallback, intent hints are honored.
  - `QualitySubtypeBuilderTests` — proves each of the five builders produces the right title, subtype tag, and power references.
  - `OverUnderConverterTests` — proves the converter generates alternating over/under sub-steps with higher power on the over.

---

## Example: end-to-end recommendation

Peak-readiness user (Great / Fresh / High, 45 min, willingness +2, last quality was threshold):

1. `chooseWorkoutType` returns `.quality` (existing logic, unchanged).
2. `chooseQualitySubtype`:
   - Eligibility: `[.vo2, .overUnders, .threshold, .muscularEndurance, .tempo]`
   - Variety filter removes nothing (last was threshold, but threshold isn't first)
   - Returns `.vo2`.
3. `buildWorkout(type: .quality, subtype: .vo2, time: 45, reason: ...)`:
   - Title: "VO2 Max Intervals"
   - Summary: "Hard intervals above threshold"
   - Steps: 10 min warm-up, 5 x 3 min @ 106–112% FTP with 3 min recovery, 5 min cool-down.
4. `WorkoutRecommendation` carries `qualitySubtype: .vo2`.
5. `WorkoutHistoryEntry` appended with `qualitySubtype: .vo2`. Next-day memory will know.
6. Analytics emits `quality_subtype: "vo2"`.
7. `WorkoutDetailView` shows the type pill "Quality" alongside a softer pill "VO2 Max".

Same user the next quality day (memory shows `lastQualitySubtype = .vo2`):

- Eligibility identical, but the variety filter removes `.vo2`, so the next pick is `.overUnders` (next in priority order).
- Title becomes "Over/Under Sets". The athlete naturally rotates.

---

## What this is not

- **Not a planner.** There's no week-level schedule, no periodization model, no automated mesocycles. The engine still makes one decision at a time.
- **Not an adaptive progression system.** Rep counts and intensities don't yet auto-progress based on completion feedback. That's the next layer.
- **Not opaque.** No black-box scoring — the selection tree is readable Swift and the templates are explicit literals.
- **Not visually loud.** The subtype shows up as a single soft pill on the detail view and as a `·` segment in the history row. The hero card title carries the subtype name and that's intentionally the loudest signal.

---

## Where this is going

Once subtypes are landing in real recommendations and being tracked in history, the natural next layers are:

1. **Adaptive progression within subtype.** If the last three VO2 sessions all landed "easy," next time bump from `5 x 3 min` to `5 x 3:30` or `6 x 3 min`. The data is already there in the history feedback.
2. **AI coach uses the subtype.** The post-workout reflection prompt should know whether yesterday was VO2 vs. tempo when deciding what to suggest for tomorrow. The intent already has a `qualitySubtype` field — the backend just has to populate it.
3. **"Likely tomorrow" preview.** If the engine picked VO2 today, it can show "Tomorrow looks like an easier endurance day" in the reflection. The recoveryCost field is what makes that possible.
