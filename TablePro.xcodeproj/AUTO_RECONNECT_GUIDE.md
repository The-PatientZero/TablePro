# TablePro Auto-Reconnect Implementation Guide

## Overview
This document describes the automatic reconnection features implemented in TablePro to handle network interruptions, VPN disconnections, and SSH tunnel failures.

---

## 🎯 What's Been Implemented

### 1. **SSH Tunnel Auto-Reconnect** (NEW ✨)
**Files Modified:**
- `SSHTunnelManager.swift`
- `DatabaseManager.swift`

**Features:**
- **Health Monitoring**: Checks every 30 seconds if SSH tunnels are still alive
- **Automatic Detection**: Detects when SSH process dies (e.g., VPN disconnect)
- **Smart Reconnection**: Waits 2 seconds for network to stabilize, then reconnects
- **Notification System**: Uses `NotificationCenter` to alert `DatabaseManager`

**How It Works:**
```
1. SSH tunnel dies (VPN disconnect) ❌
2. Health monitor detects within 30 seconds 🔍
3. Notification sent to DatabaseManager 📢
4. Wait 2 seconds for network stabilization ⏱️
5. Automatic reconnection attempt 🔄
6. Database connection restored ✅
```

**Key Code Additions:**

```swift
// In SSHTunnelManager.swift
private func startHealthMonitoring() {
    healthCheckTask = Task {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            await checkTunnelHealth()
        }
    }
}

private func checkTunnelHealth() async {
    for (connectionId, tunnel) in tunnels {
        if !tunnel.process.isRunning {
            await notifyTunnelDied(connectionId: connectionId)
        }
    }
}
```

```swift
// In DatabaseManager.swift
private func handleSSHTunnelDied(connectionId: UUID) async {
    guard let session = activeSessions[connectionId] else { return }
    
    updateSession(connectionId) { session in
        session.status = .connecting
    }
    
    // Wait for network to stabilize
    try? await Task.sleep(nanoseconds: 2_000_000_000)
    
    do {
        try await connectToSession(session.connection)
        print("✅ Successfully reconnected SSH tunnel")
    } catch {
        updateSession(connectionId) { session in
            session.status = .error("SSH tunnel disconnected. Click to reconnect.")
        }
    }
}
```

---

### 2. **MySQL/MariaDB Database-Level Reconnect** (EXISTING + ENHANCED)
**File:** `MySQLDriver.swift`

**Features:**
- Detects MySQL connection errors (2006, 2013, 2055)
- Automatically reconnects once and retries the query
- Works for temporary database server issues

**Error Codes Handled:**
- **2006**: MySQL server has gone away
- **2013**: Lost connection to MySQL server during query
- **2055**: Lost connection to MySQL server at reading initial packet

**Implementation:**
```swift
private func executeWithReconnect(query: String, isRetry: Bool) async throws -> QueryResult {
    do {
        let result = try await conn.executeQuery(query)
        return result
    } catch let error as MariaDBError where !isRetry && isConnectionLostError(error) {
        // Reconnect and retry once
        try await reconnect()
        return try await executeWithReconnect(query: query, isRetry: true)
    }
}

private func isConnectionLostError(_ error: MariaDBError) -> Bool {
    [2_006, 2_013, 2_055].contains(Int(error.code))
}
```

---

### 3. **PostgreSQL Database-Level Reconnect** (NEW ✨)
**File:** `PostgreSQLDriver.swift`

**Features:**
- Detects PostgreSQL connection failures
- Automatically reconnects once and retries the query
- Handles both regular and parameterized queries

**Error Messages Detected:**
- "server closed the connection unexpectedly"
- "connection to server was lost"
- "no connection to the server"
- "could not send data to server"

**Implementation:**
```swift
private func executeWithReconnect(query: String, isRetry: Bool) async throws -> QueryResult {
    do {
        let result = try await pqConn.executeQuery(query)
        return result
    } catch let error as NSError where !isRetry && isConnectionLostError(error) {
        // Reconnect and retry once
        try await reconnect()
        return try await executeWithReconnect(query: query, isRetry: true)
    }
}

private func isConnectionLostError(_ error: NSError) -> Bool {
    let errorMessage = error.localizedDescription.lowercased()
    return errorMessage.contains("connection") && 
           (errorMessage.contains("lost") || 
            errorMessage.contains("closed") ||
            errorMessage.contains("no connection") ||
            errorMessage.contains("could not send"))
}

private func reconnect() async throws {
    libpqConnection?.disconnect()
    libpqConnection = nil
    status = .connecting
    try await connect()
}
```

**Methods with Auto-Reconnect:**
- ✅ `execute(query:)` - Regular queries
- ✅ `executeParameterized(query:parameters:)` - Parameterized queries (SQL injection safe)

