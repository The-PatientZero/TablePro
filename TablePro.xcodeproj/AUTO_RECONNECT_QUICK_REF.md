# 🔄 Quick Reference: Auto-Reconnect Features

## What Works Now

| Scenario | Auto-Reconnect | Detection Time | Notes |
|----------|----------------|----------------|-------|
| **VPN Disconnect → Reconnect** | ✅ YES | ~30 seconds | SSH tunnel health monitoring |
| **MySQL Server Restart** | ✅ YES | Immediate | Error-based detection |
| **PostgreSQL Server Restart** | ✅ YES | Immediate | Error-based detection |
| **Network Interruption** | ✅ YES | ~30 seconds | Requires network restoration |
| **SSH Key Expiration** | ❌ NO | N/A | Requires manual re-authentication |
| **Database Credentials Change** | ❌ NO | N/A | Requires manual reconnection |

---

## 🚀 Quick Test Commands

### Test SSH Tunnel Auto-Reconnect
```bash
# 1. Connect TablePro to database via SSH
# 2. Run this to kill SSH tunnel:
pkill -f "ssh.*60000"  # Adjust port as needed

# 3. Watch console logs in Xcode for:
# "⚠️ SSH tunnel for connection: [name] died"
# "✅ Successfully reconnected SSH tunnel for: [name]"
```

### Test Database-Level Reconnect (MySQL)
```bash
# 1. Connect TablePro to MySQL database
# 2. Restart MySQL server:
brew services restart mysql
# or
sudo systemctl restart mysql

# 3. Run a query in TablePro - should auto-reconnect
```

### Test Database-Level Reconnect (PostgreSQL)
```bash
# 1. Connect TablePro to PostgreSQL database
# 2. Restart PostgreSQL server:
brew services restart postgresql
# or
sudo systemctl restart postgresql

# 3. Run a query in TablePro - should auto-reconnect
```

---

## 🔧 Configuration Quick Reference

```swift
// File: SSHTunnelManager.swift
// Line: ~52

// Faster detection (10 seconds)
try? await Task.sleep(nanoseconds: 10_000_000_000)

// Default (30 seconds) - CURRENT
try? await Task.sleep(nanoseconds: 30_000_000_000)

// Slower, less CPU (60 seconds)
try? await Task.sleep(nanoseconds: 60_000_000_000)
```

```swift
// File: DatabaseManager.swift
// Method: handleSSHTunnelDied
// Line: ~234

// Network stabilization wait time
try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
```

---

## 📊 Error Codes Reference

### MySQL/MariaDB Connection Errors (Auto-Reconnect)
- **2006**: MySQL server has gone away
- **2013**: Lost connection to MySQL server during query
- **2055**: Lost connection to MySQL server at reading initial packet

### PostgreSQL Connection Error Patterns (Auto-Reconnect)
- "server closed the connection unexpectedly"
- "connection to server was lost"
- "no connection to the server"
- "could not send data to server"

---

## 🎯 Implementation Checklist

### For New Database Drivers

```swift
// 1. Add reconnection detection
private func isConnectionLostError(_ error: Error) -> Bool {
    // Check for specific error codes or messages
}

// 2. Add reconnect method
private func reconnect() async throws {
    // Close existing connection
    // Update status to .connecting
    // Call connect() with stored credentials
}

// 3. Wrap execute methods
private func executeWithReconnect(query: String, isRetry: Bool) async throws -> QueryResult {
    do {
        // Execute query
    } catch let error where !isRetry && isConnectionLostError(error) {
        try await reconnect()
        return try await executeWithReconnect(query: query, isRetry: true)
    }
}

// 4. Update public execute method
func execute(query: String) async throws -> QueryResult {
    try await executeWithReconnect(query: query, isRetry: false)
}
```

---

## 🐛 Debugging Tips

### Enable Verbose Logging
```swift
// In SSHTunnelManager.swift, add to checkTunnelHealth():
print("🔍 Checking \(tunnels.count) SSH tunnels...")
for (id, tunnel) in tunnels {
    print("  - Tunnel \(id): \(tunnel.process.isRunning ? "✅ alive" : "❌ dead")")
}
```

### Console Filter Keywords
Search for these in Xcode console:
- `SSH tunnel`
- `reconnect`
- `connection lost`
- `Failed to reconnect`

### Connection Status States
```swift
case .disconnected     // No connection
case .connecting       // Connecting or reconnecting
case .connected        // Successfully connected
case .error(String)    // Connection error with message
```

---

## 💡 Common Issues & Solutions

### Issue: "Auto-reconnect not working after VPN reconnect"
**Solution:** Check if VPN routing is restored. Try manual `ping` to database host.

### Issue: "SSH tunnel reconnects but queries still fail"
**Solution:** Database-level connection needs separate reconnect. Run any query to trigger it.

### Issue: "Console shows reconnection success but UI shows error"
**Solution:** UI might be caching old status. Check `DatabaseManager.status` property.

### Issue: "Reconnection works once, then fails on second disconnect"
**Solution:** Check if credentials expired or SSH key passphrase changed.

---

## 📞 Quick Support Checklist

When reporting auto-reconnect issues:

1. ✅ Database type: MySQL / MariaDB / PostgreSQL / SQLite
2. ✅ Connection method: Direct / SSH Tunnel
3. ✅ Console logs showing reconnection attempts
4. ✅ Network connectivity test results
5. ✅ VPN status during failure
6. ✅ Manual reconnection works? Yes / No

---

**Quick Links:**
- 📚 Full Documentation: `AUTO_RECONNECT_GUIDE.md`
- 🔧 Implementation: `SSHTunnelManager.swift`, `DatabaseManager.swift`
- 🗄️ Drivers: `MySQLDriver.swift`, `PostgreSQLDriver.swift`

---

**Version:** 1.0 | **Date:** February 4, 2026
