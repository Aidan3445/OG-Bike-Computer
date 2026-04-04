# Computa

A GPS cycling computer for Apple Watch and iPhone. Records rides, provides turn-by-turn navigation, and syncs with Strava and RideWithGPS.

## Features

**Watch App**
- Real-time metrics: speed, distance, elevation, heart rate, power estimate
- Turn-by-turn navigation with voice guidance and haptic alerts
- Customizable metric layout
- Off-route detection with automatic rejoin

**iPhone App**
- Route management: import GPX files or pull routes directly from Strava and RideWithGPS
- Ride history with extended stats
- Live Activity on lock screen and Dynamic Island during active rides
- Auto-upload completed rides to Strava

**Integrations**
- Strava — import routes, upload rides
- RideWithGPS — import routes
- Apple Health — workout recording and heart rate

## Project Structure

```
OG Bike Computer/            # iPhone app
OG Bike Computer Watch App/  # Watch app
OG Bike Computer Widget/     # Live Activity widget
Shared/                      # Cross-platform models, stores, services
```

## Requirements

- Xcode 15+
- iOS 26 / watchOS 26
- Apple Watch paired to iPhone

## Setup

1. Clone the repo
2. Open `OG Bike Computer.xcodeproj`
3. Set your development team in the project signing settings
4. Build and run on device or simulator

For Strava/RideWithGPS integrations, add your OAuth client credentials in the respective manager files under `OG Bike Computer/Services/Integrations/`.
