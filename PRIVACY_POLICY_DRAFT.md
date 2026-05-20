# Privacy Policy for SmarterTraining

**Effective Date: May 20, 2026**

SmarterTraining is operated by **Smarter Foundry LLC** ("SmarterTraining," "we," "our," or "us"), a California limited liability company. This Privacy Policy explains how we collect, use, share, and protect your information when you use the SmarterTraining mobile application (the "App") and website (collectively, the "Service").

By using the Service, you agree to the practices described in this Privacy Policy.

---

## 1. Information We Collect

### a. Information You Provide

When you use the Service, you may provide:

- **Sign in with Apple credentials.** If you sign in, Apple sends us a unique Apple user identifier. You may also choose to share your name and email address; if you use Apple's Hide My Email relay, we receive only the relay address.
- **Email address** if you join our waitlist, contact us, or contact support.
- **Training profile.** Your fitness state, training goals, available training time, frequency, equipment, and (optionally) cycling FTP.
- **Daily check-ins.** Your overall feel, leg state, motivation, time available, contextual flags (such as poor sleep, getting sick, high stress), and any cross-sport activities you log.
- **Workouts you complete, skip, modify, or log.** Including title, duration, type, subtype, structure, and your feedback.
- **Coach Notes.** Persistent freeform context you write to help your coach adapt your training, plus optional tags.
- **Post-workout reflections.** Your responses to coach check-in prompts and any optional follow-up notes.
- **Upcoming context.** Future events you log (e.g., big rides, travel, recovery periods).
- **Subscription state.** We rely on Apple's StoreKit to manage your subscription. We see your entitlement status only; we never see or store your payment information.

### b. Health and Fitness Data

With your permission, the Service may access health and fitness data — such as workouts, heart rate, power, cadence, and activity history — from **Apple HealthKit**, connected **Bluetooth heart-rate monitors**, and **Bluetooth indoor trainers** (FTMS).

Specifically:

- **HealthKit reads:** heart-rate samples during workouts.
- **HealthKit writes:** completed workout sessions, so your fitness data stays in one place.
- **Bluetooth peripherals:** real-time power, cadence, and heart-rate values from your trainer and HRM during active workouts.

When you complete a workout, the recorded workout data — including heart rate, power, cadence, duration, and any feedback or reflection you provide — is transmitted to our backend so we can:

- Sync your training history across your devices,
- Generate adaptive coaching recommendations,
- Produce post-workout reflections and "likely tomorrow" guidance.

**HealthKit-sourced data is used solely to provide and improve the Service. We never use HealthKit data for advertising, never share it with advertisers, never sell it, and never share it with third parties for marketing purposes.**

You can revoke HealthKit access at any time in the Settings app on your device.

### c. Automatically Collected Information

When you use the App, we automatically collect:

- **Device information** (device model, operating system version, app version, locale).
- **Usage data** (which features you interact with, how often, and session-level metadata such as duration).
- **Diagnostic data** (crash reports, error logs, and performance traces).

Once you sign in with Apple, this information is associated with your Apple user identifier and is therefore linked to your identity. Before sign-in, this information is associated with a temporary pseudonymous identifier on your device.

### d. Information We Do NOT Collect

For clarity, we do **not** collect:

