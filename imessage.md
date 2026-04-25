# iMessage App Extension for Computa



## Context



The user wants to share routes and rides directly in iMessage conversations. Recipients should be able to view the map inline, send a route to their Apple Watch, or save it to the phone app. This requires a new iMessage extension target, a shared data container (app groups), and payload encoding to embed route/ride data within iMessage messages.



---



## Phase 1: Foundation — App Groups & Shared Container



The iMessage extension runs in a separate process and cannot access the main app's documents directory. An app group is required.



### 1.1 Create `Shared/Utils/SharedContainer.swift`

- Define `appGroupID = "group.com.aidan3445.computa"`

- Provide `documentsDirectory` that resolves to the app group container (with fallback to standard documents dir for contexts without the entitlement)



### 1.2 Migrate stores to shared container

- **`Shared/Stores/RouteStore.swift`** — Change `init()` to use `SharedContainer.documentsDirectory` instead of `FileManager.default.urls(for: .documentDirectory, ...)`

- **`Shared/Stores/RideStore.swift`** — Same change

- **`Shared/Services/ConnectivityManager.swift`** — Change `ridesDirectory` static property to use `SharedContainer.documentsDirectory`



### 1.3 Add app group entitlement

- **`OG Bike Computer/OG Bike Computer.entitlements`** — Add `com.apple.security.application-groups` with `group.com.aidan3445.computa`



### 1.4 Data migration in main app

- **`OG Bike Computer/OG_Bike_ComputerApp.swift`** — On first launch after update, detect files in the old documents directory (`routes/`, `rides/`) and move them to the new app group container. Copy first, verify, then delete originals.



---



## Phase 2: iMessage Extension Target



### 2.1 Create the extension target

- New directory: `OG Bike Computer Messages/`

- Bundle ID: `com.aidan3445.computa.messages`

- Deployment target: iOS 26.0

- Create `Info.plist` with `NSExtension` → `NSExtensionPointIdentifier: com.apple.identities.messages` and `NSExtensionPrincipalClass: MessagesViewController`

- Create `OG Bike Computer Messages.entitlements` with same app group

- Create `Assets.xcassets` with iMessage app icon



### 2.2 Shared file membership

Include in the Messages target:

- `Shared/Models/` — Route, RideSummary, TrackPoint, Waypoint, ActivityType, IntegrationTypes, UnitPreferences, ProcessedRoute

- `Shared/Stores/` — RouteStore, RideStore

- `Shared/Services/` — TrackEncoder, GPXExporter

- `Shared/Utils/` — Formatting, MileMarkers, SharedContainer



Exclude from the Messages target:

- `Shared/Services/ConnectivityManager.swift` (WatchConnectivity unavailable in extensions)

- `Shared/Services/TransferLedger.swift`

- `Shared/Stores/MetricConfigStore.swift`, `UserSettingsStore.swift`



### 2.3 Fix HealthKit dependency

- **`Shared/Models/ActivityType.swift`** — Wrap `import HealthKit` and the `hkType`/`distanceType` computed properties in `#if canImport(HealthKit)` so the enum compiles in the extension without HealthKit framework



---



## Phase 3: Message Payload Encoding



Routes can have thousands of points. `MSMessage.url` has practical size limits. Strategy: compress route/ride JSON with LZFSE, base64-encode, embed in URL query parameters. Simplify large routes with Douglas-Peucker.



### 3.1 Create `Shared/Services/MessagePayload.swift`

- `encodeRoute(_ route: Route) -> URL?` — Simplify to ≤3000 points, JSON-encode, LZFSE compress, base64, build URL with type=route

- `decodeRoute(from url: URL) -> Route?` — Reverse process

- `encodeRide(_ ride: RideSummary, trackPoints: [TrackPoint]) -> URL?` — Encode summary + down-sampled track (≤2000 points, lat/lon only)

- `decodeRide(from url: URL) -> (RideSummary, [TrackPoint])?` — Reverse



### 3.2 Create `Shared/Utils/RouteSimplifier.swift`

- Douglas-Peucker algorithm for `[TrackPoint]` → reduced point count while preserving route shape



---



## Phase 4: MessagesViewController



### 4.1 Create `OG Bike Computer Messages/MessagesViewController.swift`

- Subclass `MSMessagesAppViewController`

- Two modes:

  - **Compose mode** (no selected message): Show picker to browse routes/rides from shared container

  - **Receive mode** (`didSelect` message): Decode payload, show map view

- Handle compact ↔ expanded transitions by swapping the hosted SwiftUI view

- Build `MSMessage` with `MSMessageTemplateLayout`:

  - `image`: Pre-rendered map snapshot via `MKMapSnapshotter`

  - `caption`: Route/ride name

  - `subcaption`: Distance + key stat

  - `url`: Encoded payload



---



## Phase 5: SwiftUI Views for the Extension



