@preconcurrency import Foundation

@MainActor
final class DeviceDiscovery: NSObject, ObservableObject {
    @Published private(set) var cameras: [DiscoveredCamera] = []
    @Published private(set) var isSearching = false
    @Published private(set) var errorMessage: String?

    private let browser = NetServiceBrowser()
    private var services: [String: NetService] = [:]

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() {
        guard !isSearching else { return }
        errorMessage = nil
        cameras = []
        services = [:]
        isSearching = true
        browser.searchForServices(ofType: "_retrolive._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        services.values.forEach { $0.stop() }
        isSearching = false
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
        services[service.name] = service
        service.delegate = self
        service.resolve(withTimeout: 8)
    }

    func netServiceBrowser(
        _ browser: NetServiceBrowser,
        didRemove service: NetService,
        moreComing: Bool
    ) {
        services.removeValue(forKey: service.name)
        cameras.removeAll { $0.name == service.name }
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didNotSearch errorDict: [String: NSNumber]) {
        isSearching = false
        errorMessage = "无法搜索局域网设备（\(errorDict)）。"
    }

    func netServiceBrowserDidStopSearch(_ browser: NetServiceBrowser) {
        isSearching = false
    }
}

extension DeviceDiscovery: @preconcurrency NetServiceDelegate {
    func netServiceDidResolveAddress(_ sender: NetService) {
        resolved(sender)
    }

    func netService(_ sender: NetService, didNotResolve errorDict: [String: NSNumber]) {
        services.removeValue(forKey: sender.name)
        errorMessage = "无法解析 \(sender.name)（\(errorDict)）。"
    }
}
