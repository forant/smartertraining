# Adaptive Progression Architecture

Strategic analysis of SmarterTraining's coaching state, adaptation mechanisms, and progression signals. This document maps what the app knows, stores, infers, and adapts today, and identifies what's needed for a next-generation adaptive progression system.

---

## 1. Product Philosophy / Inferred Coaching Model

### What coaching philosophy does the app currently embody?

SmarterTraining embodies a **conservative, protective coaching model**. The recommendation engine's decision tree has 8+ sequential gates, and the majority exist to *prevent* intensity rather than *prescribe* it. The system's default output is endurance; quality must be actively earned through converging positive signals.

This maps well to the stated product identity: training for people with real lives. The engine treats the athlete as someone who benefits more from being protected from overreach than pushed toward performance peaks.

### Core coaching assumptions

1. **Subjective signals are more trustworthy than objective metrics.** The engine makes workout-type decisions entirely from self-reported feel, legs, motivation, and feedback. Power/HR data is captured but not used in recommendation logic.

2. **Recovery is always the safe choice.** Four hard recovery overrides fire before any other logic (Bad feel, Dead legs, Getting sick, Poor sleep + Heavy legs). These are non-negotiable.

3. **Quality work is earned, not scheduled.** Quality requires: Great feel + High motivation + Fresh/Normal legs + no recent tooMuch feedback + 1-2 easier sessions prior + no high weekly load + no upcoming context blocks + positive willingness score. All conditions must align simultaneously.

4. **The last session matters most.** `lastWorkoutFeedback` is a first-class input. "Too much" triggers immediate recovery bias and 7-day quality suppression. "Easy" enables quality via the "easy boost" pathway.

5. **Non-cycling stress counts.** Hard tennis, MTB rides, strength sessions, and yard work all contribute to `activityStress`, which can suppress quality recommendations. The system reasons holistically about load, not just trainer hours.

6. **Time constrains structure, not intensity.** A user reporting 20 minutes gets a compressed workout template, but the *type* decision (recovery/endurance/quality) is independent of time availability.

### What is static vs. adaptive today?

**Static (set once, rarely changed):**
- FTP (manual entry during onboarding)
- Fitness state (justStarting/gettingBack/consistent/veryConsistent)
- Training goals (endurance/stronger/consistent/healthier/bikePerformance)
- Training frequency (light/moderate/heavy/flexible)
- Equipment inventory
- Quality willingness score (derived from profile, range -2 to +2)

**Adaptive (changes daily):**
- Workout type selection (8-gate decision tree with 30+ branching conditions)
- Workout template (time-dependent structure)
- Coaching rationale (24+ context-aware reason templates)
- 2-day training intent (generated post-workout from AI reflection or feedback fallback)
- Upcoming context modulation (7-day lookahead from user-entered events)

**The gap:** The static layer never updates from observed behavior. A user who set "just starting" six months ago and has completed 100 quality sessions still carries a -2 willingness penalty. The adaptive layer reasons daily but has no memory of multi-week trends or progression arcs.

### What progression concepts already exist implicitly?

- **Consistency tracking:** `completedWorkoutCount7d` and `completedWorkoutCount14d` measure volume, but are used only for reason text and load assessment, not progression decisions.
- **Load estimation:** `recentIntensityLoadEstimate` weights quality=3, endurance=2, recovery=1 over 7 days. Used to block quality when load is high, but not to prescribe progressive overload.
- **Return-after-break protocol:** 5+ days off triggers conservative re-entry (recovery or endurance only, no quality). This is an implicit detraining recognition.
- **Back-to-back quality prevention:** Hard structural rule that quality sessions are never consecutive. This is implicit recovery periodization.
- **Easier-session requirement:** Quality needs 1-2 easier sessions prior. This creates an implicit work-recovery rhythm.

---

## 2. Current Athlete Memory / State Model

### Persistent athlete data

| Data | Storage | Retention | Used in Recommendations | Notes |
|------|---------|-----------|------------------------|-------|
| **FTP** | UserDefaults (UserProfile) | Until manually changed | Workout templates (power targets), edit evaluator | Never auto-updated from performance |
| **Fitness state** | UserDefaults (UserProfile) | Until manually changed | Quality willingness score (-2 to +1) | Never auto-updated |
| **Training goals** | UserDefaults (UserProfile) | Until manually changed | Willingness bias, reason text | Static after onboarding |
| **Training frequency** | UserDefaults (UserProfile) | Until manually changed | Willingness score (-1 to +1) | Static |
| **Equipment** | UserDefaults (UserProfile) | Until manually changed | Optional extras only | No effect on type/intensity |
| **Workout history** | LocalStore (workouts.json) | 30 entries max locally, unlimited on backend | 7/14-day aggregations, type distribution, feedback patterns | CheckIn snapshot embedded per entry |
| **Completed rides** | LocalStore (rides/{id}.json) | Unlimited locally | Training memory builder, post-workout charts | Full per-second samples + aggregates |
| **Training intent** | LocalStore (training_intent.json) | 3-day expiry | Gate 2 in recommendation engine | Single active intent at a time |
| **Upcoming context** | LocalStore (upcoming_context.json) | 14-day cleanup, 7-day lookahead | Gates 5 in recommendation engine | User-entered events |
| **Latest check-in** | UserDefaults | Until next check-in | Current recommendation | Only latest preserved in UserDefaults |
| **Last check-in date** | UserDefaults | Until next check-in | `hasCheckedInToday` routing | Controls check-in vs. TodayView flow |
| **Sync metadata** | LocalStore (sync_status.json) | Unlimited | Not used in recommendations | Tracks upload/sync state |

### Derived/computed state (ephemeral, recomputed daily)