### 5.1 `OG Bike Computer Messages/Views/MessagePickerView.swift`

- Segmented control: Routes | Rides

- List loaded from RouteStore/RideStore (shared container)

- Tapping an item creates and inserts the MSMessage



### 5.2 `OG Bike Computer Messages/Views/MessageRouteMapView.swift`

- Simplified version of `RouteDetailView` (no watch connectivity, no UnitState dependency)

- MapKit map with polyline, start/end markers, stats panel

- Buttons: **"Save to Phone"** and **"Send to Watch"**



### 5.3 `OG Bike Computer Messages/Views/MessageRideMapView.swift`

- Simplified version of `RideDetailView`

- Single-color polyline (no speed coloring — avoids needing timestamps in payload)

- Stats: distance, moving time, avg speed, elevation

- Button: **"Save to Phone"**



### 5.4 `OG Bike Computer Messages/Views/MessageCompactView.swift`

- Small summary card for compact presentation (~90pt)

- Route: name, distance, elevation gain

- Ride: name, date, distance



### 5.5 `OG Bike Computer Messages/Views/MessageBubbleRenderer.swift`

- Uses `MKMapSnapshotter` to render a static map image with the polyline drawn on it

- Used for the `MSMessageTemplateLayout.image` so the bubble looks good before tapping



---



## Phase 6: Save to Phone & Send to Watch



### 6.1 "Save to Phone" (in iMessage extension)

- Decode route/ride from MSMessage URL

- Save via `RouteStore.save()` / `RideStore.save()` (writes to shared app group container)

- For rides: reconstruct track binary from the simplified `[TrackPoint]` using `TrackEncoder`

- Show confirmation in the extension UI



### 6.2 "Send to Watch" (deep link to main app)

- WCSession is unavailable in extensions, so the extension opens the main app via URL scheme

- Extension calls `extensionContext?.open(URL(string: "ogbikecomputer://send-to-watch?routeId=\(uuid)")!)`

- Show brief "Opening Computa..." message in extension UI



### 6.3 Handle deep link in main app

- **`OG Bike Computer/OG_Bike_ComputerApp.swift`** — Extend `onOpenURL` handler:

  - Parse `ogbikecomputer://send-to-watch?routeId={UUID}`

  - Find route in RouteStore, call `ConnectivityManager.shared.sendRoute()`

  - Show confirmation to user



---



## Files to Create



| File | Purpose |

|------|---------|

| `Shared/Utils/SharedContainer.swift` | App group container URL resolution |

| `Shared/Services/MessagePayload.swift` | Encode/decode route/ride data for MSMessage URLs |

| `Shared/Utils/RouteSimplifier.swift` | Douglas-Peucker point reduction |

| `OG Bike Computer Messages/MessagesViewController.swift` | Extension entry point |

| `OG Bike Computer Messages/Info.plist` | Extension config |

| `OG Bike Computer Messages/OG Bike Computer Messages.entitlements` | App group |

| `OG Bike Computer Messages/Assets.xcassets/` | Icons |

| `OG Bike Computer Messages/Views/MessagePickerView.swift` | Compose flow picker |

| `OG Bike Computer Messages/Views/MessageRouteMapView.swift` | Route map display |

| `OG Bike Computer Messages/Views/MessageRideMapView.swift` | Ride map display |

| `OG Bike Computer Messages/Views/MessageCompactView.swift` | Compact mode summary |

| `OG Bike Computer Messages/Views/MessageBubbleRenderer.swift` | Map snapshot for bubble |



## Files to Modify



| File | Change |

|------|--------|

| `Shared/Stores/RouteStore.swift` | Use `SharedContainer.documentsDirectory` |

| `Shared/Stores/RideStore.swift` | Use `SharedContainer.documentsDirectory` |

| `Shared/Services/ConnectivityManager.swift` | Use `SharedContainer.documentsDirectory` for `ridesDirectory` |

| `Shared/Models/ActivityType.swift` | `#if canImport(HealthKit)` guards |

| `OG Bike Computer/OG Bike Computer.entitlements` | Add app group |

| `OG Bike Computer/OG_Bike_ComputerApp.swift` | Data migration + send-to-watch URL handler |

| `OG Bike Computer.xcodeproj/project.pbxproj` | New target, file references, build phases |



---



## Verification



1. Build the main app — ensure routes/rides still load correctly after SharedContainer migration

2. Build the Messages extension — ensure it loads in the iOS Simulator Messages app

3. Test compose flow: open Computa in iMessage → pick a route → message appears with map snapshot bubble

4. Test receive flow: tap a received route message → map renders with polyline and stats

5. Test "Save to Phone": save a received route → open main app → route appears in list

6. Test "Send to Watch": tap send to watch → main app opens → route transfers via WCSession

7. Test with rides: same flow as routes but with ride data


