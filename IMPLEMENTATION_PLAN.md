# Throttle 3 - SSH/WebDAV/Tunnel Implementation Plan

**Date:** 26 December 2025  
**Goal:** Implement SSH command execution + WebDAV file server setup with proper tunnel lifecycle management

---

## Architecture Overview

### Problem Statement
We need to:
1. Execute SSH commands remotely (to setup/manage dufs file server)
2. Manage multiple SSH tunnels (SSH, WebDAV, Transmission RPC)
3. Handle Tailscale on iOS (SOCKS5 proxy) vs macOS (direct connection)
4. Coordinate tunnel lifecycle with app state and server selection

### Solution Architecture

```
ConnectionManager (Master Coordinator)
├─ Waits for Tailscale (iOS only, after CloudKit sync)
├─ Creates all tunnels for selected server
├─ Publishes tunnel ports for consumers
└─ Handles lifecycle (gateway change, ScenePhase)

SSHManager (Command Execution)
├─ Uses SshLib framework (extended with ExecuteCommand)
├─ Checks ConnectionManager for tunnel port
└─ Connects via SOCKS5 (iOS) or direct (macOS)

SFTPManager (Existing - File Operations)
├─ Uses MFT framework for SFTP
├─ Same tunnel awareness as SSHManager
└─ Already implemented

TunnelManager (Existing - Enhanced)
├─ Uses SshLib for SSH tunnels
├─ Add: stopAllTunnels() method
└─ Supports multiple simultaneous tunnels
```

---

## Components to Build/Modify

### 1. Extended SshLib Framework
**Location:** `/Users/stephengrigg/Documents/ssh-go-master`  
**Changes Made:**
- ✅ Added `exec.go` with `ExecuteCommand()` and `ExecuteCommandBackground()`
- ✅ Added `socks5_dialer.go` for SOCKS5 proxy support (golang.org/x/net/proxy)
- ✅ Rebuilt both iOS and macOS xcframeworks with new functions
- ✅ Copied updated frameworks to Xcode project

**New Functions Available:**
- `SshlibExecuteCommand()` - Execute command and wait for output
- `SshlibExecuteCommandBackground()` - Fire and forget for long-running services

**Status:** ✅ COMPLETE - No Homebrew dependencies, works on both platforms

---

### 2. SSHManager (NEW)
**File:** ✅ `Throttle 3/Connection/SSHManager.swift`

**Purpose:** Wrapper around SshLib's SSH execution functions

**Key Methods:**
- `executeCommand(server:command:timeout:useTunnel:) async throws -> String`
  - Executes command and waits for output
  - Automatically loads credentials from Keychain
  - Handles SOCKS5 proxy on iOS with Tailscale
  - Returns stdout as string
  
- `executeCommandBackground(server:command:useTunnel:) async throws`
  - Fire-and-forget for long-running services (like dufs)
  - Doesn't wait for command completion
  - Useful for starting background daemons

**Platform Handling:**
- **iOS:** Uses Tailscale's SOCKS5 proxy if `server.useTailscale == true`
- **macOS:** Direct connection to tailnet hostname

**Credential Loading:**
- Key-based: Loads private key from Keychain `{serverID}-ssh-key`
- Password: Loads password from Keychain `{serverID}-ssh-password`

**Status:** ✅ COMPLETE

---

### 3. ConnectionManager (NEW)
**File:** `Throttle 3/Connection/ConnectionManager.swift`

**Purpose:** Master coordinator for all tunnel lifecycle management

**Properties:**
```swift
@Published private(set) var currentServer: Servers?
@Published private(set) var isConnecting: Bool = false
@Published private(set) var isConnected: Bool = false
@Published private(set) var errorMessage: String?

// Tunnel ports (nil = use direct connection)
@Published private(set) var sshTunnelPort: Int?      // 8022
@Published private(set) var rpcTunnelPort: Int?      // 9091
@Published private(set) var webdavTunnelPort: Int?   // 8080
```

**Key Methods:**
- `connect(to server: Servers) async throws`
  - Wait for Tailscale (iOS + useTailscale)
  - Create SSH tunnel (if sshOn || serveFilesOverTunnels)
  - Create WebDAV tunnel (if serveFilesOverTunnels)
  - Create RPC tunnel (if tunnelWebOverSSH)
  - Save ServerToStart to UserDefaults
  
