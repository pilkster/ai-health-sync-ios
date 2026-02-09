# Health Sync User Guide

A complete guide to setting up and using Health Sync to export your Apple Health data to your Mac.

## Prerequisites

- **iPhone**: iOS 17.0 or later
- **Mac**: macOS 14.0 or later
- **Network**: Both devices on the same Wi-Fi network

## Installation

### iOS App

1. Open `HealthSync.xcodeproj` in Xcode 16+
2. Select your iPhone as the build target
3. Build and run (⌘R)
4. When prompted, grant the following permissions:
   - **HealthKit**: Allow access to read health data
   - **Local Network**: Required for the server to accept connections

### macOS CLI

```bash
cd HealthSyncCLI
swift build -c release

# Optional: install globally
sudo cp .build/release/healthsync /usr/local/bin/
```

## Quick Start (5 Minutes)

### Step 1: Start the Server (iPhone)

1. Open the Health Sync app
2. Tap **Start Server**
3. Note the displayed IP address (e.g., `192.168.1.x:8443`)

### Step 2: Pair (Mac)

1. On iPhone, tap **Generate QR Code**
2. On Mac, run:
   ```bash
   healthsync scan
   ```
3. Point your Mac's camera at the QR code
4. Wait for "Successfully paired!" message

### Step 3: Fetch Data (Mac)

```bash
# Check connection
healthsync status

# Fetch last 7 days of steps
healthsync fetch --type steps

# Fetch workouts as JSON
healthsync fetch --type workouts --format json

# Fetch weight data to file
healthsync fetch --type weight --output weight.csv
```

## Detailed Setup

### iPhone App

#### Granting HealthKit Permissions

On first launch, the app requests access to:

- **Steps & Distance**
- **Workouts**
- **Weight & Body Composition**
- **Nutrition** (calories, macros)
- **Heart Rate & HRV**
- **Sleep Analysis**

Grant access to the data types you want to sync.

#### Starting the Server

1. Tap **Start Server** on the main screen
2. The app displays:
   - **Status**: Running on port 8443
   - **IP Address**: Your device's local IP
3. Keep the app in foreground for best performance

#### Generating QR Codes

1. Tap **Share** or **Generate QR Code**
2. QR code contains:
   - Device IP address and port
   - One-time pairing token
   - Server certificate fingerprint
3. **Important**: Tokens expire after 5 minutes

#### Viewing Audit Logs

1. Go to **Logs** tab
2. See all data access events:
   - Date/time
   - Client IP
   - Data types accessed
   - Records fetched

### Mac CLI

#### Available Commands

| Command | Description |
|---------|-------------|
| `healthsync discover` | Find servers on network |
| `healthsync scan` | Pair via QR code |
| `healthsync status` | Check connection |
| `healthsync types` | List data types |
| `healthsync fetch` | Download health data |
| `healthsync config show` | View configuration |
| `healthsync config reset` | Clear credentials |

#### Fetching Data

```bash
# Basic fetch (last 7 days of steps)
healthsync fetch

# Specify type and duration
healthsync fetch --type weight --days 30

# Custom date range
healthsync fetch --type workouts --start 2024-01-01 --end 2024-12-31

# Different output formats
healthsync fetch --type nutrition --format csv
healthsync fetch --type nutrition --format json --output nutrition.json
```

#### Available Data Types

| Type | Description |
|------|-------------|
| `steps` | Daily step count |
| `distance` | Walking/running distance |
| `workouts` | Exercise sessions |
| `weight` | Body weight measurements |
| `bodyFat` | Body fat percentage |
| `nutrition` | Calorie and macro intake |
| `heartRate` | Heart rate samples |
| `hrv` | Heart rate variability |
| `sleep` | Sleep analysis |

## Automation

### Scheduled Syncs

Use cron to automatically sync data:

```bash
# Edit crontab
crontab -e

# Add daily sync at 6 AM
0 6 * * * /usr/local/bin/healthsync fetch --type steps --days 1 >> ~/health-data/steps.csv
```

### Integration with Other Tools

Export to common formats for analysis:

```bash
# Export to CSV for Excel/Numbers
healthsync fetch --type weight --days 365 --output weight-2024.csv

# Export to JSON for scripts
healthsync fetch --type workouts --format json | jq '.[] | {date, type, duration}'
```

## Troubleshooting

### "No servers found"

1. Ensure iPhone app is open and server is started
2. Check both devices are on the same Wi-Fi network
3. Disable VPN on both devices
4. Check iPhone's Local Network permission is granted

### "Connection refused"

1. Verify server is running on iPhone
2. Check firewall settings on Mac
3. Try `healthsync discover` to find the server

### "Certificate mismatch"

The server's certificate has changed. Reset and re-pair:

```bash
healthsync config reset
healthsync scan
```

### "Pairing code expired"

QR codes expire after 5 minutes. Generate a new one on iPhone and scan again.

### "Unauthorized"

Your access token may be invalid. Reset and re-pair:

```bash
healthsync config reset
healthsync scan
```

## Privacy & Security

- **Local Only**: Data never leaves your network
- **Encrypted**: All communication uses TLS 1.2+
- **No Cloud**: No accounts, no cloud services
- **Audit Trail**: All access logged on device
- **Your Data**: Export anytime, delete anytime

See [SECURITY.md](SECURITY.md) for technical details.

## Tips

1. **Battery**: Server uses minimal battery but close when not syncing
2. **Large Exports**: For years of data, use date ranges to chunk exports
3. **MFP Data**: MyFitnessPal syncs to HealthKit → appears in nutrition type
4. **Workout Details**: Includes type, duration, calories, distance, heart rate zones

## Getting Help

- Check [CLI Reference](CLI-REFERENCE.md) for all command options
- File issues at [GitHub](https://github.com/ainekomacx/ai-health-sync-ios)
