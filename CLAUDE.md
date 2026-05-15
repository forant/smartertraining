# SmarterTraining

## Core Product Identity

SmarterTraining is an adaptive training companion for people with real lives.

The product is designed for users who want to improve consistently without needing to behave like professional athletes. The goal is not maximal optimization. The goal is sustainable progress, reduced decision fatigue, and effective training that fits into adulthood.

Tagline:

> Training for people with real lives.

The app should feel like:
- calm
- competent
- adaptive
- encouraging
- intelligent
- low-friction
- trustworthy

The app should NOT feel like:
- a spreadsheet
- a punishment system
- an optimization cult
- a noisy social network
- a guilt machine
- a productivity dashboard

---

# Product Philosophy

SmarterTraining is not trying to maximize training volume.

It is trying to maximize:
- sustainable consistency
- confidence
- momentum
- long-term durability
- effective use of limited time
- trust in daily decisions

The product assumes users:
- have jobs
- have families
- get stressed
- get tired
- miss workouts
- play multiple sports
- have imperfect schedules
- sometimes need flexibility

This is not a rigid training-plan app.

The recommendation system should adapt to real life rather than forcing users to conform to an idealized schedule.

---

# Emotional Goals

## Before Starting a Workout

The target emotional state is:

> "Ok, let's go. I have a limited amount of time, but I'm going to make this as effective as possible."

This implies:
- minimal friction
- fast startup
- low cognitive load
- confidence in the recommendation
- clear explanation of why today's workout matters
- immediate clarity on duration and structure

The app should help users feel:
- focused
- efficient
- supported
- capable

NOT:
- overwhelmed
- guilty
- confused
- pressured

---

## After Finishing a Workout

The target emotional state is:

> "Nice, I got my workout in and I feel like I'm becoming a better version of me."

This is identity-oriented, not performance-obsessed.

The app should reinforce:
- consistency
- self-trust
- personal growth
- resilience
- sustainable momentum

The app should NOT reinforce:
- shame
- inadequacy
- obsessive optimization
- comparison culture
- burnout behavior

---

# Recommendation Philosophy

Recommendations should feel:
- context-aware
- realistic
- flexible
- trustworthy
- understandable

The system should account for:
- fatigue
- soreness
- motivation
- time availability
- stress
- poor sleep
- illness
- recent workouts
- real-world activity

Examples of real-world activity:
- tennis
- MTB rides
- strength training
- walking
- skiing
- hiking
- physically demanding life events

The recommendation engine should reason holistically rather than treating all exercise as interchangeable calorie expenditure.

A hard tennis match may materially affect recovery and workout selection.

A short walk probably should not.

---

# Temporal & Contextual Awareness

SmarterTraining should reason across time, not just within isolated daily sessions.

Recommendations should account for:
- what happened in recent days
- cumulative fatigue and intensity
- upcoming planned activities
- expected future training opportunities
- disruptions to routine
- recent consistency patterns
- how today's workout affects tomorrow and the rest of the week

The app should feel aware of continuity.

Examples:
- A hard tennis match yesterday may reduce the need for additional intensity today.
- A planned long ride tomorrow may shift today's recommendation toward freshness preservation.
- Missing several recent workouts may warrant rebuilding momentum gradually rather than forcing intensity.
- Completing a hard session today may intentionally reduce tomorrow's load.

The recommendation system should think in rolling windows, not isolated days.

The goal is not rigid adherence to a predefined plan.

The goal is intelligent adaptation over time.

Users should feel:
- guided
- understood
- supported
- strategically managed

NOT:
- micromanaged
- punished
- trapped by a calendar
- forced to "make up" missed sessions

The app should reinforce the idea that training is dynamic and responsive to life context.

---

# Coaching Philosophy

The app should behave more like a thoughtful coach than a rigid planner.

Good coaching language:
- "Recovery today supports a stronger weekend."
- "40 focused minutes was enough."
- "You adapted intelligently after a stressful week."
- "Consistency matters more than perfection."

Bad coaching language:
- "You missed a workout."
- "Below target."
- "Catch up."
- "Undertrained."
- "Broken streak."

The app should reward intelligent adaptation, not blind compliance.

---

# Gamification Philosophy

Gamification should be lightweight and emotionally intelligent.

The goal is:
- continuity
- momentum
- identity reinforcement
- motivation
- subtle delight

NOT:
- addiction loops
- engagement hacking
- shame mechanics
- aggressive streak systems
- artificial urgency

Possible good systems:
- momentum arcs
- seasonal progression
- consistency journeys
- adaptive achievements
- recovery-aware milestones
- "durability" framing
- subtle visual progression

The app should never punish users for having real lives.

---

# UX Principles

The product should prioritize:
- one clear next action
- minimal taps
- low visual noise
- fast interaction
- clarity over density
- confidence over complexity

Avoid:
- giant dashboards
- excessive metrics
- analytics overload
- cluttered navigation
- hidden state
- unnecessary configuration