- `disconnect() async`
  - Stop all tunnels via TunnelManager
  - Clear all port references
  - Clear currentServer

- `reconnectIfNeeded(server: Servers) async throws`
  - Check if already connected to this server
  - If not, call connect()

- `ensureTailscaleConnected() async throws` (private, iOS only)
  - Poll TailscaleManager.shared.isConnected
  - Timeout after 30 seconds
  - Throw error if fails

**Tunnel Configuration:**
- SSH Tunnel: `remoteHost:22 → localhost:8022`
- WebDAV Tunnel: `remoteHost:8080 → localhost:8080`
- RPC Tunnel: `remoteHost:serverPort → localhost:9091`

**Error Handling:**
```swift
enum ConnectionError: LocalizedError {
    case tailscaleTimeout
    case tailscaleFailed(String)
    case tunnelFailed(String)
    case credentialsNotFound
}
```

---

### 4. TunnelManager Enhancements (MODIFY EXISTING)
**File:** `Throttle 3/Connection/TunnelManager.swift`

**Add Methods:**
```swift
private var activeTunnels: [String: Any] = [:] // Track active tunnels

func stopAllTunnels() async {
    // Stop all active tunnels
    // SshLib doesn't expose stop - may need workaround
    // For now: clear references and let connections timeout
    activeTunnels.removeAll()
    localPort = nil
    isActive = false
}

func stopTunnel(localPort: Int) async {
    // Stop specific tunnel
    activeTunnels.removeValue(forKey: "\(localPort)")
}
```

**Note:** SshLib may not expose tunnel stop. Alternative: track process and kill, or accept tunnels live until app restart.

---

### 5. UI Components (NEW)

#### ConnectingView (iOS)
**File:** `Throttle 3/Views/Sheets/ConnectingView.swift`

Full-screen connecting view for iOS sidebar/detail transition.

```swift
struct ConnectingView: View {
    let server: Servers?
    @ObservedObject var tsManager = TailscaleManager.shared
    @ObservedObject var connManager = ConnectionManager.shared
    
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
            Text("Connecting to \(server?.name ?? "Server")...")
            Text(currentStep)
        }
    }
    
    var currentStep: String {
        // Return current connection step
    }
}
```

#### ConnectingBanner (macOS)
**File:** `Throttle 3/Views/Sheets/ConnectingBanner.swift`

Toast-style banner for macOS detail view.

```swift
struct ConnectingBanner: View {
    let server: Servers
    @ObservedObject var connManager = ConnectionManager.shared
    
    var body: some View {
        HStack {
            ProgressView()
            VStack(alignment: .leading) {
                Text("Connecting to \(server.name)")
                Text(currentStep)
            }
        }
        .padding()
        .background(Color.controlBackground)
    }
}
```

---

### 6. App Integration (MODIFY EXISTING)

#### Throttle_3App.swift
**Changes:**
```swift
@Environment(\.scenePhase) private var scenePhase
@State private var shouldAutoNavigate = false

var body: some Scene {
    WindowGroup {
        ContentView(shouldAutoNavigate: $shouldAutoNavigate)
            .onAppear { observeCloudKitActivity() }
            .onChange(of: hasCompletedInitialSync) { _, completed in
                if completed {
                    handleSyncComplete()
                }
            }
    }
    .onChange(of: scenePhase) { old, new in
        handleScenePhaseChange(old: old, new: new)
    }
}

private func handleSyncComplete() {
    Task {
        // Start Tailscale AFTER CloudKit sync
        if tailscaleEnabled && !TSmanager.isConnected {
            await TSmanager.connect()
        }
        
        // Trigger auto-navigation
        if ServerToStart != nil {
            await MainActor.run {
                shouldAutoNavigate = true
            }
        }
    }
}

private func handleScenePhaseChange(old: ScenePhase, new: ScenePhase) {
    switch new {
    case .active:
        // Reconnect if needed
        if let server = ConnectionManager.shared.currentServer {
            Task {
                try? await ConnectionManager.shared.reconnectIfNeeded(server: server)
            }
        }
        
    case .background:
        #if os(iOS)
        Task {
            await ConnectionManager.shared.disconnect()
        }
        #endif
        
    default:
        break
    }
}
```

