# Security Architecture

Health Sync is designed with a security-first approach. All health data stays on your local network with no cloud dependencies.

## Threat Model

### Protected Against

- **Network eavesdropping**: All traffic encrypted with TLS 1.2+
- **Man-in-the-middle attacks**: Certificate pinning (TOFU model)
- **Credential theft**: Tokens stored in OS Keychain, never in files
- **Unauthorized access**: One-time pairing tokens, audit logging
- **Remote attacks**: Local network only, no internet exposure

### Out of Scope

- Physical device access (rely on device passcode/biometrics)
- Malware on paired devices
- Compromised Wi-Fi network infrastructure

## Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    Security Layers                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────┐        ┌─────────────────────────────┐ │
│  │   iOS Device    │        │      macOS Device           │ │
│  │                 │        │                             │ │
│  │ ┌─────────────┐ │        │ ┌─────────────────────────┐ │ │
│  │ │  Keychain   │ │        │ │       Keychain          │ │ │
│  │ │  - Token    │ │        │ │  - Access Token         │ │ │
│  │ │  - Cert/Key │ │        │ │  - (no private keys)    │ │ │
│  │ └─────────────┘ │        │ └─────────────────────────┘ │ │
│  │       ▲         │        │            ▲               │ │
│  │       │         │        │            │               │ │
│  │ ┌─────┴───────┐ │        │ ┌──────────┴─────────────┐ │ │
│  │ │  TLS Server │◄┼────────┼─┤    TLS Client          │ │ │
│  │ │  (port 8443)│ │  mTLS  │ │  (cert pinning)        │ │ │
│  │ └─────────────┘ │        │ └────────────────────────┘ │ │
│  │       ▲         │        │                           │ │
│  │       │         │        │                           │ │
│  │ ┌─────┴───────┐ │        │                           │ │
│  │ │ Local-Only  │ │        │                           │ │
│  │ │ Validation  │ │        │                           │ │
│  │ └─────────────┘ │        │                           │ │
│  │                 │        │                           │ │
│  └─────────────────┘        └───────────────────────────┘ │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

## TLS Configuration

### Server (iOS)

- **Protocol**: TLS 1.2 minimum, TLS 1.3 preferred
- **Certificate**: Self-signed, generated on first launch
- **Key Size**: RSA 2048-bit or ECDSA P-256
- **Cipher Suites**: Modern suites only (AEAD)
- **Certificate Lifetime**: Generated once, persists in Keychain

### Client (macOS)

- **Certificate Pinning**: TOFU (Trust On First Use)
- **Fingerprint**: SHA-256 of server certificate
- **Validation**: Fingerprint must match on every connection

## Authentication Flow

### Initial Pairing

```
┌──────────┐                           ┌──────────┐
│  iPhone  │                           │   Mac    │
└────┬─────┘                           └────┬─────┘
     │                                      │
     │  1. Generate one-time token         │
     │     (expires in 5 minutes)          │
     │                                      │
     │  2. Display QR code containing:     │
     │     - host:port                     │
     │     - pairing token                 │
     │     - cert fingerprint              │
     │                                      │
     │◄─────── 3. Scan QR code ────────────│
     │                                      │
     │◄─── 4. POST /pair (TLS) ────────────│
     │       Authorization: Bearer <token> │
     │                                      │
     │──── 5. Return permanent token ─────►│
     │       + confirm fingerprint          │
     │                                      │
     │  6. Store in Keychain               │
     │                                      │
```

### Subsequent Connections

1. Client loads config (host, port, fingerprint)
2. Client loads token from Keychain
3. TLS handshake with certificate pinning
4. Request with `Authorization: Bearer <token>`
5. Server validates token, returns data

## Token Security

### Pairing Token (One-Time)

- **Purpose**: Initial device pairing only
- **Lifetime**: 5 minutes
- **Usage**: Single use, invalidated after exchange
- **Generation**: Cryptographically random, 256 bits

### Access Token (Permanent)

- **Purpose**: Ongoing API authentication
- **Lifetime**: Until manually revoked
- **Storage**: macOS/iOS Keychain only
- **Protection**: `kSecAttrAccessibleWhenUnlocked`

