# healthsync CLI Reference

Complete command reference for the healthsync CLI tool.

## Synopsis

```
healthsync <command> [options]
```

## Global Options

| Option | Description |
|--------|-------------|
| `--version` | Print version and exit |
| `--help, -h` | Print help for command |

---

## Commands

### discover

Discover Health Sync servers on the local network using Bonjour/mDNS.

```bash
healthsync discover [--timeout <seconds>]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--timeout, -t` | 5 | Seconds to wait for discovery |

**Examples:**

```bash
# Quick scan
healthsync discover

# Extended scan for slow networks
healthsync discover --timeout 15
```

---

### scan

Pair with a Health Sync server by scanning a QR code.

```bash
healthsync scan [--json <string>]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--json, -j` | Manually provide pairing JSON instead of camera scan |

**Examples:**

```bash
# Scan QR code with camera
healthsync scan

# Manual pairing (if camera unavailable)
healthsync scan --json '{"host":"192.168.1.50","port":8443,"token":"abc123","fingerprint":"sha256:..."}'
```

**Notes:**
- Opens system camera for QR scanning
- Pairing tokens expire after 5 minutes
- Stores credentials in macOS Keychain

---

### status

Check connection status with the configured server.

```bash
healthsync status
```

**Output:**
- Server connection status
- App version
- HealthKit availability

**Example:**

```bash
$ healthsync status
📡 Checking connection to 192.168.1.50:8443...

✅ Connected!
   Status: ok
   Version: 1.0.0
   HealthKit: Available
```

---

### types

List available health data types.

```bash
healthsync types [--format <format>]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--format, -f` | table | Output format: `table`, `json`, `csv` |

**Example:**

```bash
$ healthsync types

📊 Available Health Data Types:

   ID                  Name
   ──────────────────  ────────────────────
   steps               Step Count
   distance            Walking + Running Distance
   workouts            Workouts
   weight              Body Weight
   bodyFat             Body Fat Percentage
   nutrition           Dietary Energy
   heartRate           Heart Rate
   hrv                 Heart Rate Variability
   sleep               Sleep Analysis
```

---

### fetch

Fetch health data from the server.

```bash
healthsync fetch [options]
```

**Options:**

| Option | Default | Description |
|--------|---------|-------------|
| `--type, -t` | steps | Data type to fetch |
| `--days, -d` | 7 | Number of days to fetch |
| `--start` | | Start date (ISO 8601) |
| `--end` | | End date (ISO 8601) |
| `--format, -f` | csv | Output format: `csv`, `json`, `table` |
| `--output, -o` | | Output file path |
| `--metadata` | false | Include metadata in output |

**Date Precedence:**
1. If `--start` and `--end` provided, use that range
2. Otherwise, use `--days` from today

**Examples:**

```bash
# Last 7 days of steps (default)
healthsync fetch

# Last 30 days of weight
healthsync fetch --type weight --days 30

# Specific date range
healthsync fetch --type workouts --start 2024-01-01 --end 2024-06-30

# Export to JSON file
healthsync fetch --type nutrition --format json --output nutrition.json

# Pipe to other tools
healthsync fetch --type steps --format csv | csvstat
```

**Output Formats:**

CSV (default):
```csv
date,value,unit
2024-01-15T08:00:00Z,8542,count
2024-01-14T08:00:00Z,10234,count
```

JSON:
```json
[
  {
    "startDate": "2024-01-15T08:00:00Z",
    "value": 8542,
    "unit": "count"
  }
]
```

Table:
```
Date                 Value        Unit
───────────────────  ───────────  ─────────
2024-01-15T08:00:00       8542   count
```

---

### config

Manage CLI configuration.

#### config show

Display current configuration.

```bash
healthsync config show
```

**Example:**

```bash
$ healthsync config show

📋 Current Configuration:

   Host:        192.168.1.50
   Port:        8443
   Fingerprint: sha256:a1b2c3d4e5f6...

   Config file: ~/.healthsync/config.json
   Token:       ✅ Stored in Keychain
```

#### config reset

Reset configuration and remove stored credentials.

```bash
healthsync config reset [--force]
```

**Options:**

| Option | Description |
|--------|-------------|
| `--force` | Skip confirmation prompt |

---

## Data Types Reference

### Activity Types

| Type | Unit | Description |
|------|------|-------------|
| `steps` | count | Daily step count |
| `distance` | meters | Walking/running distance |
| `activeEnergy` | kcal | Active calories burned |
| `basalEnergy` | kcal | Resting calories burned |

### Workouts

| Type | Fields | Description |
|------|--------|-------------|
| `workouts` | type, duration, calories, distance | Exercise sessions |

Workout types include: running, walking, cycling, swimming, hiking, strength training, yoga, etc.

### Body Measurements

| Type | Unit | Description |
|------|------|-------------|
| `weight` | kg | Body weight |
| `bodyFat` | % | Body fat percentage |
| `leanBodyMass` | kg | Lean body mass |

### Heart

| Type | Unit | Description |
|------|------|-------------|
| `heartRate` | bpm | Heart rate samples |
| `restingHeartRate` | bpm | Resting heart rate |
| `hrv` | ms | Heart rate variability (SDNN) |

### Nutrition

| Type | Unit | Description |
|------|------|-------------|
| `nutrition` | kcal | Dietary energy consumed |
| `protein` | g | Protein intake |
| `carbs` | g | Carbohydrate intake |
| `fat` | g | Fat intake |
| `fiber` | g | Fiber intake |
| `sugar` | g | Sugar intake |
| `sodium` | mg | Sodium intake |

### Sleep

| Type | Unit | Description |
|------|------|-------------|
| `sleep` | minutes | Sleep analysis stages |

Includes: inBed, asleep, awake, REM, core, deep.

---

## Configuration Files

### Config Location

```
~/.healthsync/config.json
```

### Config Format

```json
{
  "host": "192.168.1.50",
  "port": 8443,
  "fingerprint": "sha256:a1b2c3d4e5f6..."
}
```

### Keychain Storage

Access tokens are stored in macOS Keychain under:
- **Service**: `org.mvneves.healthsync.cli`
- **Account**: `token-{host}`

---

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Not configured |
| 3 | Connection failed |
| 4 | Authentication failed |

---

## Environment Variables

| Variable | Description |
|----------|-------------|
| `HEALTHSYNC_CONFIG` | Override config file path |
| `HEALTHSYNC_DEBUG` | Enable debug output (1/0) |

---

## See Also

- [User Guide](USER-GUIDE.md) - Setup and usage guide
- [Security](SECURITY.md) - Security architecture