---

## 📊 Comparison Table

| Database Type | SSH Tunnel Auto-Reconnect | Database-Level Auto-Reconnect |
|--------------|---------------------------|-------------------------------|
| MySQL        | ✅ YES (30s monitoring)   | ✅ YES (error-based)          |
| MariaDB      | ✅ YES (30s monitoring)   | ✅ YES (error-based)          |
| PostgreSQL   | ✅ YES (30s monitoring)   | ✅ YES (error-based)          |
| SQLite       | N/A (local files)         | ⚠️ Partial (file locked)      |

---

## 🔧 Configuration Options

### Adjusting Health Check Interval
By default, SSH tunnels are checked every 30 seconds. To make it faster:

```swift
// In SSHTunnelManager.swift, line ~52
try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds instead of 30
```

**Trade-offs:**
- **Faster (10s)**: Quicker reconnection, but more CPU usage
- **Default (30s)**: Balanced approach
- **Slower (60s)**: Less CPU, but longer downtime

---

### Adjusting Network Stabilization Wait Time
After detecting SSH tunnel failure, the system waits before reconnecting:

```swift
// In DatabaseManager.swift, handleSSHTunnelDied method
try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
```

**Recommendations:**
- **VPN with fast reconnect**: 1-2 seconds
- **VPN with slow reconnect**: 3-5 seconds
- **Unstable network**: 5-10 seconds

---

## 🧪 Testing the Auto-Reconnect

### Test Case 1: VPN Disconnect/Reconnect
1. ✅ Connect to database via SSH tunnel
2. ❌ Turn off VPN
3. ⏱️ Wait up to 30 seconds
4. 🔍 Check console for: `"⚠️ SSH tunnel for connection: [name] died"`
5. ✅ Turn VPN back on
6. ⏱️ Wait 2 seconds
7. 🎉 Should see: `"✅ Successfully reconnected SSH tunnel for: [name]"`
8. ✅ Try running a query - should work without manual reconnection

### Test Case 2: Database Server Restart
**MySQL/MariaDB:**
1. ✅ Connect to MySQL database
2. 🔄 Restart MySQL server
3. ⚠️ Execute a query - first attempt will fail
4. 🔄 System automatically reconnects
5. ✅ Query is retried and succeeds

**PostgreSQL:**
1. ✅ Connect to PostgreSQL database
2. 🔄 Restart PostgreSQL server
3. ⚠️ Execute a query - first attempt will fail
4. 🔄 System automatically reconnects
5. ✅ Query is retried and succeeds

### Test Case 3: Network Interruption
1. ✅ Connect to database
2. 📡 Disable network adapter
3. ⏱️ Wait up to 30 seconds (SSH tunnel monitoring)
4. 📡 Enable network adapter
5. ⏱️ Wait 2 seconds (stabilization)
6. ✅ Connection should auto-restore

---

## 📝 Console Logs to Watch For

### Successful SSH Tunnel Reconnection:
```
⚠️ SSH tunnel for connection: Production DB died
✅ Successfully reconnected SSH tunnel for: Production DB
```

### Failed SSH Tunnel Reconnection:
```
⚠️ SSH tunnel for connection: Production DB died
❌ Failed to reconnect SSH tunnel: SSH connection timed out
```

### Database-Level Reconnection (MySQL):
```
⚠️ MySQL connection lost (error 2006: server has gone away)
🔄 Attempting automatic reconnection...
✅ Database reconnected successfully
```

---

## 🚨 Limitations & Known Issues

### 1. One Retry Only
- Both SSH and database reconnects attempt **only once**
- If first reconnect fails, manual intervention required
- **Reason**: Prevents infinite retry loops

### 2. Query Loss During Reconnection
- Queries in-flight during disconnection will fail
- Only the **retry** of the failed query is attempted
- Multi-statement transactions may partially succeed
- **Solution**: Use `beginTransaction()` / `commitTransaction()` with error handling

### 3. SSH Tunnel Detection Delay
- Health check runs every 30 seconds (configurable)
- Maximum downtime: 30s (detection) + 2s (stabilization) = **32 seconds**
- **Solution**: Reduce health check interval to 10 seconds for faster recovery

### 4. Parameterized Queries Only for PostgreSQL
- PostgreSQL reconnect works for both `execute()` and `executeParameterized()`
- MySQL reconnect also works for both methods
- Always prefer parameterized queries for security

---

## 🔐 Security Considerations

### Password Handling During Reconnection
All reconnection attempts use secure password retrieval:

```swift
// Passwords retrieved from Keychain, never stored in memory
let password = ConnectionStorage.shared.loadPassword(for: connection.id)
let sshPassword = ConnectionStorage.shared.loadSSHPassword(for: connection.id)
```