| Signal | Window | Source | Current Usage |
|--------|--------|--------|---------------|
| `completedWorkoutCount7d` | 7 days | History entries | Reason text ("You've been consistent") |
| `completedWorkoutCount14d` | 14 days | History entries | Calculated but **never used** |
| `hardDayCount7d` | 7 days | Quality type + hard/tooMuch feedback | Quality blocking (>=3 = high load) |
| `recoveryDayCount7d` | 7 days | Recovery type entries | Calculated but **minimally used** |
| `daysSinceLastWorkout` | All history | Most recent entry date | Return-after-break detection (>=5 days) |
| `lastWorkoutFeedback` | 1 session | Most recent feedback | Primary adaptation signal |
| `hadTooMuchFeedback7d` | 7 days | Any tooMuch in window | 7-day quality suppression |
| `recentIntensityLoadEstimate` | 7 days | Weighted sum (Q=3, E=2, R=1) | Quality reason text only, **not in type selection** |
| `recentActivities` | 3 days | CheckIn.recentActivities flattened | Activity stress calculation |
| `recentLifeStressLevel` | 3 days | High-stress context flags, capped 0-3 | Combined with hardDayCount for quality blocking |

### Per-ride telemetry (persisted in CompletedWorkout)

| Metric | Type | Persistence | Currently Used For |
|--------|------|-------------|-------------------|
| `samples: [TrainerMetrics]` | Per-second array (power, HR, cadence, speed, timestamp) | Unlimited on disk | Post-workout charts, HealthKit export |
| `averagePower` | Int? | With ride | Chart display, Strava export, reflection request |
| `maxPower` | Int? | With ride | Chart display, reflection request |
| `averageHeartRate` | Int? | With ride | Chart display, reflection request |
| `maxHeartRate` | Int? | With ride | Chart display |
| `averageCadence` | Int? | With ride | Chart display, reflection request |
| `ergWasEnabled` | Bool? | With ride | Detail view badge |
| `workoutFeedback` | Enum? | With ride | Intent builder, recommendation engine (via history) |
| `perceivedEffort` | Int? (1-10) | With ride | Intent builder threshold (>=8 triggers recovery) |
| `postWorkoutNote` | String? | With ride | Sent to AI reflection service |
| `reflection` | PostWorkoutReflection? | With ride | Training intent generation, detail view |

### What's NOT stored that could support progression

- No FTP history or auto-detection
- No workout compliance metric (prescribed vs. actual)
- No interval-level performance data (rep 1 vs. rep 4 power)
- No HR drift calculation (cardiac decoupling)
- No power duration curve or critical power model
- No recovery rate metrics (HR recovery post-interval)
- No session TSS/IF/NP computation
- No training phase or block tracking
- No goal progress metrics
- No sleep or HRV data (despite HealthKit integration)
- No long-term consistency metrics (streaks, weekly averages)
- No workout modification history (what was changed, how often)

---

## 3. Workout Generation Architecture

### How workouts are generated today

The recommendation engine is a pure function: `RecommendationEngine.recommend(for: Inputs) -> WorkoutRecommendation`. No side effects, no state mutation, fully testable.

**Input assembly (AppState.generateRecommendation):**
```
UserProfile (static)
  + CheckIn (daily)
  + recentHistory (30 entries)
  + TrainingMemorySummary (7/14/3-day aggregations)
  + ShortTermTrainingIntent? (2-day coaching arc)
  + UpcomingContextSummary (7-day event lookahead)
  = RecommendationEngine.Inputs
```

**Output:** `WorkoutRecommendation` containing type, title, summary, reason narrative, structured steps, and equipment-aware optional extras.

### Decision flow: chooseWorkoutType()

The engine uses a **sequential gate architecture**. Each gate either returns a type or falls through:

```
Gate 1: Hard Recovery Overrides
  Bad feel, Dead legs, Getting sick, Poor sleep + Heavy legs
  → .recovery (non-negotiable)

Gate 2: Active Training Intent
  If 2-day intent exists and not expired, apply its recommendation
  → .recovery / .endurance / .quality / nil (fall through if .flexible)

Gate 3: Activity Stress Override
  If actStress >= 2 and feel != Great
  → .recovery (heavy legs) or .endurance

Gate 4: Return After Break
  If 5+ days since last workout
  → .recovery (if not great/fresh) or .endurance

Gate 5: Upcoming Context
  Big ride within 1 day, recovery-focused period, travel within 1 day
  → .recovery or .endurance (blocks quality)

Gate 6: Prior Feedback - tooMuch
  If last feedback was tooMuch
  → .recovery or .endurance

Gate 7: Memory tooMuch Pattern
  If any tooMuch in past 7 days (not just yesterday)
  → .endurance (if heavy legs or okay feel)

Gate 8: Back-to-Back Quality Prevention
  If last workout was quality
  → .recovery or .endurance (never consecutive quality)

Gate 9: Quality Readiness Assessment
  Multi-factor evaluation: willingness + signal strength + easier history + load assessment
  Three pathways to quality, all requiring convergence of 5+ positive signals
  → .quality (if all conditions met)

Default: .endurance
```

### Where adaptation currently happens

Adaptation is **reactive and short-term**:

1. **Daily check-in signals** drive same-day type selection
2. **Last feedback** (easy/right/hard/tooMuch) shifts next-day type
3. **7-day pattern** (tooMuch anywhere in window) suppresses quality
4. **2-day training intent** (from AI reflection or feedback fallback) overrides default logic
5. **Upcoming context** (user-entered events) modulates type selection

Adaptation does NOT happen at these levels:
- No multi-week periodization
- No progressive overload (longer intervals, higher power)
- No workout archetype evolution
- No personalized threshold/FTP adjustment
- No learning from HR/power response patterns

### Workout archetypes

All workouts are built from fixed templates based on type + available time:

**Recovery:**
- <= 20 min: "Easy Spin" (single block, <55% FTP)
- \> 20 min: "Recovery Day" (warmup + main <60% FTP + cooldown)

**Endurance:**
- <= 20 min: "Short Aerobic Spin" (3 min warmup, 15 min Zone 2, 2 min cool)
- <= 30 min: "30 min Zone 2 Ride" (5/20/5 split)
- \> 30 min: "45 min Zone 2" or "60 min Endurance" (5/35-50/5 split, 70-80% FTP)