#### ContentView.swift
**Changes:**
```swift
@Binding var shouldAutoNavigate: Bool
@State private var selectedServer: Servers?

var body: some View {
    NavigationSplitView {
        ServerListView(selectedServer: $selectedServer)
    } detail: {
        if let server = selectedServer {
            #if os(iOS)
            if ConnectionManager.shared.isConnecting && 
               ConnectionManager.shared.currentServer?.id == server.id {
                ConnectingView(server: server)
            } else {
                ServerDetailView(server: server)
            }
            #else
            ServerDetailView(server: server)
            #endif
        }
    }
    .onChange(of: selectedServer) { _, newServer in
        handleGatewayChange(newServer)
    }
    .onChange(of: shouldAutoNavigate) { _, should in
        if should, let serverID = ServerToStart {
            autoNavigateToServer(id: serverID)
            shouldAutoNavigate = false
        }
    }
}

private func handleGatewayChange(_ server: Servers?) {
    Task {
        if let server = server {
            try? await ConnectionManager.shared.connect(to: server)
        } else {
            await ConnectionManager.shared.disconnect()
        }
    }
}
```

#### ServerDetailView.swift
**Changes:**
```swift
#if os(macOS)
var body: some View {
    VStack(spacing: 0) {
        if ConnectionManager.shared.isConnecting && 
           ConnectionManager.shared.currentServer?.id == server.id {
            ConnectingBanner(server: server)
                .transition(.move(edge: .top).combined(with: .opacity))
        }
        
        // Existing content
        ScrollView {
            // Your server detail views
        }
    }
    .animation(.easeInOut, value: ConnectionManager.shared.isConnecting)
}
#endif
```

---

## Implementation Order

### Phase 1: Dependencies & Foundation ✅ COMPLETE
1. ✅ Extended SshLib with ExecuteCommand functions (Go code)
2. ✅ Rebuilt iOS and macOS xcframeworks
3. ✅ Copied updated frameworks to Xcode project
4. ✅ Created SSHManager.swift with SshLib wrapper

### Phase 2: Core Logic (IN PROGRESS)
5. ⏳ Create ConnectionManager.swift skeleton
6. ⏳ Implement ConnectionManager.connect()
7. ⏳ Implement ConnectionManager.disconnect()
8. ⏳ Implement ConnectionManager.ensureTailscaleConnected()
9. ⏳ Add TunnelManager.stopAllTunnels()

### Phase 3: UI Components
10. ⏳ Create ConnectingView.swift (iOS)
11. ⏳ Create ConnectingBanner.swift (macOS)

### Phase 4: Integration
12. ⏳ Update Throttle_3App.swift with ScenePhase handling
13. ⏳ Update ContentView.swift with gateway change handling
14. ⏳ Update ServerDetailView.swift with macOS banner

### Phase 5: Testing
15. ⏳ Test direct connection (macOS, no Tailscale)
16. ⏳ Test Tailscale connection (iOS)
17. ⏳ Test server switching
18. ⏳ Test background/foreground transitions
19. ⏳ Test auto-navigation on launch

---

## Testing Checklist

### Basic Connection
- [ ] macOS: Direct SSH connection works
- [ ] macOS: SSH command execution works
- [ ] iOS: Connection via Tailscale SOCKS5 proxy works
- [ ] iOS: SSH command execution through SOCKS5 works

### Tunnel Management
- [ ] Multiple tunnels created simultaneously
- [ ] SSH tunnel port published correctly
- [ ] WebDAV tunnel port published correctly
- [ ] RPC tunnel port published correctly
- [ ] Tunnels cleaned up on disconnect

### UI/UX
- [ ] iOS: ConnectingView shows during connection
- [ ] iOS: Transitions to detail view after connected
- [ ] macOS: Banner appears at top of detail view
- [ ] macOS: Banner disappears after connected
- [ ] Progress messages accurate (Tailscale, tunnels, etc.)

### Lifecycle
- [ ] Server selection triggers connection
- [ ] Server switch tears down old, creates new tunnels
- [ ] App background (iOS): tunnels torn down
- [ ] App foreground: tunnels recreated
- [ ] Auto-navigation works on launch

### Error Handling
- [ ] Tailscale timeout handled gracefully
- [ ] SSH authentication failure shows error
- [ ] Tunnel creation failure shows error
- [ ] Missing credentials shows error

---

## Key Constants & Configuration