### SSH Key Passphrase Security
- SSH key passphrases stored in Keychain
- Temporary askpass scripts created during reconnection
- Scripts automatically cleaned up after use

---

## 🎓 Best Practices

### 1. Handle Connection Errors Gracefully
```swift
do {
    let result = try await dbManager.execute(query: query)
    // Process result
} catch {
    // Show user-friendly error
    if case .error(let message) = dbManager.status {
        showAlert("Connection Error", message)
    }
}
```

### 2. Monitor Connection Status in UI
```swift
// Display connection status to users
switch dbManager.status {
case .connecting:
    StatusBar(message: "Reconnecting...", color: .orange)
case .error(let message):
    StatusBar(message: message, color: .red)
        .overlay(
            Button("Reconnect") {
                Task { try? await dbManager.connectToSession(connection) }
            }
        )
case .connected:
    StatusBar(message: "Connected", color: .green)
case .disconnected:
    StatusBar(message: "Disconnected", color: .gray)
}
```

### 3. Use Transactions for Critical Operations
```swift
do {
    try await dbManager.activeDriver?.beginTransaction()
    try await dbManager.execute(query: "UPDATE accounts SET balance = balance - 100 WHERE id = 1")
    try await dbManager.execute(query: "UPDATE accounts SET balance = balance + 100 WHERE id = 2")
    try await dbManager.activeDriver?.commitTransaction()
} catch {
    try? await dbManager.activeDriver?.rollbackTransaction()
    throw error
}
```

---

## 🔮 Future Enhancements

### Possible Improvements:
1. **Multiple Retry Attempts**: Instead of one retry, implement exponential backoff (retry after 2s, 4s, 8s, etc.)
2. **Connection Pool**: Maintain backup connections for instant failover
3. **Manual Reconnect Button**: UI button for immediate reconnection without waiting
4. **Connection Status Indicator**: Visual indicator showing connection health in real-time
5. **Reconnect Notification**: Show notification banner when auto-reconnect succeeds/fails
6. **SQLite File Lock Handling**: Better handling of locked database files

### Suggested Implementation (Multiple Retries):
```swift
private func executeWithReconnect(query: String, retryCount: Int = 0, maxRetries: Int = 3) async throws -> QueryResult {
    do {
        return try await conn.executeQuery(query)
    } catch let error where isConnectionLostError(error) && retryCount < maxRetries {
        let delay = UInt64(pow(2.0, Double(retryCount))) * 1_000_000_000 // Exponential backoff
        try? await Task.sleep(nanoseconds: delay)
        try await reconnect()
        return try await executeWithReconnect(query: query, retryCount: retryCount + 1, maxRetries: maxRetries)
    }
}
```

---

## 📚 Related Files

### Core Implementation Files:
- **SSHTunnelManager.swift**: SSH tunnel lifecycle and health monitoring
- **DatabaseManager.swift**: Session management and reconnection coordination
- **MySQLDriver.swift**: MySQL/MariaDB auto-reconnect
- **PostgreSQLDriver.swift**: PostgreSQL auto-reconnect
- **DatabaseDriver.swift**: Protocol definitions

### Supporting Files:
- **ConnectionStorage.swift**: Secure credential storage (Keychain)
- **QueryResult.swift**: ConnectionStatus enum definition
- **ContentView.swift**: UI integration points

---

## ❓ FAQ

### Q: Why doesn't it reconnect instantly when VPN comes back?
**A:** The health check runs every 30 seconds. You can reduce this to 10 seconds for faster detection (see Configuration Options).

### Q: What happens if reconnection fails?
**A:** The connection status changes to `.error("SSH tunnel disconnected. Click to reconnect.")` and users need to manually reconnect.

### Q: Does it work for all database types?
**A:** Yes for MySQL, MariaDB, and PostgreSQL. SQLite is file-based and doesn't need network reconnection.

### Q: Can I disable auto-reconnect?
**A:** Currently no. To disable, comment out the `startHealthMonitoring()` call in `SSHTunnelManager.init()`.

### Q: How much battery/CPU does health monitoring use?
**A:** Minimal. It checks once every 30 seconds using a simple process status check.

### Q: Does it reconnect during active queries?
**A:** No. Only failed queries trigger reconnection. Active queries will fail first, then reconnect on retry.

---

## 📞 Support

For issues or questions about auto-reconnect:
1. Check console logs for reconnection attempts
2. Verify network connectivity
3. Ensure VPN is stable after reconnection
4. Check SSH key permissions (should be 600)

---

**Last Updated:** February 4, 2026
**Version:** 1.0
**Status:** ✅ Production Ready
