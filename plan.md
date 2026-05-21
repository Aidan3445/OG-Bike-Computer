# Computa Backlog

---

## 🆕 In Flight (added 2026-05-12)

- [ ] **Repeat critical alerts until the phone acknowledges receipt.** `audioSpeak` now flags `.immediateTurn` and `.navEvent` priorities as critical. On timeout (no `speechDone` ack within estimate + 1.5s), instead of falling back to local watch speech, the watch resends with a fresh UUID. Budget is 3 retries (~3 × (estimate + 1.5s)) before giving up and falling back to local. Non-critical priorities (stats, auto-pause) still fall back to local on first timeout. Implemented via a per-alert `inFlightText/Category/IsCritical/RetriesLeft` set + `sendInFlightToPhone(wm:)`. `clearInFlight()` centralizes reset.

- [ ] **Check if turn alerts are still relevant before delivery.** Added `relevanceCheck: (() -> Bool)?` to `VoiceAlert`. `processQueue` invokes it at dequeue time and silently skips stale alerts. Wired closures on:
  - Off-route → drops if `navigation.isOffRoute == false` by speak time.
  - Back-on-route → drops if we've gone off-route again.
  - Turn-approach (both entry points) → drops if `currentTurnIndex` has moved past the alert's turn index.
  - At-turn (immediate) → same — better to miss the announce than say "turn left" 5s after the rider already passed the turn (off-route flow catches missed turns).

- [ ] **Splits still not reading all selected stats; sometimes delivered late and read current state rather than the split/halfway snapshot.**
  1. Picker (`SplitMetricPickerView`) was already filtered to round-trippable metrics. Added `voiceReadableMetrics` set in `NavigationAlertPreferences.swift` and made `SplitAlertPreferences.init(from:)` strip any metric outside that set on decode — old saved configs with `.powerEstimate` / `.grade` are cleaned up automatically.
  2. Verified text is built *at trigger time* from `SplitStats` snapshots, not at speak time, so queue delays don't bleed current state into split or halfway readouts.

- [ ] **Add a setting for alert connection checks; default on.** *Deferred — needs spec.* The retry-until-ack work covers the practical case (failed sends recover instead of going silent). If you still want an explicit liveness pre-check toggle, want me to model it as: pre-ping the phone before each non-critical alert and skip the mirror leg if no pong within ~500ms?

- [ ] **Auto-pause/resume audio is reliable but turn alerts sometimes play on the watch speaker instead of the connected (phone-paired) headphones.** Addressed by the retry-until-ack change above — critical (turn / off-route) alerts no longer fall back to local on the first timeout, so the audio stays on the phone session (where the BT headphones are bound). Local fallback only fires after the retry budget is exhausted *or* if the mirror leg is genuinely unreachable.

- **Hold ride system still inconsistent.** *Deferred — substantial.* The three sub-issues (Save-doesn't-transfer, phone-actions-don't-mirror-to-watch, Fitness-app-missing-location) interact with HKWorkoutSession lifecycle, WC file transfer, and the held-ride state machine. Wants a dedicated session.

- [ ] **Watch turn-distance readout should step down through tenths → feet.** `formatTurnDistance` in `Shared/Utils/Formatting.swift` now steps `≥1 mi → "X.X mi"`, `≥0.1 mi → tenths ("0.7 mi", "0.3 mi")`, `<0.1 mi → feet rounded to 50`. Same rungs for km/m. Uses digit forms throughout — dropped the `½`/`¼` unicode glyphs since they rendered too small on the watch.

---

## 🐛 Bug Fixes

- **All ride alerts (turns, auto-pause, etc.) stop firing on longer rides (~45+ miles).** This affects all alert types — turn cues stop completely, and auto-pause fires inconsistently. The root cause is unknown but may be related to too many cue points loaded simultaneously, similar to the Logan route issue.