Users should almost always know:
1. what today's recommendation is
2. why it was chosen
3. how long it will take
4. how to start immediately

---

# AI Philosophy

AI should augment the experience, not replace product structure.

Deterministic systems should remain responsible for:
- core safety rails
- workout structure
- fallback logic
- predictable behavior
- guardrails

AI layers may enhance:
- reasoning
- personalization
- explanation quality
- motivational framing
- pattern recognition
- adaptation nuance

Avoid:
- opaque recommendations
- hallucinated physiology claims
- fake precision
- overconfident advice

The app should remain interpretable and trustworthy.

---

# Architecture Principles

Prefer:
- deterministic business logic
- modular systems
- state-driven UI
- inspectable recommendation flows
- local-first behavior where possible
- platform-agnostic core logic

Avoid:
- unnecessary abstraction
- premature infrastructure complexity
- tightly coupling UI and business logic
- platform-specific assumptions in core systems

The app may eventually support:
- iOS
- iPadOS
- macOS
- Apple TV

Current development should avoid making future multiplatform support difficult, but should NOT prematurely optimize for all platforms immediately.

---

# Trainer Integration Philosophy

Trainer integration is core product infrastructure, not a side feature.

The app should eventually support:
- BLE FTMS trainer connectivity
- ERG workouts
- structured interval execution
- live metrics
- workout progression
- reliable reconnect behavior

The key product goal is:

> "Can the user complete today's workout entirely inside SmarterTraining without needing another app?"

Trainer execution should feel:
- reliable
- immediate
- calm
- low-friction

---

# Current Product Direction

Near-term MVP priorities:
- trainer integration
- lightweight gamification
- real-world activity integration
- backend infrastructure
- AI-enhanced recommendations
- Sign in with Apple
- subscriptions/paywall

The goal is not feature breadth.

The goal is building a highly coherent daily training companion that users genuinely prefer opening every day.

---

# Anti-Goals

SmarterTraining is NOT trying to become:
- a professional coaching platform
- a spreadsheet analytics system
- a generic social fitness app
- a hardcore optimization product
- a punishment-based habit tracker
- a virtual cycling metaverse
- a maximalist feature platform

The product should resist:
- feature creep
- dashboard bloat
- complexity inflation
- fake precision
- optimization theater

Simplicity is a feature.
Consistency is the product.
Trust is the moat.

---

# Current Implementation

## Key Features

- **Onboarding (8 steps):** Collects name, fitness state, goals, time availability, training frequency, equipment, and optional cycling FTP. Persisted to UserDefaults.
- **Daily Check-In (5 steps):** Asks overall feel, leg freshness, motivation, available time, and optional context flags (slept poorly, getting sick, high stress, etc.). Drives the recommendation.
- **Deterministic Recommendation Engine:** Pure function — takes profile + check-in + recent history, returns a single workout (recovery / endurance / quality). No AI or network calls yet. Designed to be swapped for AI-backed logic later.
- **Today View:** Shows the recommended workout (hero card with structured steps), a coach-style reason explaining *why*, optional extras based on equipment, a check-in summary, and a post-workout feedback prompt (easy / right / hard / too much).
- **Workout History:** In-memory rolling window of last 5 entries. Feedback from prior sessions feeds back into the next recommendation.

## Architecture

- **Single `@Observable AppState`** injected via `.environment()`. Holds profile, check-in, recommendation, history, and feedback. Persists check-in and profile to `UserDefaults`.
- **`RecommendationEngine`** is a standalone struct with no dependencies on AppState — takes explicit `Inputs` (profile, check-in, history) and returns a `WorkoutRecommendation`. Logic is layered: hard recovery overrides -> prior feedback signals -> history guardrails -> profile bias ("quality willingness") -> default to endurance.
- **Navigation flow** is state-driven in `ContentView`: splash -> onboarding (if needed) -> check-in (if not done today) -> TodayView.
- **No Combine, no async networking, no Core Data.** Everything is local and synchronous.
- **Reusable UI components:** `CheckInCard`, `OnboardingCard`, `OptionGrid`, `OptionButton`, `ContextChip`, `FlowLayout` (custom Layout for wrapping chips), `OnboardingPill`.

## Data Model Highlights

- `WorkoutType`: `.recovery`, `.endurance`, `.quality`
- `WorkoutStep`: role (warmup/primary/cooldown/accessory) + modality (cycling/strength/mobility/recovery)
- `WorkoutFeedback`: `.easy`, `.right`, `.hard`, `.tooMuch` — last session's feedback is a first-class input to the next recommendation
- `CheckInPresentationContext`: adjusts check-in UI copy based on whether it's a regular check-in, plan update, or return after absence

## Current State

- Pre-AI: recommendation engine is rule-based, explicitly structured to be replaceable
- History is in-memory only (not persisted across launches beyond the latest check-in)
- Debug controls are present in TodayView for seeding history, resetting state, and clearing onboarding
