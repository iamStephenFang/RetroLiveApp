@preconcurrency import Foundation

@MainActor
final class DeviceDiscovery: NSObject, ObservableObject {
    @Published private(set) var cameras: [DiscoveredCamera] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private var browser: NetServiceBrowser?
    private var services: [String: NetService] = [:]

    override init() {
        super.init()
    }

    func start() {
        guard !isSearching else { return }
        errorMessage = nil
        cameras = []
        services = [:]
        isSearching = true
        let browser = NetServiceBrowser()
        browser.delegate = self
        self.browser = browser
        browser.searchForServices(ofType: "_retrolive._tcp.", inDomain: "local.")
    }

    func stop() {
        let stoppedBrowser = browser
        browser = nil
        stoppedBrowser?.delegate = nil
        stoppedBrowser?.stop()
        services.values.forEach {
            $0.delegate = nil
            $0.stop()
        }
        services = [:]
        cameras = []
        isSearching = false
        errorMessage = nil
    }

    private func resolved(_ service: NetService) {
        guard let host = service.hostName, service.port > 0 else { return }
        let camera = DiscoveredCamera(
            id: "\(service.name)|\(host)|\(service.port)",
            name: service.name,
            host: host,
            port: service.port
        )
        cameras.removeAll { $0.name == service.name }
        cameras.append(camera)
        cameras.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

extension DeviceDiscovery: @preconcurrency NetServiceBrowserDelegate {
    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didFind service: NetService,
        moreComing: Bool
    ) {
        guard browser === self.browser else { return }
        services[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 8)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        guard browser === self.browser else { return }
        services.removeValue(forKey: service.name)
        cameras.removeAll { $0.name == service.name }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        guard browser === self.browser else { return }
        isSearching = false
        errorMessage = L10n.format("discovery.search_failed", String(describing: errorDict))
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        guard browser === self.browser else { return }
        isSearching = false
    }
}

extension DeviceDiscovery: @preconcurrency NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        guard services[sender.name] === sender else { return }
        resolved(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        guard services[sender.name] === sender else { return }
        services.removeValue(forKey: sender.name)
        errorMessage = L10n.format("discovery.resolve_failed", sender.name, String(describing: errorDict))
    }
}