- [ ] **Alert queue not clearing correctly; alerts delivering out of order and delayed.** Reworked the watch↔phone speech mirror to be ack-driven: phone sends `speechDone` with the alert id when its synthesizer's `didFinish` fires, watch advances queue on real completion. Per-alert timeout (`estimate + 1.5s`) falls back to local watch speech if the phone fails silently. Phone drops `speech` messages older than 3s to avoid double-audio after fallback. Removed `synthesizer.stopSpeaking(at: .word)` on the phone (was the source of the "interrupt itself" bug). Audio routing now follows headphones-on-watch → phone-mirror → watch-speaker, with a user override (`Auto`/`Watch`/`Phone`) added to the Alerts settings page. Decision *not* to preempt — alerts always finish; queue is FIFO with priority. Settings page renamed "Navigation Alerts" → "Alerts".
  - [ ] **Enhancement — Evaluate TTS library to improve voice alert quality.** Added `Shared/Utils/PreferredVoice.swift` — a fallback chain that prefers Apple Premium voices (Ava, Evan, Zoe, Joelle, Allison), then Enhanced, then the system default. Both `PhoneSpeechPlayer` and `VoiceNavigator.speakLocally` use it. Premium voices must be installed by the user via Settings → Accessibility → Spoken Content → Voices; settings footer surfaces this hint. Decided against a third-party SDK — none solved the watch↔phone bridge consistency, and Apple's neural voices are a clear quality jump on-device.

- **Auto-pause sometimes locks in paused state and never resumes.** Two failure modes:
  1. Auto-pause triggers at ride start before movement begins — once the rider starts moving it never clears.
  2. Mid-ride auto-pauses sometimes also fail to auto-resume when movement resumes.
  - Also: auto-pause occasionally triggers when the rider is above the auto-pause speed threshold, after which the ride never auto-resumes — manual intervention required on phone or watch. Audit the speed comparison logic and fix the threshold check.
  - **Enhancement — Add periodic "did you mean to resume?" check after auto-pause.** After an auto-pause, if the rider hasn't resumed after a set interval, send a tiered alert: first alert as a notification prompting "Would you like to resume?", escalating to a full-screen notification if still not resumed after a second interval. Check frequency and enable/disable should be configurable in settings.

- **End and save from the held ride map/detail screen is broken on both phone and watch.** Tapping end & save from this screen has no effect on phone. On watch it is sometimes also broken.

- **Resuming a held ride should restore the route that was active when the ride was put on hold.** Currently the phone resumes using the route selected at the start of the ride rather than the one active at hold time.

- [ ] **Split stat alerts have incorrect numbering and timing after a hold.** Verified the existing held-ride continuation path in `WorkoutManager.startWorkout` already computes `currentSplitNumber = Int(totalDistance / splitDist)` and seeds `lastSplitDistance` from there, so resuming at 12 mi with 5 mi splits gives split 3 at 15 mi (3 mi post-resume) and split 4 at 20 mi (5 mi later). Marking implemented-untested for ride confirmation.

- [ ] **Split stat audio readouts should clarify whether a stat covers the full ride or only the current split.** First halfway stat now reads as "first half X" (e.g. "first half average speed 14 mph"); subsequent halfway stats drop the prefix. Split readouts unchanged: split-scope stats are bare ("time 18 minutes"), ride-scope stats are prefixed ("ride distance 12 miles"). End-of-route readout doesn't yet exist (separate Advanced item).

- [ ] **Not all stat readouts firing at split or halfway point.** `SplitStats` extended with `elapsedTime`, `elevationGain`, `elevationLoss`, `calories`, and `maxHeartRate` (previously only carried 5 fields). `WorkoutManager` now tracks per-split deltas for these and `currentRideStats()` populates them. `VoiceNavigator.statText` handles all the new metrics with `formatVoiceElevation`. The picker (`SplitMetricPickerView`) was filtering down to metrics that round-trip — removed `.heartRate` (use `.averageHeartRate`), `.powerEstimate`, and `.grade` since the watch doesn't snapshot those per-split. Old saved configs with `.heartRate` still work as an alias for average HR.

- **Route deletion from watch/phone not working correctly.** Two distinct issues:
  1. [ ] **Routes are always deleted from the phone regardless of which target is selected.** Fixed: `ClearRoutesSheet.onConfirm` previously had signature `(Bool) -> Void` (watch-only flag); the phone delete was unconditional. Changed to `(Bool, Bool) -> Void` for `(deletePhone, deleteWatch)` and gated each call site on its respective flag. Dialog body text now also reflects the selection ("phone", "watch", or "phone and your Apple Watch") instead of always saying "phone".
  2. Routes are only deleted from the watch when there is an active connection — deletions don't persist if the watch app is backgrounded.
  - **Related — Action queuing system needed for watch when backgrounded.** Phone-initiated actions (delete, sync, etc.) need a reliable queue that executes when the watch app comes back to the foreground. This is a broader architectural issue that affects other features.

