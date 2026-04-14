import Darwin
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

    static func resolveTargetCapabilities(for url: URL) throws -> TargetCapabilities {
        let mountURL = URL(fileURLWithPath: mountPath(for: url), isDirectory: true)
        let resourceKeys: Set<URLResourceKey> = [
            .volumeLocalizedFormatDescriptionKey,
            .volumeIsReadOnlyKey
        ]
        let values = try mountURL.resourceValues(forKeys: resourceKeys)
        let fileSystemType = fileSystemName(for: mountURL) ?? values.volumeLocalizedFormatDescription ?? "Unknown"
        let normalized = fileSystemType.lowercased()
        let isAPFS = normalized == "apfs" || normalized.contains("apple file system")
        return TargetCapabilities(
            fileSystemType: fileSystemType,
            isAPFS: isAPFS,
            supportsSnapshots: isAPFS,
            isReadOnly: values.volumeIsReadOnly ?? false
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

    private static func fileSystemName(for url: URL) -> String? {
        var stats = statfs()
        let result = url.path.withCString { pathPointer in
            statfs(pathPointer, &stats)
        }
        guard result == 0 else { return nil }
        return withUnsafePointer(to: &stats.f_fstypename.0) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                String(cString: $0)
            }
        }
    }
}