**Quality:**
- <= 30 min: "Compact Threshold" (5 min warmup, 3x4 min @ 95-100% FTP w/ 2 min easy, 5 min cool)
- 30-60 min: "Threshold Intervals" (10 min warmup, 4x5 min @ 95-100% FTP w/ 3 min easy, 10 min cool)
- \>= 60 min: "Full Threshold Intervals" (15 min warmup, 4x6 min @ 95-100% FTP w/ 3 min easy, 10 min cool)

**Key limitation:** Quality is always threshold intervals. No VO2max, sweet spot, muscular endurance, tempo, or over-under archetypes. The `qualitySubtype` field exists on `ShortTermTrainingIntent` (vo2, threshold, muscularEndurance, tempo, overUnders) but is never used for workout generation.

### How durations/intensities are chosen

- **Duration:** Determined entirely by `checkIn.timeAvailable`. Templates are hard-coded to time buckets.
- **Intensity zones:** Hard-coded as FTP percentages in step target text. Recovery <55-60%, Endurance 70-80%, Quality 95-100%.
- **Warmup/cooldown:** FTP-based ramps added by `WorkoutConverter.convertStep()`. Warmup ramps from 40% FTP to target. Cooldown ramps from target to 35% FTP.

### Deterministic vs. heuristic vs. AI

| Component | Type | Description |
|-----------|------|-------------|
| Hard recovery overrides | Deterministic | Dead legs always = recovery |
| Back-to-back quality prevention | Deterministic | Quality never follows quality |
| Type selection (Gates 1-9) | Heuristic | Weighted signal evaluation with fixed thresholds |
| Reason text generation | Heuristic | Pattern-matched from ~24 templates |
| Workout templates | Deterministic | Fixed structures per type + time bucket |
| AI coach explanation | AI-driven | Backend LLM generates deeper "why" narrative |
| Post-workout reflection | AI-driven | Backend LLM generates session evaluation + 2-day intent |
| Training intent (fallback) | Heuristic | Feedback + effort → simple day-1/day-2 prescription |

---

## 4. Runtime Telemetry and Workout Execution

### TrainerWorkoutRuntime

State machine: `ready -> running <-> paused -> finished`

**Tick-based execution:** 1-second timer drives `tick()` which:
1. Increments `totalElapsed` and `stepElapsed`
2. Captures sample via `captureSample()` (reads `trainerManager.metrics`, substitutes HRM heart rate if trainer HR is nil/0)
3. Checks step completion (`stepElapsed >= step.duration` triggers `advanceStep()`)
4. Updates within-step ramp ERG targets (every 3 seconds for ramp steps)
5. Updates between-step ramp ERG targets (every 2 seconds via `ERGRampController`)
6. Updates cadence guidance status

### Metric capture

Per-second `TrainerMetrics` samples contain:
- `power: Int?` — Watts from FTMS characteristic (bit-parsed, little-endian)
- `cadence: Double?` — RPM at 0.5 resolution
- `speed: Double?` — km/h at 0.01 resolution
- `heartRate: Int?` — BPM from trainer or HRM fallback
- `timestamp: Date` — Millisecond precision

**Sample rate:** 1 Hz (every tick)
**Memory:** Unbounded array growth; ~360 KB for a 1-hour ride
**Disk persistence:** Every 10 seconds via `saveRideSnapshot()` (up to 10 seconds of data loss on crash)

### Power smoothing

`PowerSmoother` maintains a 3-second rolling average for UI display. Window-based: filters samples within last 3 seconds, computes integer mean. Not persisted post-workout.

### ERG control

**Acquisition:** 8-second timeout. Sends `.requestControl` to FTMS control point. States: off -> enabling -> active (or .unsupported / .failed).

**Between-step ramps:** `ERGRampController` uses 8-second smoothstep easing (t^2 * (3 - 2t)) with commands sent every 2 seconds. Minimum 5W delta to trigger. Creates smooth S-curve transitions.

**Within-step ramps:** Linear interpolation from `rampFromPower` to `targetPower` over step duration. ERG updates sent every 3 seconds. Used for warmup (40% FTP -> target) and cooldown (target -> 35% FTP).

### Completion logic

**Normal completion:** All steps executed -> `runtime.finish()` -> stops timer + sends `.stop` to trainer -> `finishRide()` computes HR aggregates, calls `computeStats()`, saves to disk, triggers sync, transitions to `.feedback` phase.

**Cancellation:** User taps Close -> analytics track abandonment -> `runtime.finish()` + disconnect. Ride persists on disk as `.inProgress`. No feedback collected.

### Post-workout signals available for future adaptation

**Already captured and persisted:**
- Full per-second power time series (enables: power duration curves, variability analysis, interval segmentation, fatigue detection)
- Full per-second HR time series (enables: cardiac drift analysis, HR-power decoupling, recovery rate)
- Per-second cadence (enables: efficiency analysis, fatigue-driven cadence drop)
- Session aggregates (avg/max power, avg/max HR, avg cadence)
- ERG state (whether controlled or guided mode)
- Workout type and step structure (what was prescribed)
- Perceived effort (1-10 scale)
- Categorical feedback (easy/right/hard/tooMuch)
- Free-form notes
- AI reflection with 2-day guidance

**Captured during ride but NOT persisted:**
- Smoothed power (3-second rolling average)
- Cadence guidance warnings (low cadence events)
- Between-step ramp execution (timing, targets)
- HR source (trainer vs. HRM vs. HealthKit)

**Not captured at all:**
- Power variability / coefficient of variation
- HR drift per interval
- Time to target power after ERG command
- Individual interval metrics (rep-by-rep analysis)
- Normalized power / intensity factor / TSS
- Power duration curve
- Pedal smoothness
- Recovery HR drop post-interval

---

## 5. Qualitative Feedback System

### Subjective inputs collected

**Daily check-in (6 steps):**