- **The elevation panel expansion height should be fully coupled to the stat panel tab.** Currently a rider can end up with an expanded stat view and a clipped/cut-off elevation map at the same time.

- [ ] **Import route screen should not automatically dismiss or navigate back after an import completes.** Each pending route now resolves into a per-row state (`Saved to Phone`, `Sent to Watch`, `Sent — Ride Started on Watch`, `Switched to This Route`, or a failure label). The sheet stays open after each action; only the toolbar "Done" dismisses. Failure path uses the actual `Result<Void, Error>` returned by `sendRoute`.

- [ ] **Scrub on elevation/metric charts in route and ride detail can swallow swipe-back gesture.** `LongPressScrubOverlay.Coordinator` in `OG Bike Computer/Views/RideCharts.swift` now implements `gestureRecognizer(_:shouldReceive:)` and rejects any touch starting within 40pt of the leading edge, so the system back-swipe wins the leading strip and scrub still arms anywhere else on the chart.

- **POIs / waypoints on the ride detail map.** Route detail and watch maps already render POIs from the route, but the recorded ride doesn't carry the source route's POIs forward. To show them in `RideDetailView`, snapshot the active route's POIs onto the `RideSummary` at ride completion (touches all `RideSummary(...)` call sites in `WorkoutManager`), then render the same `WaypointPin` annotations.
  - Note: this is distinct from the waypoints-not-appearing bug (below) and from the full POI feature work (in Essential New Features). This specifically covers carrying POIs through to recorded ride detail.

- **Waypoints / POIs not appearing on map during a ride.** POIs associated with a route are not rendering on the map view. Verify that waypoint data is being correctly fetched, parsed, and passed to the map layer during route load.

- [x] **Add safe area padding to the free ride watch UI.** Content currently renders outside the safe area on the watch screen.

- [ ] **Changing routes causes the selected tab on the main watch view to change unexpectedly.** `WorkoutView`'s `onChange(of: hasRoute)` now also gates on `!workout.isActive` — the auto-jump-to-map only fires for fresh route loads before a ride starts. Mid-ride route swaps no longer steal the rider's current tab.

- [x] **The full-route toggle button on the watch ride map screen sometimes obscures the route in the upper-right corner.** Fix in two parts: After switching to the full-route view, briefly animate the toggle button to invisible, hold for a moment, then animate it back. The button may remain tappable while invisible, or be removed during the fade — whichever is simpler to implement.

- **Add +/– zoom controls that zoom toward the part of the route closest to the rider.** At maximum zoom in, the rider's location should be centered, at maximum zoom out, we should see the default full map zoom that is the current behavior. Zoom levels do not need to be user-configurable.
- [x] **The halfway alert fires immediately if the ride is started at or past the halfway point.** The alert should only fire when the rider actually crosses the halfway waypoint during the ride. It should not fire if the rider starts past that point, joins the route mid-ride past halfway, or is off-route when the waypoint would have been passed. Currently it triggers immediately with zeroed-out stats.

- [ ] **Ensure half way alert runs stats on exactly half of the route.** Confirmed `announceHalfway` snapshots stats with `wm.currentRideStats()` at the moment `distanceAlongRoute` first crosses half — the resulting text strings are built and queued at trigger time, so even if the queue holds the alert for several seconds before speaking, the spoken values reflect the halfway-crossing snapshot, not current state.

- [x] **Riders are occasionally flagged as off-route while still on the route.** When the app recovers and announces "back on route," it incorrectly fires a turn cue that is not relevant to the current position.

- **Fix heading/compass direction.** The heading indicator does not accurately reflect the rider's current direction of travel. 

