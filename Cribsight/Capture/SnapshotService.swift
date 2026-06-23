import UIKit
import Photos

/// Saves a snapshot image to the user's photo library, requesting add-only
/// permission on first use.
enum SnapshotService {
    enum Result {
        case saved
        case denied
        case failed
    }

    static func save(_ image: UIImage, completion: @escaping (Result) -> Void) {
        func write() {
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            } completionHandler: { success, _ in
                DispatchQueue.main.async { completion(success ? .saved : .failed) }
            }
        }

        switch PHPhotoLibrary.authorizationStatus(for: .addOnly) {
        case .authorized, .limited:
            write()
        case .notDetermined:
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                if status == .authorized || status == .limited {
                    write()
                } else {
                    DispatchQueue.main.async { completion(.denied) }
                }
            }
        default:
            DispatchQueue.main.async { completion(.denied) }
        }
    }
}