| Step | Question | Options | Storage |
|------|----------|---------|---------|
| 0 | "How do you feel today?" | Great, Good, Okay, Bad | CheckIn.overallFeel |
| 1 | "How do your legs feel?" | Fresh, Normal, Heavy, Dead | CheckIn.legs |
| 2 | "How motivated are you?" | High, Medium, Low | CheckIn.motivation |
| 3 | "How much time do you have?" | 20, 30, 45, 60+ min | CheckIn.timeAvailable |
| 4 | "Any other physical activity recently?" | Multi-select: Tennis, Strength, MTB, Run, Walk/hike, Sports, Yard work, Snow sports, Other. Each with timing (Today/Yesterday/2-3 days ago) and intensity (Easy/Moderate/Hard/Very hard) | CheckIn.recentActivities[] |
| 5 | "How's life outside training?" | Multi-select: Poor sleep, High work stress, Family exhaustion, Travel, Mentally drained, Getting sick, Sore legs, Low motivation, Busy day ahead, Other | CheckIn.contextFlags[] |

**Post-workout feedback:**
- Categorical: easy / right / hard / tooMuch (WorkoutFeedback enum)
- Effort scale: 1-10 integer (perceivedEffort)
- Free-form note: String, capped at 200 chars

### How subjective data affects recommendations

**Immediate (same-session):**
- `overallFeel` + `legs` + `motivation` directly gate workout type
- `contextFlags` containing "Getting sick" or "Poor sleep" + "Heavy" legs trigger hard recovery overrides
- `timeAvailable` selects workout template duration
- `recentActivities` calculate `activityStress` (0-2 scale)

**Next-session (via feedback):**
- `lastWorkoutFeedback == .tooMuch` forces recovery or endurance
- `lastWorkoutFeedback == .easy` enables quality via "easy boost"
- `perceivedEffort >= 8` triggers recovery intent in fallback builder

**7-day window:**
- `hadTooMuchFeedback7d` suppresses quality even if yesterday's feedback was fine
- `hardDayCount7d` (quality type + hard/tooMuch feedback) blocks quality at >= 3
- `recentLifeStressLevel` (high-stress flags from 3-day window, capped at 3) combined with hard days blocks quality

### Longitudinal persistence

**Preserved:** Check-in data is embedded in each `WorkoutHistoryEntry.checkIn` and persisted with workout history (30-entry local cap, unlimited on backend). This means subjective state snapshots exist for every workout day.

**Lost:** Only the latest check-in is stored in UserDefaults. Check-in data from days without workouts is not captured. There is no standalone check-in history.

**Aggregated:** `TrainingMemoryBuilder` extracts 3-day activity and stress patterns from embedded check-ins. 7-day and 14-day workout counts are computed. No longer-term aggregation exists.

---

## 6. Existing Progression Signals

This section identifies all places where the current app already implicitly tracks adaptation-relevant data, even if the system does not formally use them.

### Signals currently used for daily decisions

| Signal | How Tracked | Decision Impact |
|--------|-------------|-----------------|
| Workout type distribution (7d) | hardDayCount7d, recoveryDayCount7d | >= 3 hard days blocks quality |
| Feedback pattern (7d) | hadTooMuchFeedback7d | Suppresses quality for a week |
| Last feedback | lastWorkoutFeedback | tooMuch = recovery, easy = quality boost |
| Break detection | daysSinceLastWorkout >= 5 | Conservative re-entry |
| Activity stress | recentActivities (3d) | Suppresses quality if high external load |
| Life stress | contextFlags (3d) | Combined with hard days to block quality |

### Signals captured but NOT used in recommendations

| Signal | Where Stored | Potential Progression Use |
|--------|-------------|-------------------------|
| **Average power per ride** | CompletedWorkout.averagePower | Track power output trends over weeks/months |
| **Max power per ride** | CompletedWorkout.maxPower | Track peak capacity changes |
| **Average HR per ride** | CompletedWorkout.averageHeartRate | HR-power efficiency ratio over time |
| **Max HR per ride** | CompletedWorkout.maxHeartRate | Cardiac ceiling tracking |
| **Average cadence** | CompletedWorkout.averageCadence | Efficiency pattern tracking |
| **Per-second power samples** | CompletedWorkout.samples | Interval-level analysis, power duration curves, variability |
| **Per-second HR samples** | CompletedWorkout.samples | Cardiac drift, HR recovery, decoupling analysis |
| **Perceived effort (1-10)** | CompletedWorkout.perceivedEffort | RPE-to-power calibration, internal load tracking |
| **Workout duration** | CompletedWorkout.duration | Volume tracking, time-in-zone |
| **Workout type** | CompletedWorkout.workoutType | Type distribution analysis over months |
| **ERG state** | CompletedWorkout.ergWasEnabled | Session quality indicator (controlled vs. free ride) |
| **Post-workout note** | CompletedWorkout.postWorkoutNote | Qualitative pattern mining |
| **AI reflection** | CompletedWorkout.reflection | Coach assessment history |
| **Quality subtype** | ShortTermTrainingIntent.qualitySubtype | Energy system targeting (vo2/threshold/ME/tempo) |
| **completedWorkoutCount14d** | TrainingMemorySummary | 2-week consistency trend (computed but never queried) |
| **recentIntensityLoadEstimate** | TrainingMemorySummary | Weighted load score (used only in reason text, not type selection) |
| **recoveryDayCount7d** | TrainingMemorySummary | Recovery proportion (computed, barely used) |
| **Workout modifications** | WorkoutEditor.isModified (boolean) | Whether athlete adjusted the recommendation (not persisted) |
| **HealthKit workout** | CompletedWorkout.healthKitWorkoutUUID | Cross-reference with Apple Health data |

### Implicit progression indicators derivable from existing data

**Athlete improvement:**
- Average power trending upward for same workout type over 4+ weeks
- Same interval targets becoming "easy" (feedback shifting from "right" to "easy")
- Max power increasing over time

**Workout success/failure:**
- Feedback == "right" indicates well-calibrated prescription
- Feedback == "tooMuch" indicates over-prescription
- Feedback == "easy" indicates under-prescription or fitness gain
- Perceived effort decreasing for similar workouts indicates adaptation

