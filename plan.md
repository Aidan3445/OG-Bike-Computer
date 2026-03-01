# Watch GPX Nav App — 5-Week Build Plan

## North Star

> A rock-solid offline bike computer that feels like a 2008 Garmin — but built with modern tools.

No maps. No routing. No subscriptions. GPX in, turn prompts out.

---

## Week 1 — Foundation & File Pipeline ✅

### 1.1 — Project Setup ✅
- Xcode project with iOS + paired watchOS targets
- SwiftUI + Swift throughout
- Shared code group with both-target membership

### 1.2 — GPX Import (iPhone) ✅
- File importer with `.xml`/`.data` content types
- GPX parser handles `<trk>/<trkpt>` and `<rte>/<rtept>`
- Route model with distance, elevation gain/loss computed properties
- Route list with stats (distance, elevation, point count)

### 1.3 — Phone → Watch Transfer ✅
- WatchConnectivity via `transferFile` (not `transferUserInfo` — too small for route data)
- Watch receives and persists routes as JSON
- Watch reports route names back via `updateApplicationContext`
- Phone shows green checkmark for routes already on watch
- Overwrite confirmation when re-sending existing route
- Upload spinner with timeout, blocks concurrent uploads

### Bonus: Mobile Polish ✅
- Route rename (swipe right, local only)
- Connection status bar
- Launch sync via `receivedApplicationContext`

---

## Week 2 — Watch App Core + Workout Session ✅

### 2.1 — Workout Session + GPS ✅
- HealthKit authorization (cycling + running + walking + hiking)
- Location authorization
- `HKWorkoutSession` + `HKLiveWorkoutBuilder` for background execution
- `CLLocationManager` for live GPS
- GPS filtering (accuracy < 50m)
- `HKWorkoutRouteBuilder` records actual ride GPS for Fitness app route map

### 2.2 — Basic Metrics + Ride Recording ✅
- Heart rate + active calories from HealthKit
- Speed + distance from CLLocation updates
- Elapsed time with pause-aware accumulator
- All GPS points recorded for HealthKit route attachment + future Strava export

### 2.3 — Watch Navigation UI ✅
- Route list → Start Ride screen with activity type picker (Cycling, Running, Walking, Hiking)
- Activity type determines HK workout type + speed vs pace display
- Vertical paged TabView: Navigation → Metrics → Controls
- MetricRow component with large glanceable text
- Pause/Resume/End controls
- Sub-1-minute ride discard prompt
- `WorkoutManager` handles start/pause/resume/stop(save:)/discard

---

## Week 3 — Navigation Logic ✅

All navigation code lives in `Shared/` — testable on both platforms.

### 3.1 — Route Preprocessing ✅
- `RouteProcessor.process()` computes from raw Route:
  - Haversine distances between consecutive points
  - Cumulative distance at each point
  - Bearings between consecutive points
  - Turn detection (angle threshold ≥ 30°, minimum 50m spacing)
  - Bounding box for rendering
- Turn classification: slight/normal/sharp left/right, U-turn, straight
- `ProcessedRoute` + `ProcessedPoint` + `TurnPoint` models
- Preprocessing runs once on watch at ride start (~50-100ms, negligible battery)

### 3.2 — Position Matching ✅
- `NavigationTracker` receives live GPS and:
  - Finds nearest segment (windowed search ±50 points, full scan fallback)
  - Projects position onto segment via law of cosines for interpolated distance
  - Tracks cumulative distance along route
  - Computes distance remaining
- Off-route detection (>100m from nearest segment)
- Route completion detection (<50m from end)

### 3.3 — Turn Prompts ✅
- Two-stage alert system:
  - Warning at ~200m (gentle `.click` haptic)
  - Imminent at ~50m (directional haptic — `.directionDown` for left, `.directionUp` for right)
  - U-turn: `.failure` haptic
  - Route complete: `.success` haptic
- Alert deduplication (each turn fires each alert level once)
- Navigation page on watch:
  - Large turn arrow + distance countdown
  - Color coding: green (>200m) → yellow (200m) → red (50m)
  - Off-route warning state
  - Route complete state
  - Distance remaining footer

---

## Week 4 — Visualization + Battery

### 4.1 — Route Shape Rendering
- Use SwiftUI `Canvas` or `Path` to draw:
  - Full route as a polyline (transformed to screen coordinates)
  - Current position as a bright dot
  - Upcoming turn points as small markers
- Transform GPS coordinates to screen space:
  - Find bounding box of route
  - Scale/translate to fit watch screen
  - Rotate so current heading is "up" (optional, adds complexity)
- Keep it simple: white line on black background, green dot for position

**✓ Checkpoint:** See your route shape on watch with a moving dot as you ride.

---

### 4.2 — Off-Route Detection
- If nearest segment distance exceeds threshold (~100m):
  - Show "Off Route" warning
  - Stronger haptic alert
  - Optionally show bearing back to nearest route point
- If rider returns to route, resume normal navigation

**✓ Checkpoint:** Walk away from route → get off-route warning → walk back → resumes.

---

### 4.3 — Battery Optimization
- **Dynamic GPS frequency:**
  - Far from turn (>500m): reduce location updates (`desiredAccuracy = kCLLocationAccuracyHundredMeters`)
  - Near turn (<200m): full accuracy (`kCLLocationAccuracyBest`)