- [ ] **Off-route view on watch should still display the metrics that the map screen normally shows.** `statsOverlay` in `RouteMapView.swift` previously branched into an off-route-only block that hid the primary/secondary stats. It now renders a single VStack: when off-route it prepends an "OFF ROUTE" header + nearest-route distance and a divider, then falls through to the normal primary/turn-info/secondary stat rendering. Container tints red when off-route.

- [x] **Full-route toggle button and +/– zoom buttons should work in the Map Screen settings demo/preview.** Currently they're inert in the preview; they should behave the same as on the live watch screen so the user can verify behavior from settings.

- [ ] **Held ride not dismissed after discard (phone).** `RideDetailView` now grabs `@Environment(\.dismiss)` and calls it from the discard confirmation dialog so the detail screen pops back to the parent list once the held ride is gone.

- **Watch map screen glitches on load — route line briefly fills entire screen.** Fix with one of two approaches:
  - Option A: Show only the current location dot on a black background until the route has fully rendered, then display it.
  - Option B: Hold (cache) the previous screen and swap it out atomically once the new map is ready.

- **Turn notifications occasionally not firing.** Turn-by-turn alerts are intermittently missed. Investigate alert queue delivery to ensure no alerts are silently dropped, especially when the watch app is backgrounded or transitioning states.

- [ ] **Grade overlay on watch elevation screen non-functional.** The toggle was wired to a `showGrade: Bool` config but the chart never read it. Now when enabled, the chart renders a per-segment colored band along the bottom of the elevation chart with grade tiers (blue ≤ -3% descent, green flat/mild, yellow moderate, orange steep, red very steep). Computed at render time from consecutive `ElevationSample` pairs — no model changes needed.

- [ ] **"Full route vs. ahead" toggle on elevation tab not persisting as default.** Watch's `ElevationProfileView` was guarding the default-tab apply with a one-shot `initializedDefaultTab` flag, so changing the setting after first appearance had no effect. Removed the guard so the default re-applies on every appearance, and added an `onChange(of: defaultTab)` handler so changing the setting while the screen is visible updates the mode live.

- [ ] **Time readouts only showing minutes; should show hours.** Voice formatter (`formatVoiceDuration`) now emits "1 hour 32 minutes" for durations ≥ 60 min instead of "92 minutes". Existing UI formatters (`formatTime`, `RideSummaryView.formatTime`, widget `formatDuration`) already handled hours — only the spoken path was missing it.

- **Some alerts need to be repeated until the phone acknowledges receipt — off-route and immediate-turn especially.** If the phone ack is lost or the message never reaches the phone, the rider can miss the alert entirely. Implement a retry-with-backoff for high-priority categories (e.g. 3 attempts at ~1s intervals, scoped to `.immediateTurn` and `.navEvent`). May require extending the ack protocol with explicit "received" vs "spoken" states.

- **Turn alerts should re-check relevance before delivery.** Alerts can queue up and play seconds after they were generated. By the time speech actually starts, the rider may have passed the turn, gone off-route, or be facing a different direction. At dequeue time (just before `audioSpeak`), verify the alert is still relevant given the rider's current state — skip if not.

- **Split stat alerts still aren't reading all selected stats; sometimes delivered late and reading current-state values rather than the snapshot at the split/halfway mark.** Even after the recent `SplitStats` extensions and per-split tracking, the rider reports gaps. Audit the announce-time snapshot to ensure every selected metric is present and the readout text is built at trigger time, not at speak time. Halfway/split should always read stats reflecting the moment the marker was crossed.

- **Setting for alert connection checks; default ON.** Add a user setting that periodically pings the phone during a ride to verify alert mirroring is healthy. If a check fails, fall back to local watch speech and surface a banner.

- **Auto-pause / auto-resume voice alerts always play correctly through headphones, but turn alerts sometimes come out of the watch speaker instead.** Both go through the same `audioSpeak` path so something timing-dependent is mis-routing turn alerts specifically. Investigate the route resolution at the moment each alert fires — there may be a race between audio session activation and `resolveAudioRoute()`.

- [ ] **Watch UI turn distance should step down through finer units before switching to feet/meters.** Subsumed by the In Flight `formatTurnDistance` rewrite above — now `≥1 mi → "X.X mi"`, `≥0.1 mi → tenths`, `<0.1 mi → feet rounded to 50`. Digit forms only (no unicode glyphs).

