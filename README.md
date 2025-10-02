# Step Counter Sensor App — README

This document explains how to set up, run, and verify the Step Counter Sensor App (Flutter + Firebase). It also describes the data model, local caching, cloud sync, permissions, required Firestore index, and common troubleshooting. Everything here is ready to paste as a single README on GitHub.

## App Demo Pictures
<img src="https://github.com/user-attachments/assets/9023ee8c-2299-4f8e-9a0c-628904d70742" width="300" height="1000" />
<img src="https://github.com/user-attachments/assets/2e4ff3bf-9d91-4aa1-88a6-9d55a0404dcf" width="300" height="1000" />
<img src="https://github.com/user-attachments/assets/9bb33d91-f027-4659-9f29-80e01e61dc72" width="300" height="1000" />
<img src="https://github.com/user-attachments/assets/5c949504-9815-4fd1-a06e-89bac6571f7a" width="300" height="1000" />
<img src="https://github.com/user-attachments/assets/b292f3b9-32f7-4b9b-8e7d-2cb9e6337adc" width="300" height="1000" />




## Overview

* A Flutter mobile app that reads device step counter events, batches them every few seconds, stores them locally for resilience, and syncs to Firebase Cloud Firestore.
* Built for Phase 1 (mobile app, sensor access, local storage) and Phase 2 (cloud database, schema, backend rules/index).
* Tech stack: Flutter, Firebase Authentication, Cloud Firestore, SQLite (sqflite), Provider state management, pedometer plugin, SharedPreferences for lightweight session history.

## Key Features

* Continuous or periodic step data acquisition via device step counter sensor.
* Local caching with SQLite so data isn’t lost during network issues.
* Cloud sync to Firestore in small batches every 5 seconds or when batch fills.
* Authenticated user scope: each user sees and uploads only their own data.
* History and analytics screen: daily totals, week/month/all-time stats, last-7-days bar chart.
* Graceful handling of sensor resets and spike clamping.

## Architecture Summary

* Presentation: Flutter UI (Login, Signup, Home, History).
* State: StepProvider orchestrates sensor events, batching, and sync timing.
* Local storage: SQLite database file steps.db, table step_events (columns: id, user_id, ts, steps, synced).
* Cloud storage: Firestore collection steps (fields: userId, ts, steps, deviceId).
* Authentication: Firebase Email/Password.
* Sync strategy: write to SQLite first for durability, then push to Firestore; mark rows as synced on success; replay any unsynced rows later.

## Data Model

* Firestore collection: steps

  * userId: string (Firebase uid of the authenticated user)
  * ts: integer (epoch milliseconds timestamp when steps were recorded)
  * steps: integer (delta steps counted for that small time slice)
  * deviceId: string (UUID used to identify the device/session origin)
* SQLite table: step_events

  * id: INTEGER PRIMARY KEY AUTOINCREMENT
  * user_id: TEXT
  * ts: INTEGER (epoch milliseconds)
  * steps: INTEGER
  * synced: INTEGER (0 or 1)
* Statistics are computed client-side from these records:

  * Today, Week, Month, All Time total steps
  * Daily average across last 7 days
  * Last-7-days bar chart for visualization

## Prerequisites

* Flutter SDK installed and on PATH (Flutter 3.x recommended).
* Dart SDK bundled with Flutter.
* Android Studio or Xcode (for building Android/iOS).
* Node.js only if you prefer Firebase CLI for project initialization; otherwise you can use Firebase Console.
* A Firebase project with Authentication and Firestore enabled (free tier is fine).
* A physical Android device recommended for accurate step sensor testing; emulators generally do not emit real step counts.

## Quick Start — High-Level

* Create a Firebase project and enable Authentication (Email/Password) and Firestore (Native mode).
* Add iOS and/or Android apps to the Firebase project and download the config files into your Flutter app (google-services.json for Android, GoogleService-Info.plist for iOS).
* Ensure required permissions are set (Android ACTIVITY_RECOGNITION, iOS NSMotionUsageDescription).
* Configure Firestore security rules (scoped to userId) and create the composite index on steps.
* Get dependencies and run the app; sign up, grant permissions, start counting, verify sync, and view history.

## Detailed Setup — Firebase

* Create Firebase project:

  * In Firebase Console, click Add project and give it a name.
  * Enable Authentication → Sign-in method → Email/Password → Enable.
  * Enable Cloud Firestore → Start in production or test mode (test mode only for development) → Database location close to your users.
* Add Android app:

  * Register package name (e.g., com.example.steps_counter_sensor_app).
  * Download google-services.json and place it under android/app/.
  * In Android build.gradle files, ensure Google services plugin is applied as per Firebase Android setup guide.
* Add iOS app (if building for iOS):

  * Register bundle identifier (matches your Runner target).
  * Download GoogleService-Info.plist and place it under ios/Runner/.
  * In Xcode, ensure the plist is in the target and add NSMotionUsageDescription in Info.plist.

## Detailed Setup — Firestore Rules (development-safe and user-scoped)

* Set rules so an authenticated user can read/write only documents where userId matches their uid.
* In Firestore Rules editor, use a user-scoped rule for collection steps.
* After development, review and tighten rules if needed (e.g., validate numeric ranges, ts bounds).

## Required Composite Index

* Because the app queries steps by userId and a timestamp range ordered by ts, you must create a composite index.
* In Firebase Console → Firestore Database → Indexes → Composite → Add Index:

  * Collection: steps
  * Fields: userId Ascending, ts Descending
* Save and wait for the index to build before testing date-range queries in History.

## Android Configuration

* Android permissions required:

  * ACTIVITY_RECOGNITION permission for Android 10+ to access step counter.
  * Optional step counter/detector features declared with required="false".