### Tunnel Ports
```swift
// Static ports for simplicity
// Could be dynamic if port conflicts occur

SSH_TUNNEL_PORT = 8022      // localhost:8022 → remoteHost:22
WEBDAV_TUNNEL_PORT = 8080   // localhost:8080 → remoteHost:8080
RPC_TUNNEL_PORT = 9091      // localhost:9091 → remoteHost:9091 (or serverPort)
```

### Timeouts
```swift
TAILSCALE_TIMEOUT = 30.0 seconds
SSH_CONNECTION_TIMEOUT = 10.0 seconds
TUNNEL_CREATION_TIMEOUT = 15.0 seconds
```

### Keychain Keys
```swift
// Existing pattern:
"\(server.id.uuidString)-ssh-password"
"\(server.id.uuidString)-ssh-key"
"\(server.id.uuidString)-ssh-passphrase"
```

---

## Known Limitations & TODOs

### Current Limitations
1. **SshLib tunnel stop:** No exposed API to stop individual tunnels
   - Workaround: Accept tunnels live until app restart
   - Future: Track underlying processes and kill manually

2. **Port conflicts:** Using static ports could conflict with other apps
   - Future: Implement dynamic port allocation

3. **Tunnel health:** No active monitoring of tunnel state
   - Future: Periodic health checks, auto-reconnect

### Future Enhancements
- [ ] Dynamic port allocation
- [ ] Tunnel health monitoring
- [ ] Bandwidth usage tracking
- [ ] Connection quality indicators
- [ ] Tunnel keepalive/heartbeat

---

## File Structure Summary

```
Throttle 3/
├── Connection/
│   ├── ConnectionManager.swift       ← NEW
│   ├── SSHManager.swift              ← NEW
│   ├── ConnetionManager.swift        ← EXISTING (rename/merge?)
│   ├── SFTPManager.swift             ← EXISTING (no changes)
│   ├── SFTPProxy.swift               ← EXISTING (no changes)
│   ├── TailscaleManager.swift        ← EXISTING (no changes)
│   └── TunnelManager.swift           ← MODIFY (add stopAllTunnels)
│
├── Views/
│   └── Sheets/
│       ├── ConnectingView.swift      ← NEW (iOS)
│       └── ConnectingBanner.swift    ← NEW (macOS)
│
├── Throttle_3App.swift               ← MODIFY (ScenePhase, auto-nav)
└── ContentView.swift                 ← MODIFY (gateway handling)
```

---

## Implementation Notes

### Why This Architecture?
1. **Separation of Concerns:** Each manager has one responsibility
2. **Observable:** All state changes published via @Published
3. **Testable:** Clean async/await APIs
4. **Resilient:** Graceful timeout and error handling
5. **Platform-Aware:** iOS vs macOS handled transparently

### Why Extend SshLib Instead of Shout?
- **No Homebrew Dependencies:** Avoids libssh2/openssl code signing issues
- **Cross-Platform:** Same code works on iOS and macOS
- **Single Library:** Both tunneling (InitSSH) and command execution (ExecuteCommand) in one framework
- **Go's Excellent SSH Support:** golang.org/x/crypto/ssh is mature and well-tested
- **We Control It:** Can extend further if needed
- **SOCKS5 Support:** Built-in via golang.org/x/net/proxy for iOS/Tailscale

### Why ConnectionManager Pattern?
- **Single Source of Truth:** One place for tunnel state
- **Lifecycle Control:** Tied to app lifecycle events
- **No Race Conditions:** Tunnels created before consumers need them
- **Gateway-Driven:** Navigation changes trigger connection changes

---

## Success Criteria

Implementation is complete when:
1. ✅ SSH commands execute on remote server
2. ✅ Works on both iOS (via SOCKS5) and macOS (direct)
3. ✅ Multiple tunnels coexist peacefully
4. ✅ UI shows appropriate progress indicators
5. ✅ Server switching works smoothly
6. ✅ Background/foreground transitions handled
7. ✅ Auto-navigation on launch works
8. ✅ All error cases handled gracefully

---

## Next Steps

**Phase 1 Complete ✅**
- Extended SshLib with ExecuteCommand
- Created SSHManager wrapper

**Phase 2 Next:**
1. Create ConnectionManager.swift
2. Implement tunnel coordination logic
3. Add TunnelManager.stopAllTunnels()

**Then:**
4. Build UI components (ConnectingView, ConnectingBanner)
5. Integrate with app lifecycle
6. Test all scenarios

**Estimated Remaining Time:** 3-4 hours for implementation + testing