- [ ] **The second turn in a "turn right then turn left" announcement should include the street name when known.** Added `followingTurnPhrase(for:)` in `VoiceNavigator.swift` — extracts the road name from the second turn's description (`Turn X onto NAME` format), routes it through `applyRoadNamePronunciation`, and renders as `"turn right onto Main Street then turn left onto Pine Street"`. Falls back to direction-only when no name is present. Wired into both multi-turn approach branches (`passedTurn` immediate path and the distance-alert path).

- [ ] **Highway road-name pronunciation in voice alerts.** Added `applyRoadNamePronunciation(_:)` in `VoiceNavigator.swift`, applied from `voiceText(for:)` and `followingTurnPhrase(for:)`. Operates only on the post-`onto ` portion of a turn description so the "Turn right onto …" prefix is untouched. Rules: (1) leading 1-2 uppercase letters followed by a number token (`US 17`, `PA 106`, `I 95`) → letters spaced for letter-pronunciation; (2) trailing `N/S/E/W` → `north/south/east/west`; (3) `ST`/`ST.` disambiguation — first token (or token right after a comma) → `Saint`, otherwise → `Street`.

- [ ] **Back-on-route announcement reads "continue straight to continue" — redundant.** `VoiceNavigator.update(...)` rejoin branch now emits `"Back on route."` when the rejoin direction resolves to `continue straight`, and `"Back on route. <Direction>."` (no trailing "to continue") otherwise.

- **Phone first metric screen often out of sync during a ride; the second screen renders fine.** Find the metric binding on the first screen, confirm it's subscribed to the live telemetry store (likely `PhoneTelemetryStore`), and fix.

- [ ] **Free ride should display the heading direction on the map when the setting is enabled.** `RouteMapView.swift` was gating the cardinal-direction text on `mapConfig.showHeading && workout.hasRoute`. Dropped the `hasRoute` clause so the heading text renders on free rides too whenever the setting is on. (Distinct from the deeper "fix heading/compass direction" bug above.)

