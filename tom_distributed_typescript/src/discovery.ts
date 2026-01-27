/**
 * Network discovery utilities for finding servers.
 * 
 * Note: Full subnet scanning is only available in Node.js/Deno environments.
 * In browsers, only localhost/127.0.0.1 discovery is available.
 */

/**
 * Discovery result.
 */
export interface DiscoveryResult {
  /** The discovered URL. */
  url: string;
  
  /** Time taken to discover in milliseconds. */
  discoveryTimeMs: number;
}

/**
 * Discovery options.
 */
export interface DiscoveryOptions {
  /** The port to scan. */
  port: number;
  
  /** Connection timeout in milliseconds. Default: 2000 */
  timeout?: number;
  
  /** Health check endpoint path. Default: '/health' */
  healthPath?: string;
  
  /** Additional candidate URLs to try first. */
  additionalUrls?: string[];
}

/**
 * Exception thrown when auto-discovery fails.
 */
export class DiscoveryFailedException extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'DiscoveryFailedException';
  }
}

/**
 * Try to connect to a URL and verify it responds.
 */
async function tryConnect(
  url: string,
  healthPath: string,
  timeout: number,
): Promise<boolean> {
  try {
    const controller = new AbortController();
    const timeoutId = setTimeout(() => controller.abort(), timeout);
    
    try {
      const response = await fetch(`${url}${healthPath}`, {
        signal: controller.signal,
      });
      return response.ok || response.status === 200;
    } finally {
      clearTimeout(timeoutId);
    }
  } catch {
    return false;
  }
}

/**
 * Get local network interfaces (Node.js/Deno only).
 * Returns empty array in browsers.
 */
async function getLocalIps(): Promise<string[]> {
  const ips: string[] = [];
  
  // Try Node.js os module
  try {
    // Dynamic import to avoid bundler issues
    const os = await import('os');
    const interfaces = os.networkInterfaces();
    
    for (const name of Object.keys(interfaces)) {
      const addrs = interfaces[name];
      if (!addrs) continue;
      
      for (const addr of addrs) {
        if (addr.family === 'IPv4' && !addr.internal) {
          ips.push(addr.address);
        }
      }
    }
  } catch {
    // Not in Node.js environment
  }
  
  // Try Deno
  try {
    // @ts-ignore - Deno API
    if (typeof Deno !== 'undefined' && Deno.networkInterfaces) {
      // @ts-ignore - Deno API
      const interfaces = Deno.networkInterfaces();
      for (const iface of interfaces) {
        if (iface.family === 'IPv4' && !iface.internal) {
          ips.push(iface.address);
        }
      }
    }
  } catch {
    // Not in Deno environment
  }
  
  return ips;
}

/**
 * Extract subnet from IP address (first 3 octets).
 */
function extractSubnet(ip: string): string | null {
  const parts = ip.split('.');
  if (parts.length !== 4) return null;
  return `${parts[0]}.${parts[1]}.${parts[2]}`;
}

/**
 * Scan a subnet for servers.
 * 
 * @param subnet First 3 octets of IP (e.g., "192.168.1")
 * @param port Port to scan
 * @param healthPath Health check endpoint
 * @param timeout Connection timeout
 * @returns List of responding URLs
 */
export async function scanSubnet(
  subnet: string,
  port: number,
  healthPath: string = '/health',
  timeout: number = 500,
): Promise<string[]> {
  const found: string[] = [];
  const batchSize = 20;
  
  for (let start = 1; start < 255; start += batchSize) {
    const end = Math.min(start + batchSize, 255);
    const promises: Promise<{ url: string; ok: boolean }>[] = [];
    
    for (let i = start; i < end; i++) {
      const url = `http://${subnet}.${i}:${port}`;
      promises.push(
        tryConnect(url, healthPath, timeout).then(ok => ({ url, ok }))
      );
    }
    
    const results = await Promise.all(promises);
    for (const result of results) {
      if (result.ok) {
        found.push(result.url);
      }
    }
  }
  
  return found;
}

/**
 * Auto-discover a server.
 * 
 * Discovery order:
 * 1. Try localhost on specified port
 * 2. Try 127.0.0.1 on specified port
 * 3. Try any additional candidate URLs
 * 4. Try all local machine IP addresses (Node.js/Deno only)
 * 5. Scan all /24 subnets for each local IP (Node.js/Deno only)
 */
export async function discover(options: DiscoveryOptions): Promise<DiscoveryResult> {
  const startTime = Date.now();
  const timeout = options.timeout ?? 2000;
  const healthPath = options.healthPath ?? '/health';
  const port = options.port;
  
  // Priority candidate URLs
  const candidateUrls = [
    `http://localhost:${port}`,
    `http://127.0.0.1:${port}`,
    ...(options.additionalUrls ?? []),
  ];
  
  // Try priority candidates first
  for (const url of candidateUrls) {
    if (await tryConnect(url, healthPath, timeout)) {
      return {
        url,
        discoveryTimeMs: Date.now() - startTime,
      };
    }
  }
  
  // Get local IPs (only works in Node.js/Deno)
  const localIps = await getLocalIps();
  const subnets = new Set<string>();
  
  // Add local machine IPs
  for (const ip of localIps) {
    const url = `http://${ip}:${port}`;
    if (await tryConnect(url, healthPath, timeout)) {
      return {
        url,
        discoveryTimeMs: Date.now() - startTime,
      };
    }
    
    const subnet = extractSubnet(ip);
    if (subnet) {
      subnets.add(subnet);
    }
  }
  
  // Scan all subnets
  for (const subnet of subnets) {
    const found = await scanSubnet(subnet, port, healthPath, 500);
    if (found.length > 0) {
      return {
        url: found[0],
        discoveryTimeMs: Date.now() - startTime,
      };
    }
  }
  
  throw new DiscoveryFailedException(
    `No server found on port ${port}. Tried: ${candidateUrls.join(', ')}`
  );
}