- **Wrist-down throttling:**
  - Detect wrist state via `WKExtension` / `WKApplicationDelegate` scene phases
  - When wrist down: skip UI updates entirely, only process location for navigation logic
  - When wrist up: resume full UI refresh
- **Efficient rendering:**
  - Don't redraw route shape every GPS update (only move the dot)
  - Throttle metric display updates to 1/sec max
  - No animations

**✓ Checkpoint:** Compare battery drain on a 1-hour ride with vs without optimizations.

---

### 4.4 — Auto-Pause
- If speed < 1 mph for 5+ seconds:
  - Pause elapsed timer
  - Reduce GPS frequency further
  - Show "Paused" indicator
- Resume when speed exceeds threshold
- Track moving time vs total time separately

**✓ Checkpoint:** Stop at a light → timer pauses → start riding → timer resumes.

---

## Week 5 — Polish & Ship

### 5.1 — Edge Cases & Robustness
- GPS drift smoothing (exponential moving average or Kalman-lite)
- Route completion detection + summary screen
- Handle watch running out of storage (route file size limits)
- Handle workout interruption (phone call, crash recovery)
- Test with various GPX files (different sources, formats, sizes)

---

### 5.2 — Workout Save + Strava Export

**HealthKit / Fitness app (automatic):**
- When you call `endWorkout()` on `HKWorkoutSession`, the `HKLiveWorkoutBuilder` automatically saves the workout to HealthKit — it appears in the Fitness app immediately
- To include the GPS route on the workout (so Fitness shows the map): attach the recorded locations as an `HKWorkoutRoute` via `HKWorkoutRouteBuilder`
  - Call `insertRouteData(_:)` with your recorded `CLLocation` array
  - Call `finishRoute()` after the workout ends
- This is what makes your ride show a route map in Fitness and on the workout summary

**Strava export (manual):**
- After ride ends, generate a GPX file from the recorded track points (lat, lon, elevation, timestamp)
- Transfer the GPX file from watch → iPhone via WatchConnectivity
- On iPhone, offer a "Share" / "Export to Strava" option:
  - Use `UIActivityViewController` to share the `.gpx` file
  - User can "Open in Strava" or upload via strava.com
- GPX export format is simple XML — you already know the structure from the import side, just write it in reverse
- Alternative: also generate a `.fit` file (Strava prefers FIT), but GPX is simpler to start and Strava accepts it fine

**✓ Checkpoint:** Finish a ride → workout appears in Fitness with route map → export GPX → upload to Strava and see the ride.

---

### 5.3 — UX Polish
- Make the navigation screen dead simple:
  - Massive turn arrow
  - Large distance-to-turn number
  - Minimal text
- Color coding:
  - Green = on route, no turn soon
  - Yellow = turn approaching
  - Red = off route
- End-of-ride summary:
  - Total distance, time, avg speed, elevation gain
  - Save workout to HealthKit

---

### 5.4 — iPhone App Polish
- Route management:
  - Delete routes
  - View route details (distance, elevation profile)
  - See which routes are on the watch
- Transfer status indicator
- **Ride history:** list completed rides transferred from watch
- **Export rides:** share GPX files for Strava upload via share sheet

---

### 5.5 — App Store Submission
- Add all required usage descriptions:
  - HealthKit: "Records cycling workouts and heart rate"
  - Location (Always): "Tracks position for turn-by-turn navigation during rides"
  - Motion (if used): "Detects auto-pause when stopped"
- App Store listing:
  - Be explicit: offline, GPX-based, no maps
  - Screenshots from real rides on real watch
- TestFlight beta first → fix any issues → submit

---

## Key Architecture Decisions

**Shared code is king.** GPX parsing, route processing, position matching, turn detection — all of this lives in `Shared/` and works identically on both platforms. The watch and phone are just thin UI layers on top.

**The workout session IS the app.** On watchOS, everything revolves around the active workout session. It's not a feature — it's the foundation that makes GPS, background execution, and HealthKit all work.

**Codable everything.** Routes transfer as JSON between phone and watch. Simple, debuggable, no custom serialization needed.

**No CoreData.** For a handful of route files, plain JSON in the documents directory is simpler and more debuggable. Don't over-engineer storage.

---

## Tech Stack Summary

| Layer | Technology |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI (both platforms) |
| GPS | CoreLocation |
| Health/Workout | HealthKit + HKWorkoutSession |
| File Transfer | WatchConnectivity |
| File Import | UIDocumentPickerViewController |
| Storage | JSON files in documents directory |
| Haptics | WKInterfaceDevice haptic API |
| Route Drawing | SwiftUI Canvas/Path |

---

## Risk Areas to Watch

1. **WatchConnectivity reliability** — file transfers can be slow/delayed. Test early and often on real hardware.
2. **Background GPS battery drain** — the dynamic frequency adjustment in Week 4 is critical for long rides.
3. **GPS accuracy on watch** — Apple Watch GPS is noisier than phone GPS. Your position matching needs to be forgiving.
4. **App review** — Apple is strict about HealthKit and location usage. Be precise in your privacy descriptions.
5. **GPX format variations** — different apps export slightly different GPX. Test with files from Strava, Komoot, RideWithGPS, etc.
