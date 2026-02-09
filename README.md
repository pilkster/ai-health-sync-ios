# AI Health Sync

A secure, local-network health data synchronization solution for iOS. Extract your HealthKit data to your Mac without cloud dependencies.

## Overview

AI Health Sync consists of two components:
1. **iOS App** - Runs a secure TLS server on your iPhone, exposing HealthKit data
2. **macOS CLI** - Fetches health data from the iOS app over your local network

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           AI Health Sync Architecture                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────┐                    ┌─────────────────────────┐    │
│  │     iPhone          │                    │        Mac               │    │
│  │                     │                    │                         │    │
│  │  ┌───────────────┐  │   Local Network    │  ┌───────────────────┐  │    │
│  │  │  HealthKit    │  │   (mTLS/8443)      │  │  healthsync CLI   │  │    │
│  │  │    Store      │  │ ◄────────────────► │  │                   │  │    │
│  │  └───────┬───────┘  │                    │  │  - discover       │  │    │
│  │          │          │   QR Code Pairing  │  │  - scan           │  │    │
│  │  ┌───────▼───────┐  │ ─────────────────► │  │  - fetch          │  │    │
│  │  │ Health Sync   │  │                    │  │  - status         │  │    │
│  │  │    Server     │  │                    │  │  - types          │  │    │
│  │  │  (TLS/8443)   │  │                    │  └───────────────────┘  │    │
│  │  └───────┬───────┘  │                    │           │             │    │
│  │          │          │                    │           ▼             │    │
│  │  ┌───────▼───────┐  │                    │  ┌───────────────────┐  │    │
│  │  │   Keychain    │  │                    │  │     Keychain      │  │    │
│  │  │  (Token/Cert) │  │                    │  │  (Token/Config)   │  │    │
│  │  └───────────────┘  │                    │  └───────────────────┘  │    │
│  │          │          │                    │           │             │    │
│  │  ┌───────▼───────┐  │                    │           ▼             │    │
│  │  │  SwiftData    │  │                    │  ┌───────────────────┐  │    │
│  │  │  Audit Logs   │  │                    │  │   CSV/JSON Output │  │    │
│  │  └───────────────┘  │                    │  └───────────────────┘  │    │
│  │                     │                    │                         │    │
│  └─────────────────────┘                    └─────────────────────────┘    │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Features

### iOS App
- 📱 Clean SwiftUI interface for iOS 17+
- 🔐 Self-signed certificate generation on first launch
- 🌐 Local network TLS server (port 8443)
- 📊 HealthKit data access: steps, workouts, weight, nutrition
- 🔗 QR code pairing with one-time tokens
- 📝 Full audit logging of all data access
- 🔒 Keychain-secured token storage

### macOS CLI
- 🔍 Automatic device discovery via Bonjour
- 📡 QR code scanning for pairing
- 📈 Flexible data fetching with date ranges
- 📋 CSV and JSON output formats
- 🔐 TOFU certificate pinning
- 🔑 Keychain-secured credentials

## Security Model

- **Local Network Only**: All communication stays on your local network
- **mTLS**: Mutual TLS authentication with certificate pinning
- **One-Time Tokens**: Pairing tokens expire after 5 minutes
- **Keychain Storage**: Secrets never stored in plain text
- **Audit Logging**: Every data access is logged on device

See [SECURITY.md](docs/SECURITY.md) for detailed security architecture.

## Quick Start

### iOS App

1. Build and install the HealthSync app from Xcode
2. Grant HealthKit permissions when prompted
3. Tap "Start Server" to begin listening for connections
4. Use the QR code to pair with the CLI

### macOS CLI

```bash
# Build the CLI
cd HealthSyncCLI
swift build -c release

# Install (optional)
cp .build/release/healthsync /usr/local/bin/

# Discover devices on your network
healthsync discover

# Scan QR code to pair
healthsync scan

# Check connection status
healthsync status

# List available data types
healthsync types

# Fetch step data from last 7 days
healthsync fetch --type steps --days 7

# Fetch all data in JSON format
healthsync fetch --format json --output health-data.json
```

## Requirements

- **iOS App**: iOS 17.0+, iPhone with HealthKit
- **CLI**: macOS 14.0+, Swift 6.0+

## Documentation

- [User Guide](docs/USER-GUIDE.md) - Setup and usage instructions
- [CLI Reference](docs/CLI-REFERENCE.md) - Complete CLI documentation
- [Security Architecture](docs/SECURITY.md) - Security design details

## Building

### iOS App

Open `HealthSync.xcodeproj` in Xcode 16+ and build for your device.

### CLI

```bash
cd HealthSyncCLI
swift build -c release
```

## License

MIT License - See [LICENSE](LICENSE) for details.

## Author

Created with ❤️ for personal health data sovereignty.