- Precise or coarse location data.
- Your contacts, photos, or microphone input.
- Advertising identifiers (IDFA).
- Browsing history outside the Service.
- Payment information (handled exclusively by Apple's StoreKit).

---

## 2. How We Use Your Information

We use your information to:

- Provide, operate, and maintain the Service.
- Generate adaptive workout recommendations and tier-aware progression.
- Adjust your plan based on your check-in, recent training load, recovery state, and Coach Notes.
- Produce post-workout reflections, "likely tomorrow" previews, and execution guidance.
- Personalize your coaching experience based on your goals, training approach, and history.
- Sync your data across your devices when you are signed in.
- Analyze usage to improve features, performance, and recommendation quality.
- Respond to feedback and support requests.
- Detect, prevent, or address security incidents, technical issues, and abuse.

Some recommendations and reflections are generated using **automated systems and algorithmic processing**, including large language models operated by third-party AI providers (see Section 3). You can request human review of, or object to, decisions that have significant effects on you — see Section 8.

---

## 3. Third-Party Service Providers

We use a small number of third-party processors to operate the Service. Each processor handles data on our behalf, under contract, only for the purpose of providing their function:

| Provider | Purpose | What they receive |
|---|---|---|
| **Apple** (Sign in with Apple, HealthKit, StoreKit, Push Notifications) | Identity, health data access, subscriptions, notifications | Apple user identifier; HealthKit access remains on your device |
| **Mixpanel, Inc.** | Product analytics | Pseudonymous (and, post-sign-in, identified) usage events and device metadata |
| **Sentry (Functional Software, Inc.)** | Crash and performance diagnostics | Crash logs, performance traces, and your Apple user identifier (after sign-in) |
| **OpenAI, L.L.C.** | AI generation of post-workout reflections and "why this" coaching explanations | Workout context (subtype, duration, recent feedback, memory summary); your Apple user identifier is forwarded as an opaque ID |
| **Strava, Inc.** | Optional workout sharing, only when you tap "Share to Strava" | Completed workout file (TCX) with HR, power, cadence; title; description |
| **Smarter Foundry LLC's own backend infrastructure** | Sync, AI orchestration, account management | All data you provide or generate in the App while signed in |

These providers operate in the **United States** and may store or process data in other jurisdictions where their infrastructure is hosted. Each operates under their own privacy policy. We choose providers that contractually commit to processing data only for our specified purposes.

When you tap **Share to Strava**, your workout data is transmitted directly to your own Strava account. Strava's handling of that data is governed by Strava's privacy policy.

---

## 4. AI Processing Notice

Some Service features rely on third-party AI providers (currently OpenAI) to generate personalized coaching content. When you complete a workout or check in, anonymized workout context — such as workout type, recent training history, your feedback, and (where relevant) free-form notes you have written — is sent to OpenAI to generate reflection and recommendation text. **OpenAI is contractually prohibited from training their models on this data and from using it for any purpose other than serving our API requests.**

We do not send your real name, email address, or contact information to OpenAI.

---

## 5. We Do Not Sell or Share Your Data for Advertising

SmarterTraining does **not** sell your personal information or your health and fitness data within the meaning of the California Consumer Privacy Act (CCPA / CPRA). We also do not share your data with advertisers, do not participate in cross-context behavioral advertising, and do not allow third-party advertising SDKs in the App.

---

## 6. Data Retention

We retain your data only as long as is necessary to:

- Provide the Service's functionality.
- Maintain your training history, preferences, and coaching continuity.
- Comply with legal obligations.
- Resolve disputes and enforce our agreements.

When you delete your account (see Section 8), we permanently delete or anonymize your data within 30 days, except where retention is required by law (such as tax records related to your subscription).

---

## 7. Data Security

We use reasonable safeguards to protect your information, including:

- **HTTPS / TLS** for all communications between the App and our backend.
- **Apple Keychain** for storing sensitive credentials such as Strava OAuth tokens.
- **Access controls** limiting which Smarter Foundry personnel can access systems holding your data.

No method of transmission or storage is completely secure, and we cannot guarantee absolute security.

---

## 8. Your Rights and Choices

### Everyone

- **Delete your account.** You can delete your account and all associated data at any time inside the App (Settings → Delete Account) or by emailing privacy@smartertraining.ai.
- **Revoke permissions.** You can revoke HealthKit, Bluetooth, and Notification permissions at any time in your device's Settings app.
- **Disconnect Strava.** You can disconnect Strava in the App at any time; this stops future uploads.

### California Residents (CCPA / CPRA)

You have the right to:

- **Know** what categories of personal information we collect, the sources, the purposes, and the third parties we share with.
- **Access** the specific pieces of personal information we hold about you.
- **Correct** inaccurate personal information.
- **Delete** your personal information.
- **Opt out of "sale" or "sharing"** — though, as noted, we do not sell or share for cross-context behavioral advertising.
- **Limit use of sensitive personal information.** Health and fitness data is sensitive personal information under CPRA; we only use it to provide the Service.
- **Non-discrimination** for exercising any of these rights.

To exercise any of these rights, email **privacy@smartertraining.ai**. We will verify your identity (typically by asking you to sign in to the App) and respond within 45 days.

### Residents of the EU, UK, EEA, and Switzerland (GDPR / UK GDPR)

You have the right to:

- **Access** the personal data we hold about you.
- **Rectification** of inaccurate personal data.
- **Erasure** ("right to be forgotten").
- **Restriction** of processing.
- **Data portability** — receive your data in a machine-readable format.
- **Object** to processing based on legitimate interests, including profiling.
- **Withdraw consent** for any processing based on your consent.
- **Lodge a complaint** with your local data protection authority.

The legal bases on which we process your data are:

- **Performance of a contract** (delivering the Service you signed up for).
- **Legitimate interests** (improving the Service, preventing abuse).
- **Consent** (HealthKit, Bluetooth access, marketing emails if applicable).
- **Legal obligation** (tax, regulatory).

To exercise any of these rights, email **privacy@smartertraining.ai**.

### International Data Transfers

Because our service providers operate in the United States, your data may be transferred outside your country. Where required by law (for example, for transfers from the EU), we rely on **Standard Contractual Clauses** or other approved transfer mechanisms.

---

## 9. Children's Privacy

The Service is not intended for children under the age of 13 (or under 16 in the EU/UK, where stricter consent rules apply). We do not knowingly collect personal information from children. If you believe a child has provided us with personal information, contact privacy@smartertraining.ai and we will delete it.

---

## 10. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. If we make material changes, we will:

- Update the **Effective Date** at the top of this page.
- Notify you in the App and/or by email (if you have provided one) at least 7 days before the changes take effect.

Continued use of the Service after changes take effect constitutes acceptance of the updated Privacy Policy.

---

## 11. Contact Us

**Email:** privacy@smartertraining.ai

**Company:** Smarter Foundry LLC

**Website:** smartertraining.ai

For California residents exercising CCPA rights, you may also designate an authorized agent in writing.

---

## 12. Health and Fitness Disclaimer

SmarterTraining provides informational training guidance, workout planning, and adaptive recommendations only. The Service is not a medical service and does not provide medical advice, diagnosis, or treatment.

You should consult a qualified healthcare professional before beginning or significantly changing any exercise program, particularly if you have any health conditions or concerns. Exercise carries inherent risks, and you participate in any recommended activity at your own risk.
