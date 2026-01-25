## 0.2.0

### Unified Operation API

- **Abstract Operation class** now includes low-level methods (`cachedData`, `createCallFrame`, `deleteCallFrame`, `registerTempResource`, `unregisterTempResource`) - code no longer needs to distinguish between `LocalOperation` and `RemoteOperation`
- **Removed casts** from examples - both orchestrator and worker examples now use the abstract `Operation` type
- **Full API parity** between local and remote implementations

### Signal-Based Cleanup

- **CleanupHandler** - New singleton utility class for SIGINT/SIGTERM signal handling
- **Automatic temp resource cleanup** - Both `LocalOperation` and `RemoteOperation` register cleanup callbacks for graceful shutdown
- **Silent error handling** - Cleanup ignores missing files (may have been cleaned by another participant)
- **Local temp tracking** - Temp resources are tracked locally for signal-based cleanup even if the ledger file is unavailable

### Server Endpoints

- Added `/callframe/create` and `/callframe/delete` endpoints to `LedgerServer` for direct call frame manipulation by remote clients

## 0.1.0

- Initial release of tom_dist_ledger package
- File-based ledger implementation with lock files and backup trails
- High-level Ledger API for operation coordination
- Async simulation framework with participant implementations