**Adaptation readiness:**
- Fresh legs + Great feel appearing more frequently after quality sessions
- Shorter recovery between quality sessions (quality every 3 days vs. every 5 days)
- Activity stress tolerance increasing (hard tennis + quality workout both rated "right")

**Recoverability:**
- Days between quality sessions where athlete reports "Fresh" legs
- Frequency of "Heavy" or "Dead" legs after quality work
- Whether tooMuch feedback frequency is decreasing

**Durability:**
- Total weekly training time trending upward
- Longer endurance sessions becoming "easy"
- Maintaining quality feedback ratings as session duration increases

**Fatigue tolerance:**
- hardDayCount7d increasing without tooMuch feedback
- recentIntensityLoadEstimate increasing without negative signals
- Life stress flags present but quality still rated "right"

**HR trends (from samples):**
- Average HR for same power output decreasing over weeks = aerobic fitness gain
- Max HR stability or increase = maintained ceiling
- HR recovery rate between intervals improving

---

## 7. Missing Layers for True Adaptive Progression

### The core gap

The app currently makes daily decisions in a memoryless way. Each recommendation treats the athlete as if today is their first day, informed only by a 7-day rolling window. There is no concept of:

- Where the athlete is in a progression arc
- What they've been building toward
- How their capacity has changed over months
- What energy systems need development
- Whether workout prescriptions are well-calibrated to their actual abilities

The system can protect athletes from overreach (reactive) but cannot guide them toward improvement (proactive).

### Likely easy wins

These require minimal architectural change - mostly computation over existing persisted data:

1. **Session TSS/IF/NP computation**
   - All data exists (per-second power, FTP). Compute normalized power, intensity factor, and training stress score for each ride.
   - Store as computed fields on CompletedWorkout.
   - Enables: CTL/ATL/TSB tracking, load management.

2. **Interval-level segmentation**
   - Step structure is known (TrainerWorkoutStep array). Map sample timestamps to steps.
   - Compute per-interval: avg power, max power, avg HR, power variability.
   - Store as array on CompletedWorkout.
   - Enables: Rep-by-rep fatigue detection, interval quality scoring.

3. **Feedback-to-power calibration**
   - Compare `workoutFeedback` against `averagePower` and workout type over time.
   - If "easy" feedback correlates with rising average power, the athlete is adapting.
   - No new data needed, just correlation analysis.

4. **Consistency metrics**
   - Compute rolling weekly averages: sessions/week, hours/week, TSS/week.
   - Derive consistency score from variance of weekly values.
   - Surface in UI and feed to recommendation engine.

5. **Auto-detect FTP changes**
   - If quality workouts are consistently rated "easy" and average power exceeds current FTP targets, suggest FTP update.
   - Or compute from power duration curve across recent rides.

6. **Persist workout modifications**
   - Currently `editor.isModified` is a boolean checked at display time but not stored.
   - Store what was changed (duration, power, reps) on CompletedWorkout.
   - Enables: Detect athletes who consistently shorten workouts (time-constrained) or reduce power (over-prescribed).

### Medium-complexity additions

These require new data structures and modest engine changes:

7. **Athlete response memory**
   - New struct: `AthleteResponseProfile` tracking how the athlete responds to each workout type.
   - Fields: avg feedback per type, avg RPE per type, typical recovery pattern, HR-power trends.
   - Updated incrementally after each workout.
   - Enables: Personalized prescription calibration.

8. **Progressive interval prescription**
   - Replace fixed quality templates (always 4x5 min @ 95-100% FTP) with parameterized intervals.
   - Parameters: reps, duration, intensity, rest duration, rest intensity.
   - Progression rules: If 4x5 @ 95% rated "easy" twice, progress to 4x6 or 3x8 or 4x5 @ 98%.
   - Requires: Interval progression state per energy system.

9. **Energy system targeting**
   - The `qualitySubtype` field already exists (vo2, threshold, muscularEndurance, tempo, overUnders).
   - Build workout templates for each subtype.
   - Track which energy systems have been trained recently and prioritize gaps.
   - Requires: Subtype-specific workout builders, energy system balance tracking.

