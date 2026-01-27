/**
 * Jest setup file to polyfill fetch for Node.js environment.
 * This ensures the TypeScript clients work in Jest tests.
 */

// Import cross-fetch to polyfill global fetch
import fetch, { Headers, Request, Response } from 'cross-fetch';

// Polyfill global fetch
globalThis.fetch = fetch as any;
globalThis.Headers = Headers as any;
globalThis.Request = Request as any;
globalThis.Response = Response as any;