* Battery optimizations:

  * Some OEMs kill background processes aggressively; ask users to exclude the app from battery optimization for best reliability while counting.

## iOS Configuration

* Add NSMotionUsageDescription to Info.plist to access motion and fitness data.
* Test on a physical iPhone for accurate step readings; simulators won’t generate step events.

## Running the App (typical flow)

* Ensure Flutter is set up and device/emulator is connected.
* From the project root:

  * flutter pub get
  * flutter run
* On first launch:

  * Create an account via Sign Up (email + password).
  * Log in and land on Home.
  * When prompted, grant Activity Recognition permission (Android) or accept Motion permissions (iOS).
  * Tap Start to begin a session. Walk with the device or tap Simulate for test increments.
  * Wait a few seconds to allow the periodic sync (default ~5s) to run.
  * Open the History screen to view Overview totals and the Chart for the last 7 days.

## How It Works Internally

* StepProvider listens to Pedometer.stepCountStream and derives delta steps from the cumulative counter.
* Deltas are accumulated and periodically batched:

  * Auto-save to local SQLite for durability.
  * Push to Firestore in batches (safe chunks below 500 writes).
  * On success, mark local rows as synced and prune old local rows.
  * On offline or sync failure, data remains locally and is replayed on next success.
* History screen:

  * Queries Firestore by userId with a ts range, requires composite index.
  * Aggregates daily totals between selected startDate and endDate.
  * Computes today/week/month/all-time counts plus last-7-days daily average.
  * Renders a bar chart for the last 7 days.

## Validation Checklist (do these to confirm setup)

* Authentication:

  * Sign up and log in without errors; current user uid appears behind the scenes as userId in Firestore docs.
* Permissions:

  * App asked for Activity Recognition (Android) or Motion usage (iOS) and you granted it.
* Local cache:

  * Start a session, then go offline, walk or simulate steps, then go back online; data should sync once connectivity returns.
* Firestore:

  * In collection steps, documents appear with fields userId, ts (epoch ms), steps (int), deviceId (string).
  * Index status: Index exists and queries do not throw FAILED_PRECONDITION.
* History:

  * Overview totals change after you walk/simulate.
  * Chart shows last-7-days bars with human-readable weekday labels.

## Troubleshooting

* PERMISSION_DENIED:

  * Ensure you are authenticated.
  * Verify Firestore rules allow read/write where request.auth.uid equals userId field being written.
  * Confirm your client writes userId to each steps document.
* FAILED_PRECONDITION: The query requires an index:

  * Create the composite index on collection steps with fields userId Ascending and ts Descending.
  * Wait for Firestore to finish building the index.
* No steps counted:

  * Real devices: some Android phones lack hardware step counter; most modern ones have it.
  * Ensure ACTIVITY_RECOGNITION permission is granted.
  * Some devices pause sensor dispatch under battery saver; disable battery optimization for the app.
  * Emulators typically do not emit step data; use Simulate or test on a physical device.
* Sync not happening:

  * Check internet connectivity.
  * Confirm Firebase initialization succeeded (Firebase.initializeApp runs before app builds).
  * Check that data is being batched (pending count increases) and that timer-based sync triggers every few seconds.
* History empty or incomplete:

  * Verify your time range covers today; History by default queries the last 7 days.
  * Confirm ts is stored as epoch milliseconds and that device time is correct.
  * Ensure composite index exists and has finished building.

## Security and Privacy Notes

* Rules restrict users to their own documents by matching request.auth.uid and userId field.
* Do not ship development rules that grant wide-open access; confirm auth gating before production.
* Step data is sensitive health-related behavioral information; disclose usage and retention in your app privacy policy.
* Consider data retention:

  * Optionally schedule deletion of records older than a chosen time window or implement a user setting for retention.

## Performance Guidelines

* Batch writes to Firestore to reduce cost and improve reliability.
* Keep batch size under Firestore limits (this app uses conservative chunk sizes).
* Use epoch milliseconds for ts to enable range queries and proper indexing.
* Prune local SQLite rows periodically to keep the device database small.

## What To Include In Your GitHub Repo

* Source code for the Flutter app.
* Android google-services.json and iOS GoogleService-Info.plist are typically excluded from public repos; use environment or private config if open-sourcing.
* This README file.
* A brief screenshot or gif of History and Home screens (optional).

## Phase Mapping To Requirements

* Phase 1: Mobile application development

  * Step counter data acquisition: Listening to device pedometer and computing deltas.
  * Local storage: SQLite table step_events stores all batches, marked synced after cloud success.
  * Data transmission: Periodic batch sync to Firestore in JSON-like map format.
* Phase 2: Cloud database and backend

  * Cloud database selection: Firebase Cloud Firestore with Authentication.
  * Database schema: Collection steps with fields userId, ts, steps, deviceId; composite index userId+ts.
  * Security: Firestore rules enforce user-level access.
  * Analytics: Client-side aggregation for daily, weekly, monthly, all-time, and last-7-days chart.

## Final Test Script (manual)

* Launch app → Sign Up → Log in.
* Home → Grant permission → Tap Start.
* Walk at least 20–30 steps or press Simulate several times.
* Wait 5–10 seconds for auto-sync.
* Open Firebase Console → Firestore → steps; verify new docs with your uid.
* Open History → Overview and Chart; verify counts and bars updated.
* Toggle airplane mode, add more steps, then disable airplane mode; verify that previously unsynced steps appear shortly after.

## Credits

* Flutter, Firebase, pedometer, sqflite, provider, intl, fl_chart.
* Built by adapting standard Flutter + Firebase patterns with an offline-first approach for sensor data.