10. **Multi-week load tracking**
    - Extend TrainingMemorySummary to 4-week and 8-week windows.
    - Compute chronic training load (CTL) and acute training load (ATL).
    - Use TSB (training stress balance) to inform readiness.
    - Requires: TSS computation (easy win #1) plus extended window calculations.

11. **Workout compliance tracking**
    - Compare prescribed workout (recommendation steps) against actual execution (completed ride metrics).
    - Score: Did the athlete hit target power? Complete all intervals? Finish the full duration?
    - Enables: Detect over-prescription (consistently cutting short) or under-prescription (always easy).

### Major architectural changes

12. **Training phase / block structure**
    - Introduce concept of mesocycles (2-4 week blocks with specific focus).
    - Base block → Build block → Peak block → Recovery block.
    - Each block adjusts the recommendation engine's willingness and template selection.
    - Requires: Phase state machine, phase transition logic, UI for phase awareness.

13. **Longitudinal adaptation model**
    - Replace static UserProfile with evolving `AthleteModel` that updates over time.
    - Auto-adjust: fitness state, quality willingness, FTP estimate, recovery capacity.
    - Requires: Bayesian or rolling-average model that updates incrementally.

14. **Constrained-athlete scheduling**
    - For athletes with predictable weekly patterns (e.g., "I can only train Mon/Wed/Fri/Sat"), optimize the sequence of workout types across available days.
    - Balance quality/endurance/recovery across the week given constraints.
    - Requires: Weekly planning layer above daily recommendation.

15. **Goal-driven periodization**
    - Connect training goals to specific workout prescriptions and timelines.
    - "I want to ride 100 miles in 8 weeks" generates a progressive plan.
    - Requires: Goal decomposition, timeline planning, progress tracking.

---

## 8. Proposed Adaptive Progression Architecture

### Conceptual model

The app should evolve from a **daily recommendation engine** to an **adaptive coaching memory system** built on three layers:

```
Layer 1: Athlete Model (slow-changing, weeks-to-months)
    Who is this athlete? How do they respond? What have they built?

Layer 2: Training Context (medium-changing, days-to-weeks)
    What phase are we in? What's the weekly shape? What's upcoming?

Layer 3: Daily Decision (fast-changing, same-day)
    Given today's check-in and current context, what's the right workout?
```

The current app only has Layer 3. Adding Layers 1 and 2 would enable true adaptive progression.

### Layer 1: Athlete Model

A persistent, incrementally-updated profile of the athlete's capacity and response patterns.

**Proposed structure:**

```
AthleteModel {
  // Capacity estimates (updated after each workout)
  estimatedFTP: Int                    // Auto-adjusted from performance data
  ftpConfidence: Float                 // How reliable the estimate is
  ftpHistory: [(date, value)]          // Track changes over time

  // Response patterns (rolling averages)
  recoveryRate: Float                  // How quickly legs go from Heavy to Fresh after quality
  qualityTolerance: Int                // Max quality sessions per week before tooMuch
  enduranceCeiling: TimeInterval       // Longest endurance session rated "right"
  typicalRecoveryDays: Int             // Days between quality sessions

  // Energy system development
  thresholdLevel: ProgressionLevel     // Current interval prescription parameters
  vo2Level: ProgressionLevel           // (if/when VO2 workouts are added)
  muscularEnduranceLevel: ProgressionLevel

  // Behavioral patterns
  avgSessionsPerWeek: Float            // Rolling 4-week average
  avgTimePerSession: TimeInterval      // Rolling average
  modificationFrequency: Float         // How often workouts are edited
  shorteningFrequency: Float           // How often duration is reduced
  feedbackDistribution: [Feedback: Int] // Calibration indicator
}

ProgressionLevel {
  currentReps: Int                     // e.g., 4
  currentDuration: TimeInterval        // e.g., 5 min
  currentIntensity: FTPPercentage      // e.g., 95%
  currentRestDuration: TimeInterval    // e.g., 3 min
  lastProgressedAt: Date
  consecutiveSuccesses: Int            // "right" or "easy" ratings in a row
  consecutiveStruggles: Int            // "hard" or "tooMuch" ratings
}
```

**Update rules:**
- After each completed workout, update response patterns using exponential moving average
- FTP estimate adjusted if interval power consistently exceeds targets with "easy" feedback
- Progression levels advance after 2+ consecutive "right" or "easy" sessions at current level
- Progression levels regress after 2+ "hard" or "tooMuch" at current level

### Layer 2: Training Context

A medium-term planning layer that provides week-level structure.

**Proposed structure:**

```
TrainingContext {
  // Load tracking
  chronicTrainingLoad: Float           // 42-day rolling avg TSS (CTL)
  acuteTrainingLoad: Float             // 7-day rolling avg TSS (ATL)
  trainingStressBalance: Float         // CTL - ATL (TSB)

  // Weekly shape
  weeklyBudget: WeeklyBudget           // Available sessions and time
  currentWeekPlan: [DaySlot]           // What's been done and what's coming
  energySystemBalance: EnergySystemBalance  // What's been trained recently

  // Phase (optional, for future)
  currentPhase: TrainingPhase?         // base / build / peak / recovery
  weeksInPhase: Int
  phaseObjective: String
}

WeeklyBudget {
  targetSessions: Int                  // From training frequency
  targetHours: Float                   // From typical availability
  qualityBudget: Int                   // Max quality sessions this week
  completedSessions: Int
  completedHours: Float
  qualityCompleted: Int
}

EnergySystemBalance {
  lastThresholdDate: Date?
  lastVO2Date: Date?
  lastMuscularEnduranceDate: Date?
  lastTempoDate: Date?
  prioritySystem: EnergySystem         // What needs work next
}
```

### Layer 3: Enhanced Daily Decision

The existing recommendation engine, enhanced with inputs from Layers 1 and 2:

**New inputs to chooseWorkoutType():**
- `athleteModel.qualityTolerance` replaces hard-coded "3 hard days" threshold
- `athleteModel.recoveryRate` adjusts how many easier sessions are needed before quality
- `trainingContext.trainingStressBalance` provides objective readiness signal
- `trainingContext.weeklyBudget.qualityBudget` limits quality per week
- `trainingContext.energySystemBalance.prioritySystem` selects quality subtype

**New inputs to buildWorkout():**
- `athleteModel.thresholdLevel` parameterizes interval prescription
- `athleteModel.enduranceCeiling` adjusts endurance duration targets
- `athleteModel.estimatedFTP` replaces static profile FTP

### Design principles

**Explainable logic:** Every progression decision should be traceable to specific signals. "We're progressing your threshold intervals from 4x5 to 4x6 because your last two sessions were rated 'right' with declining perceived effort."

**Structured memory:** Use typed data structures, not opaque embeddings or model weights. The athlete model should be inspectable and debuggable.

**Coach-like reasoning:** The system should reason the way a human coach would: "She's been consistently handling 4x5 threshold, her HR response is stable, and she rated them 'right' twice. Let's try 4x6." Not: "The gradient descent converged on a longer interval."

**Transparent heuristics:** Thresholds and progression rules should be documented constants, not learned parameters. This keeps the system predictable and trustworthy.

**Graceful degradation:** Athletes with little data should get the current conservative recommendations. Progressive features activate as data accumulates.

---

## 9. Coaching Examples

### Example 1: Athlete outgrowing 4x5 min threshold intervals

**Current state:** Athlete has completed 4x5 min @ 95-100% FTP three times in two weeks. Feedback: "right", "right", "easy". Perceived effort trending down (7, 6, 5). Average power stable at 98% FTP.

**Signals available today:**
- CompletedWorkout.workoutFeedback history: right, right, easy (persisted)
- CompletedWorkout.perceivedEffort history: 7, 6, 5 (persisted)
- CompletedWorkout.averagePower vs. FTP (persisted)
- Per-second power samples showing stable power across all reps (persisted but not analyzed)

**What the app does today:** Next quality recommendation will still be 4x5 min @ 95-100% FTP. The "easy" feedback enables quality sooner (easy boost), but the workout structure never changes.

**What adaptive progression would do:** Recognize 2+ "right" or "easy" at current level. Progress to 4x6 min @ 95-100% FTP (longer intervals, same intensity). Update `thresholdLevel.currentDuration` from 300s to 360s. Reason text: "Your threshold work has been landing well. Extending the intervals to build more time at intensity."

**Additional state needed:** `ProgressionLevel` struct tracking current parameters + consecutive success count.

### Example 2: Athlete repeatedly struggling with quality work

**Current state:** Last three quality sessions: "hard", "tooMuch", "hard". Perceived effort: 8, 9, 8. HR drift visible in samples (HR climbing 10+ bpm over same-power intervals).

**Signals available today:**
- Feedback pattern: hard, tooMuch, hard (persisted, hadTooMuchFeedback7d = true)
- Perceived effort: 8, 9, 8 (persisted but only used in intent builder)
- HR samples showing drift (persisted but not analyzed)

**What the app does today:** hadTooMuchFeedback7d suppresses quality. After 7 days without tooMuch, quality becomes available again at the same prescription.

**What adaptive progression would do:** Recognize pattern of struggle. Regress prescription: reduce from 4x5 to 3x4 min, or reduce intensity from 95-100% to 90-95% FTP. Update `thresholdLevel.consecutiveStruggles = 3`. Consider FTP may be overestimated. Reason text: "Recent sessions have been landing harder than intended. Dialing back the intervals to find your current sweet spot."

**Additional state needed:** `ProgressionLevel.consecutiveStruggles`, FTP confidence indicator, HR drift analysis.

### Example 3: Athlete adapting well to endurance volume

**Current state:** Over 4 weeks, athlete has completed: 5x 45min Zone 2, 3x 60min Zone 2. All rated "right" or "easy". HR-power ratio improving (lower HR for same power). No tooMuch feedback.

**Signals available today:**
- Workout type + duration history (persisted)
- Feedback consistently positive (persisted)
- HR and power samples showing improving efficiency (persisted but not analyzed)

**What the app does today:** Continues prescribing 45 or 60 min Zone 2 based on available time. No awareness of endurance progression.

**What adaptive progression would do:** Track `enduranceCeiling` increasing. Start prescribing slightly longer sessions when time allows ("You've been handling 60 min well - if you have 75 min, the extra time at Zone 2 builds more aerobic base"). Update weekly volume targets upward. Recognize aerobic fitness improvement from HR-power trends.

**Additional state needed:** `AthleteModel.enduranceCeiling`, rolling HR-power efficiency metric.

### Example 4: Athlete showing fatigue drift despite completion

**Current state:** Athlete completes all workouts but: per-second power shows declining power in later intervals (rep 1: avg 250W, rep 4: avg 230W). HR trending up throughout. Feedback is "right" but perceived effort is creeping up (5, 6, 7 over three sessions).

**Signals available today:**
- Per-second power and HR samples (persisted, not interval-segmented)
- Perceived effort trending up (persisted)
- Feedback "right" (persisted)

**What the app does today:** Sees "right" feedback, continues same prescription. The subtle fatigue trend is invisible because samples aren't interval-segmented and perceived effort isn't tracked longitudinally.

**What adaptive progression would do:** Interval segmentation reveals power decay across reps. RPE trend analysis shows increasing effort for same work. Two responses: (a) maintain current level longer before progressing (reset consecutiveSuccesses), (b) suggest a recovery-focused week. Reason text: "You're completing these well, but the effort is creeping up. A lighter week now protects your gains."

**Additional state needed:** Interval-level metrics, RPE trend tracking, concept of planned recovery weeks.

### Example 5: Athlete frequently shortening workouts due to time

**Current state:** Athlete reports 45 min available but frequently modifies workouts to 30 min. Over last 10 sessions, 6 were shortened via editor.

**Signals available today:**
- `editor.isModified` is checked but not persisted with the ride
- Time available reported in check-in (45 min) vs. actual duration (persisted in CompletedWorkout.duration)

**What the app does today:** Continues recommending 45-min workouts. User continues editing them down.

**What adaptive progression would do:** Track modification frequency and direction. Recognize pattern of time over-reporting. Adjust behavioral model: `AthleteModel.effectiveAvailability` < reported availability. Start building 30-min templates by default. Reason text: "We've noticed you often have less time than expected. Today's workout is built for 30 focused minutes."

**Additional state needed:** Modification history (what changed, how often), effective availability estimate.

---

## 10. Technical Inventory Appendix

### Key models

| Model | File | Lines | Purpose |
|-------|------|-------|---------|
| `UserProfile` | Models.swift | 57-67 | Static athlete profile (goals, equipment, FTP) |
| `CheckIn` | Models.swift | 75-116 | Daily pre-workout state assessment |
| `RecentActivity` | Models.swift | 69-73 | Non-cycling activity with timing/intensity |
| `WorkoutRecommendation` | Models.swift | 148-155 | Generated workout (type, steps, reason) |
| `WorkoutStep` | Models.swift | 140-146 | Recommendation step (role, modality, name, targets) |
| `WorkoutType` | Models.swift | 118-130 | recovery / endurance / quality enum |
| `WorkoutFeedback` | Models.swift | 157-180 | easy / right / hard / tooMuch enum |
| `WorkoutHistoryEntry` | Models.swift | 182-219 | Persisted workout record with embedded check-in |
| `CompletedWorkout` | CompletedWorkout.swift | 3-101 | Full ride data with samples, metrics, feedback, reflection |
| `TrainerMetrics` | TrainerTypes.swift | 44-51 | Per-second telemetry (power, HR, cadence, speed) |
| `TrainerWorkoutStep` | TrainerWorkoutTypes.swift | struct | Executable workout step (name, duration, targetPower, role, rampFromPower) |
| `TrainingMemorySummary` | TrainingMemorySummary.swift | 3-30 | 7/14/3-day aggregations |
| `ShortTermTrainingIntent` | ShortTermTrainingIntent.swift | 3-60 | 2-day coaching arc with intensity prescriptions |
| `UpcomingContextEvent` | UpcomingContext.swift | 136-212 | User-entered future event |
| `UpcomingContextSummary` | UpcomingContext.swift | 216-274 | Bucketed 7-day event summary |
| `PostWorkoutReflection` | CompletedWorkout.swift | 105-119 | AI-generated session evaluation + guidance |
| `WorkoutEditor.StepGroup` | WorkoutEditorView.swift | 8-19 | Editable workout step (grouped intervals) |
| `WorkoutEditEvaluation` | WorkoutEditEvaluator.swift | struct | Edit safety assessment |

### Key managers/services

| Service | File | Purpose |
|---------|------|---------|
| `AppState` | Models.swift (245-500) | Central @Observable state. Holds profile, check-in, recommendation, history. Orchestrates recommendation generation and persistence. |
| `RecommendationEngine` | RecommendationEngine.swift | Pure-function workout type selection, reason generation, and template building |
| `TrainerWorkoutRuntime` | TrainerWorkoutRuntime.swift | Workout execution state machine. Tick-based step progression, sample capture, ERG control. |
| `FTMSManager` | FTMSManager.swift | Bluetooth FTMS trainer connectivity. Scan, connect, parse metrics, send ERG commands. |
| `ERGRampController` | ERGRampController.swift | 8-second smoothstep between-step power transitions |
| `PowerSmoother` | PowerSmoother.swift | 3-second rolling power average for display |
| `CadenceGuidance` | CadenceGuidance.swift | Low-cadence warning detection (< 75 rpm for 3+ seconds) |
| `LocalStore` | LocalStore.swift | File-based persistence for workouts, rides, intents, context, sync metadata |
| `BackendAuthService` | BackendAuth.swift | Apple Sign-In, JWT management, account deletion |
| `BackendSyncService` | BackendSync.swift | Differential sync with backend (POST /v1/sync) |
| `AICoachService` | AICoachService.swift | Fetches AI explanation for daily recommendation |
| `PostWorkoutReflectionService` | PostWorkoutReflectionService.swift | Fetches AI post-workout reflection, builds training intent |
| `TrainingMemoryBuilder` | TrainingMemorySummary.swift | Aggregates 7/14/3-day training metrics from history |
| `TrainingIntentBuilder` | ShortTermTrainingIntent.swift | Creates 2-day coaching intent from reflection or feedback |
| `HealthKitManager` | HealthKitManager.swift | Live HR observation, workout save to Apple Health |
| `HRMManager` | HRMManager.swift | Standalone heart rate monitor BLE connectivity |
| `WorkoutConverter` | TrainerWorkoutTypes.swift | Converts recommendation steps to executable TrainerWorkoutSteps |
| `WorkoutEditEvaluator` | WorkoutEditEvaluator.swift | Assesses safety of user workout modifications |
| `CoachingNotificationManager` | CoachingNotificationManager.swift | Schedules 22h/46h post-workout coaching notifications |
| `SubscriptionService` | SubscriptionService.swift | StoreKit 2 entitlement management |
| `AnalyticsService` | AnalyticsService.swift | Event tracking (Mixpanel) |
| `SentryService` | SentryService.swift | Error logging |

### Recommendation engine entry points

| Entry Point | Location | Trigger |
|-------------|----------|---------|
| `AppState.submit(checkIn:)` | Models.swift:314 | User completes daily check-in |
| `AppState.refreshRecommendationIfCheckedIn()` | Models.swift:399-405 | Upcoming context added/edited/deleted |
| `AppState.generateRecommendation(for:)` | Models.swift:479-499 | Internal: assembles inputs, calls engine |
| `RecommendationEngine.recommend(for:)` | RecommendationEngine.swift:16-22 | Pure function: inputs -> recommendation |
| `RecommendationEngine.chooseWorkoutType(for:)` | RecommendationEngine.swift:87-229 | 8-gate decision tree |

### Runtime classes

| Class/Struct | File | Lifecycle |
|-------------|------|-----------|
| `TrainerWorkoutRuntime` | TrainerWorkoutRuntime.swift | Created per ride session, owns timer and samples |
| `FTMSManager` | FTMSManager.swift | Created per ride session, manages BLE connection |
| `ERGRampController` | ERGRampController.swift | Owned by runtime, manages between-step transitions |
| `PowerSmoother` | PowerSmoother.swift | Owned by runtime, 3-sec rolling buffer |
| `CadenceGuidance` | CadenceGuidance.swift | Owned by runtime, tracks low-cadence events |
| `WorkoutEditor` | WorkoutEditorView.swift | Created when user opens editor, owned by TodayView |

### Persistence layers

| Layer | Technology | Scope | Key Files |
|-------|-----------|-------|-----------|
| UserDefaults | Apple UserDefaults | Profile, check-in, onboarding flag | Models.swift (264-269) |
| Local file system | JSON files in App Support | Workouts, rides, intent, context, sync metadata | LocalStore.swift |
| HealthKit | Apple HealthKit | HR samples, workout records | HealthKitManager.swift |
| Backend API | REST (POST /v1/sync, /v1/auth) | Full data sync, auth | BackendSync.swift, BackendAuth.swift |
| Keychain | Apple Keychain Services | JWT, user ID | KeychainHelper.swift |

### HealthKit integration

**Written:**
- `HKWorkout` (cycling, indoor) with start/end dates
- `HKQuantitySample` (heartRate) per trainer HR reading with timestamps

**Read:**
- Live heart rate observation via `HKAnchoredObjectQueryDescriptor`
- Used as HR fallback when trainer/HRM don't provide HR

**Not integrated:**
- Sleep data (not read or written)
- HRV (not computed or stored)
- VO2max (not read from HealthKit)
- Active energy (not written)

### Strava integration

- OAuth connection via `StravaAuth`
- TCX file generation from ride samples via `TCXGenerator`
- Upload via `StravaUploader`
- Post status tracked on `CompletedWorkout.isPostedToStrava`
- Share card rendering via `StravaCardRenderer` / `StravaWorkoutCardView`
