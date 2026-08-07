import Foundation

enum IconCatalog {
    static let icons: [DemoIcon] = loadIcons()

    struct DemoIcon: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let data: Data
    }

    private static var resourceBundle: Bundle {
        #if SWIFT_PACKAGE
        .module
        #else
        .main
        #endif
    }

    private static func loadIcons() -> [DemoIcon] {
        let bundle = resourceBundle
        var urls: [URL] = []

        if let root = bundle.url(forResource: "Icons", withExtension: nil) {
            if let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil
            ) {
                for case let url as URL in enumerator where url.pathExtension.lowercased() == "svg" {
                    urls.append(url)
                }
            }
        }

        if urls.isEmpty, let resourceRoot = bundle.resourceURL {
            if let enumerator = FileManager.default.enumerator(
                at: resourceRoot,
                includingPropertiesForKeys: nil
            ) {
                for case let url as URL in enumerator where url.pathExtension.lowercased() == "svg" {
                    urls.append(url)
                }
            }
        }

        return urls
            .compactMap { url -> DemoIcon? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return DemoIcon(name: url.deletingPathExtension().lastPathComponent, data: data)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