### Token Never Stored In:

- Config files
- Environment variables
- Logs
- Memory dumps (zeroed after use)

## Local Network Restriction

### Allowed Hosts

The server and client validate that connections are local-only:

```swift
static func isPrivateNetwork(_ host: String) -> Bool {
    // IPv4 private ranges (RFC 1918)
    if host.hasPrefix("192.168.") { return true }
    if host.hasPrefix("10.") { return true }
    if host.hasPrefix("172.") {
        // 172.16.0.0 - 172.31.255.255
        let parts = host.split(separator: ".")
        if parts.count >= 2, let second = Int(parts[1]) {
            return second >= 16 && second <= 31
        }
    }
    
    // Localhost
    if host == "localhost" { return true }
    if host == "127.0.0.1" { return true }
    if host.hasSuffix(".local") { return true }
    
    // IPv6 loopback and link-local
    if host == "::1" { return true }
    if host.hasPrefix("fe80:") { return true }
    
    return false
}
```

### Why Local Only?

- Reduces attack surface dramatically
- No exposure to internet-based attacks
- No need for public certificates or DNS
- User maintains full control

## Audit Logging

### Logged Events

| Event | Details Captured |
|-------|------------------|
| Server started | Timestamp, port |
| Device paired | Client IP, fingerprint |
| Auth failed | Client IP, reason |
| Data fetched | Client IP, data type, record count |
| Server stopped | Timestamp |

### Log Storage

- **Location**: SwiftData (iOS)
- **Retention**: Last 1000 events
- **Access**: View in app's Logs tab
- **Export**: Available for review

### Not Logged

- Actual health data values
- Token values
- Private keys

## Certificate Management

### Generation

```swift
// On first launch, generate self-signed certificate
let privateKey = SecKeyCreateRandomKey(...)
let certificate = createSelfSignedCert(key: privateKey)

// Store in Keychain with protection
SecItemAdd([
    kSecClass: kSecClassIdentity,
    kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
    ...
])
```

### Fingerprint

- **Algorithm**: SHA-256
- **Format**: `sha256:<hex-digest>`
- **Displayed**: First 20 chars in UI for verification
- **Used**: Certificate pinning validation

## Keychain Usage

### iOS (Server)

| Item | Service | Protection |
|------|---------|------------|
| Server Identity | `org.mvneves.healthsync.identity` | AfterFirstUnlock |
| Access Token | `org.mvneves.healthsync.token` | WhenUnlocked |
| Paired Devices | `org.mvneves.healthsync.devices` | WhenUnlocked |

### macOS (Client)

| Item | Service | Protection |
|------|---------|------------|
| Access Token | `org.mvneves.healthsync.cli` | WhenUnlocked |

## Best Practices

### For Users

1. **Keep app updated**: Security fixes in updates
2. **Use secure Wi-Fi**: Avoid public networks for syncing
3. **Review audit logs**: Check for unexpected access
4. **Revoke if needed**: Reset config on suspected compromise

### Network Hygiene

1. Use WPA3/WPA2 on your Wi-Fi network
2. Disable guest network during syncing
3. Consider a separate IoT VLAN if security-conscious

## Comparison to Alternatives

| Feature | Health Sync | Cloud Services |
|---------|-------------|----------------|
| Data location | Your network | Third-party servers |
| Internet required | No | Yes |
| Account needed | No | Yes |
| End-to-end encrypted | Yes (TLS) | Varies |
| Audit trail | Local, complete | Limited/none |
| Data sovereignty | Full | Shared |

## Reporting Security Issues

Found a security vulnerability? Please:

1. **Do not** open a public issue
2. Email: [security contact]
3. Include: Steps to reproduce, impact assessment
4. Allow: 90 days for fix before disclosure

## Cryptographic Specifications

| Component | Algorithm | Key Size |
|-----------|-----------|----------|
| TLS | 1.2/1.3 | - |
| Server Key | RSA/ECDSA | 2048/P-256 |
| Token | CSPRNG | 256 bits |
| Fingerprint | SHA-256 | 256 bits |
| Keychain | AES-256-GCM | 256 bits |
