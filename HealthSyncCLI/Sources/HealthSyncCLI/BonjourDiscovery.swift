//
//  BonjourDiscovery.swift
//  HealthSyncCLI
//
//  Bonjour/mDNS service discovery for finding Health Sync servers
//  on the local network.
//

import Foundation
import Network

/// Discovers Health Sync servers on the local network using Bonjour
final class BonjourDiscovery: @unchecked Sendable {
    /// Service type for Health Sync
    private static let serviceType = "_healthsync._tcp"
    
    /// Network browser instance
    private var browser: NWBrowser?
    
    /// Discovered servers
    private var servers: [DiscoveredServer] = []
    
    /// Discovery queue
    private let queue = DispatchQueue(label: "org.mvneves.healthsync.discovery")
    
    /// Discover servers on the network
    /// - Parameter timeout: Timeout in seconds
    /// - Returns: Array of discovered servers
    func discover(timeout: TimeInterval) async -> [DiscoveredServer] {
        return await withCheckedContinuation { continuation in
            servers = []
            
            let parameters = NWParameters()
            parameters.includePeerToPeer = true
            
            let browser = NWBrowser(
                for: .bonjour(type: Self.serviceType, domain: "local"),
                using: parameters
            )
            self.browser = browser
            
            browser.stateUpdateHandler = { [weak self] state in
                switch state {
                case .failed(let error):
                    print("   Discovery error: \(error)")
                case .cancelled:
                    continuation.resume(returning: self?.servers ?? [])
                default:
                    break
                }
            }
            
            browser.browseResultsChangedHandler = { [weak self] results, changes in
                for result in results {
                    if case let .service(name, type, domain, _) = result.endpoint {
                        // Resolve the service to get host and port
                        self?.resolveService(name: name, type: type, domain: domain)
                    }
                }
            }
            
            browser.start(queue: queue)
            
            // Stop after timeout
            queue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.browser?.cancel()
            }
        }
    }
    
    /// Resolve a Bonjour service to get its host and port
    private func resolveService(name: String, type: String, domain: String) {
        let connection = NWConnection(
            to: .service(name: name, type: type, domain: domain, interface: nil),
            using: .tcp
        )
        
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                if let endpoint = connection.currentPath?.remoteEndpoint {
                    let server = self?.parseEndpoint(endpoint, name: name)
                    if let server = server {
                        DispatchQueue.main.async {
                            self?.servers.append(server)
                        }
                    }
                }
                connection.cancel()
            case .failed, .cancelled:
                break
            default:
                break
            }
        }
        
        connection.start(queue: queue)
    }
    
    /// Parse endpoint to get host and port
    private func parseEndpoint(_ endpoint: NWEndpoint, name: String) -> DiscoveredServer? {
        switch endpoint {
        case .hostPort(let host, let port):
            var hostString: String
            switch host {
            case .ipv4(let address):
                hostString = address.debugDescription
            case .ipv6(let address):
                hostString = address.debugDescription
            case .name(let hostname, _):
                hostString = hostname
            @unknown default:
                hostString = host.debugDescription
            }
            
            // Clean up the host string
            hostString = hostString.replacingOccurrences(of: "%.*", with: "", options: .regularExpression)
            
            return DiscoveredServer(
                name: name,
                host: hostString,
                port: Int(port.rawValue)
            )
        default:
            return nil
        }
    }
}
