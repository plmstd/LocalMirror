import Foundation

enum VolumeIdentityResolver {
    static func resolve(for url: URL) throws -> VolumeIdentity {
        let resourceKeys: Set<URLResourceKey> = [
            .volumeUUIDStringKey,
            .volumeLocalizedNameKey,
            .volumeNameKey,
            .volumeIsRemovableKey
        ]
        let values = try url.resourceValues(forKeys: resourceKeys)
        let mountPath = mountPath(for: url)
        let volumeURL = URL(fileURLWithPath: mountPath)
        let displayName = values.volumeLocalizedName ?? values.volumeName ?? volumeURL.lastPathComponent
        return VolumeIdentity(
            uuid: values.volumeUUIDString,
            displayName: displayName.isEmpty ? volumeURL.lastPathComponent : displayName,
            mountPath: mountPath,
            isRemovable: values.volumeIsRemovable ?? false
        )
    }

    static func availableCapacity(for url: URL) -> Int64? {
        let resourceKeys: Set<URLResourceKey> = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: resourceKeys) else {
            return nil
        }
        if let important = values.volumeAvailableCapacityForImportantUsage {
            return Int64(important)
        }
        if let plain = values.volumeAvailableCapacity {
            return Int64(plain)
        }
        return nil
    }

    private static func mountPath(for url: URL) -> String {
        let path = url.path
        guard path.hasPrefix("/Volumes/") else {
            return "/"
        }

        let components = path.split(separator: "/")
        guard components.count >= 2 else {
            return path
        }
        return "/Volumes/" + components[1]
    }
}
