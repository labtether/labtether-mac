import Foundation

enum ConsoleURLBuilder {
    private static let pathSegmentAllowed: CharacterSet = {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        return allowed
    }()

    static func nodeURL(base: URL, assetID: String) -> URL? {
        let trimmedAssetID = assetID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedAssetID.isEmpty,
              var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let encodedAssetID = trimmedAssetID.addingPercentEncoding(withAllowedCharacters: pathSegmentAllowed) ?? trimmedAssetID
        let path = [basePath, "nodes", encodedAssetID]
            .filter { !$0.isEmpty }
            .joined(separator: "/")
        components.percentEncodedPath = "/\(path)"
        components.percentEncodedQuery = nil
        components.percentEncodedFragment = nil
        return components.url
    }
}
