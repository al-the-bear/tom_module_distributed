# Tom Process Monitor

A distributed process management system with self-healing capabilities.

## HTTP API

The Process Monitor exposes a REST API for remote management.
By default, the main instance listens on port `19881`.

**CORS Support**: The API supports CORS for all origins (`*`) to facilitate web-based tooling.

### Endpoints

*   `GET /monitor/status`: Returns current monitor status.
*   `POST /monitor/restart`: Restarts the monitor instance.
*   `GET /processes`: List all managed processes.
*   `POST /processes`: Register a new process.
*   `POST /processes/{id}/start`: Start a process.
*   `POST /processes/{id}/stop`: Stop a process.
