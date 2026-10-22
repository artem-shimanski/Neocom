import LiteRow
import SDEKit
import UIKit

/// The icons stored in the static data export (`iconImages`), decoded once and cached.
///
/// Only market groups have them. The PNGs are read synchronously from the database; the cache is
/// keyed by icon id alone, since the images are language-independent.
@MainActor
enum SDEIconImages {
    private static let cache = NSCache<NSNumber, UIImage>()
    /// Ids without a picture, so misses are not queried again.
    private static var missing: Set<IconID> = []

    /// The image of the first of `ids` that has one, or `nil`.
    static func image(for ids: [IconID], in database: Database?) -> UIImage? {
        for id in ids {
            if let image = image(for: id, in: database) {
                return image
            }
        }
        return nil
    }

    static func image(for id: IconID, in database: Database?) -> UIImage? {
        let key = NSNumber(value: id.rawValue)
        if let image = cache.object(forKey: key) {
            return image
        }
        guard let database, !missing.contains(id) else { return nil }
        let rows = (try? database.readSync { try $0.fetchAll(SDEQuery.iconImage(id)) }) ?? []
        guard let png = rows.first?.png, let image = UIImage(data: png) else {
            missing.insert(id)
            return nil
        }
        cache.setObject(image, forKey: key)
        return image
    }
}