- [ ] **Off-route detection misses points between sparse route nodes.** Added `perpendicularDistance(point:a:b:)` and `refinedSegmentDistance(...)` helpers on `NavigationTracker` (`OG Bike Computer Watch App/Services/NavigationTracker.swift`). After `findNearest` picks a winning point index, the returned distance is now refined by computing perpendicular distance to the two adjacent segments (and only used when the rider's projection falls within the segment bounds), so a rider on a long straight stretch between widely-spaced GPX nodes no longer reads as off-route.

---

## 🔁 Hold Ride — Core Rework

- [ ] **The watch must be the source of truth for held ride state.** `handle(_:workoutConfiguration:)` on the watch now skips starting a new ride when a held ride exists, letting the WC message handler own the continue path. Phone-initiated starts that would discard a held ride are routed through a confirmation alert. The phone hides held rides from the history list and ride detail when the watch is unreachable.

- [ ] **Only the most recent held ride should ever be displayed. Starting a new ride must discard any existing held ride**, with a confirmation alert shown on both phone and watch. Starting from `StartRideView` on the watch, or from a WC `startRide` message, both trigger the confirmation before discarding.

- [x] **Add a discard option for held rides on both phone and watch.** Watch held ride menu has Continue / End & Save / Discard / Cancel. Phone `RideDetailView` has a "Discard Ride" button below the Continue/End&Save row. Discard from either device syncs the deletion to the other via a `deleteHeldRide` WC message.

- [x] **The continue and end & save buttons on the held ride screen should share a single row.** `RideDetailView` now shows Continue and End & Save side-by-side in an `HStack`, with Discard as a secondary action below.

- [ ] **Add a first-time explainer for the hold feature** with a "Don't show this again" toggle. The explainer sheet appears the first time hold countdown completes, before the ride is actually held. Preference persists in `UserDefaults`.

- **Hold ride sync still inconsistent across phone↔watch.** Three sub-bugs reported together:
  1. **End & Save on watch (from the held ride menu) doesn't queue the file transfer to phone** — normal end-of-ride does, but the held-ride end-save path doesn't. The ride never shows up in the phone history.
  2. **Phone Continue / End & Save / Discard buttons should immediately trigger the action on the watch.** Currently they go through `sendContinueHeldRide` / `sendFinalizeHeldRide` / `sendDiscardRide` in `Shared/Services/ConnectivityManager.swift` but the watch handler doesn't always run (state-dependent — foreground vs background vs active workout).
  3. **HK workout being saved without location data.** Sections appear in the Fitness app but the route is empty. Investigate `routeBuilder.finishRoute(with:)` in `WorkoutManager` — there's a `routeInsertGroup` DispatchGroup (`WorkoutManager.swift:170`) that `finishRoute` should be waiting on before completing.

---

## ✨ Essential New Features

- **Add an indicator on the ride list when a ride recording is actively being transferred from the watch**, including a "Syncing" label with spinner. The watch sends a `rideTransferStarting` userInfo before the file transfer begins, pre-populating the ride row on the phone. The spinner clears when the file arrives.

- **Add a 5-second countdown before the watch auto-starts a ride after route selection.** A Cancel button stops the countdown but stays on the current screen. The Back button cancels and returns home. The activity type selector should be a smaller circle button; tapping it opens a picker or new screen. The most recently selected type should be remembered.

- **Add a recording map to the phone ride control UI.** The selected route should be drawn in blue on this map.

- [ ] **Routes queued for transfer to the watch should be remembered across app relaunches.** `ConnectivityManager.sendRoute` previously staged the route JSON in `FileManager.temporaryDirectory`, which iOS can purge — so a transfer queued while the watch was unreachable could become un-replayable. Added `pendingRouteTransfersDirectory` (Documents/PendingRouteTransfers/) and route the staged file there. WCSession's outstanding-transfer queue already survives relaunches, so the file remains on disk for the OS to retry. Cleanup happens in a new `session(_:didFinish:error:)` delegate method that removes the staged file once the transfer terminates successfully (failures leave the file in place for retry).

- [ ] **Jumps in ride recordings caused by long pauses or holds should be drawn as dashed grey lines** on the map, visually distinguishing them from actively-ridden segments. Added `splitAtPauseGaps(locations:gapSeconds:)` in `RideDetailView.swift` that returns ridden runs separated by elapsed-time gaps >30s plus the gap coord pairs. `buildRideCache` now feeds the runs into `buildColoredSegments` per-run (so the speed gradient no longer draws a straight line across the gap) and stores the gap pairs in a new `pauseJumps` `@State`. The map renders gap pairs as a `MapPolyline` with `Color.gray` and a dashed StrokeStyle (`dash: [4, 3]`).

- **Screen lock mode: tap and hold to toggle.** Prevents accidental input during a ride.

- **Periodically check location during a manual pause.** If the rider has moved significantly from the pause location, show an alert offering "Resume Ride" or "Keep Paused". Check frequency and enable/disable should be configurable in settings.

- [ ] **Add auto-send to watch setting for route imports.** New `@AppStorage("autoSendRoutesToWatch")` toggle in `RideSettingsView.routeSharingSection` (phone-only — not part of `RidePreferences`, doesn't sync to watch). `RouteImportCoordinator.handle(_:)` reads the key; when on (and the watch is paired + installed), it kicks off `ConnectivityManager.sendRoute` for each imported route and publishes their IDs to `autoSentRouteIDs`. `RouteImportActionSheet` observes that set and pre-seeds the corresponding rows with `.sentToWatch`, so the rider sees the action already-resolved when the sheet appears.

- **Add auto-remove route setting with four options** (off by default): Off (current behavior), Phone (removes from phone after successful transfer to watch), Watch (removes from watch after the finish line is crossed), Both. Present as single-select options in settings.

- **Add a route and ride detail toolbar for toggling map layers/views**, including: weather (real-time for rides, projected for routes), wind, local elevation peaks and valleys, additional distance markers, and map type via MapKit.

- [x] **Tab ordering settings subpage (under Ride Settings).** Lets the user reorder the main watch screen tabs by drag — vertical carousel of tab cards. Default order: RouteMap, ElevationMap, then all metric pages. Individual metric pages must be independently orderable. Like all settings, must update live and continue working mid-ride.

- [x] **Include all waypoints/POIs from route sources on maps.** Strava `waypoints`, RWGPS `points_of_interest`, and standard GPX `<wpt>` tags (the ones that aren't turn cues) should all surface as POIs.
  - Phone (route detail and ride detail maps): show with an icon and label. (Ride detail still TODO — see Bug Fixes.)
  - Watch map screen: show with a `mappin` (or similar) icon, no label.
  - Add a Route Screens setting on the watch to display waypoints on: route map, elevation map, both, or neither.

- **Fix all preview screens in settings.** several systems are broken like the zoom buttons just grow the line of the map rather than actually pretending to zoom and show more/less curviness (also the line thickness scales in the demo which is bad), the waypoints on the elevation map are not on the curve, they just float above, and the elevation map itself is just half the are for the "Ahead" setting. take a look at all the preiews and fix obvious things. a more specific list of fixes like those examples will come later

- [ ] **Alternate mile markers above/below route line on watch map.** All three mile-marker rendering sites in `RouteMapView.swift` (full-route canvas, breadcrumb canvas, MapKit annotation) now alternate the flag/label offset based on marker index — even index above the route line, odd index below (flag rotated 180° when below). Reduces overlap when consecutive markers are close on screen.

- [ ] **Quick link to the currently-selected route detail from the phone ride control screen.** Added a "View Route Details" pill below the route selector in `RideControlView.swift` that appears whenever `activeRoute != nil`. Tapping it presents `RouteDetailView` in a sheet (wrapped in its own `NavigationStack` with a Done toolbar button), so the rider can re-check the route map mid-ride without losing the ride control screen.

---

## 🔔 Navigation Alerts

- [x] **Remove climb and descent alerts entirely** — both the alert functionality and the entries on the navigation alerts settings page.

- [x] **Promote split updates, auto pause/resume, and haptic feedback out of the Experimental section.** Move them into the regular alert settings list and remove the Experimental section header from the navigation alerts settings page entirely.

- [ ] **Add a navigation alert for waypoints / POIs.** Added `checkPOIAlerts(nav:route:)` in `VoiceNavigator.swift`, called once per `update(...)` after turn/halfway checks (so it can't preempt navigation alerts — uses `.stat` priority). Iterates `route.pois`, skips POIs farther off-route than `WaypointAlertPreferences.maxOffRouteDistance`, and fires once per `(poi, tier)` via a `firedPOIAlerts: Set<String>` keyed `"<index>-<tier>"`. Tiers come from `WaypointAlertPreferences` when `useCustomDistances` is on, else mirror turn alert primary/secondary distances. Wording: `"in <dist>, pass <name>."` when the POI is on-route (≤30m off), else `"in <dist> to your <side>, <off-dist> off route, is <name>."` Bearing/side is computed from the route bearing at the POI's nearest route point vs. bearing to the POI coordinate (left/right; dropped when nearly aligned or directly behind). `firedPOIAlerts` clears in both `reset()` and `resetForRouteSwap()`.

- [ ] **Setting to control the order of split and halfway stat announcements.** `SplitMetricPickerView` now exposes drag-reorder on the "Selected Stats" section via `.onMove` + an `EditButton` in the toolbar; the stored `metrics` array order is the announce order. Removed the `sorted { a, _ in a.metric == .distance }` calls in `VoiceNavigator.announceSplit` and `VoiceNavigator.announceHalfway` so both readouts honor the user-chosen order verbatim.

---

## ⚙️ Settings Reorganization

- [x] **Rename "Map Screen" settings page to "Route Screens"** and nest the elevation screen settings under it.
  - Keep the existing map-screen settings at the top.
  - Add a toggle (default ON) for showing the elevation screen, with a live demo/preview matching the map and metric previews.
  - Add elevation-screen-specific settings: how far ahead the "Ahead" tab looks (distance), which tab to default to (full route vs. ahead), plus any other logical knobs (e.g., grade overlay, gain/loss readout toggles).

---

## 🗺️ Elevation View Improvements

- [x] **Chart scrubber in ride and route detail (phone):** Drag on the elevation (or any metric) chart to move a scrub position line. A dot appears on the map at that route position, and a readout above the chart shows the value at that point. Applies to both `RideDetailView` (all metrics) and `RouteDetailView` (elevation chart).

- [x] **Watch elevation profile view:** A new vertical tab in the workout view (only shown when a route with elevation data is loaded) displays the full route elevation chart with the rider's current position marked. Toggle between full-route and 5-mile lookahead modes. Current elevation and total gain are shown below the chart.

- [x] **Preprocess a simplified elevation profile on the phone for use on the watch.** The full-route elevation chart on the watch is too slow to render. When a route is sent to the watch, the phone should produce a smoothed/decimated elevation series that preserves major peaks and valleys (e.g., Ramer-Douglas-Peucker or peak-preserving downsampling) capped to a small point count (target a few hundred points max). The watch renders only the simplified series; the full-resolution data stays on the phone.

- **Add a draggable handle on the route map (phone) that syncs a dot on the elevation graph**, with an elevation readout shown above it.

- **Zooming into a section on the route map should zoom the elevation graph to show that section.**

---

## 🎛️ UI Polish

- [ ] **Swap icons for current elevation vs. total elevation gain.** `ElevationProfileView.elevationReadout` had them reversed — current elevation was using `arrow.up.right` and gain was using `mountain.2`. Swapped to current → `mountain.2`, gain → `arrow.up.right`. (`MetricType.icon` was already correct; only the readout view was wrong.)

- [ ] **Scrubbing dot color on ride detail charts should match chart color.** Threaded the active chart color out of `RideChartsView` via a new optional `scrubColor: Binding<Color>` (writes from `onAppear` and `onChange(of: selected)`). `RideDetailView` now binds it and uses the value as the map scrub-dot stroke color, replacing the hard-coded `Color.accentColor` (which read as purple). Elevation = green, speed = blue, HR = red, power = orange. RouteDetailView's scrub dot was already correctly colored green (it only scrubs elevation), so no change there.

- [ ] **Left-justify x-axis labels on stats panel charts (phone + watch).** Phone (`RideCharts.swift`) and watch (`ElevationProfileView.swift`) chart x-axis labels now use `AxisValueLabel(anchor: .topLeading)` so they're anchored to the left edge of their tick instead of centering. The rightmost label no longer gets clipped at the chart edge.

---

## 🔗 Sharing & Integrations

- **Allow selecting multiple ride recordings and uploading them as a single Strava or RideWithGPS activity.**

- **Add easy route sharing via AirDrop.**

---

## 🎛️ Advanced / Bonus Features

- **Add a watch-only mode setting that suppresses all phone communication except voice alerts.** When enabled, the phone will never show a ride control screen during an active ride.

- [ ] **Add an end-of-route stat audio readout.** New `EndOfRouteAlertPreferences` (enabled, mode, `useSplitsMetrics`, `metricsOverride`) added to `NavigationAlertPreferences.swift`. `VoiceNavigator.announceEndOfRouteStats()` enqueues stat readouts after the arrival alert when `nav.isRouteComplete` first flips and `announcedArrival` is set. Defaults to mirroring the split/halfway metric list; toggling off "Use Split Stats" reveals a custom metric picker (`SplitMetricPickerView` bound to `metricsOverride`). Settings exposed under a new "End-of-Route Readout" section in `NavigationAlertSettingsView`.

- **Add a turn editor** so riders can review and modify turn cues on a route.

- **Add the ability to select sections of a route or ride recording to exclude from distance and elevation calculations.** Use case: mark a ferry crossing or vehicle shuttle as "not biking" so it doesn't pollute the ride stats.
  - Excluded sections render greyed out on the route/ride map, matching the style used for pause-jump segments.
  - Excluded from distance, elevation gain/loss, and any cumulative stat.
  - **Affects split + halfway calculations** — this is the main practical motivation. Currently a ferry crossing throws off splits for the rest of the ride.
  - Export caveat: Strava and RideWithGPS don't have a native "skip" concept; for now keep exclusion as our-app-UI-only. May be worth investigating their "pause" / "split" semantics later to see if we can represent jumps in the uploaded activity.
  - Implementation hint: probably a separate "excluded ranges" array on `RideSummary` / `Route` rather than mutating the point arrays — keeps the raw data intact and lets the user un-exclude.
