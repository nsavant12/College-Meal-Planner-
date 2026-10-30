import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum PhotoSource: String, Identifiable {
    case camera, library
    var id: String { rawValue }
}

struct LibraryPicker: UIViewControllerRepresentable {
    let completion: (Result<UIImage?, Error>) -> Void
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }
    static func dismantleUIViewController(_ uiViewController: PHPickerViewController, coordinator: Coordinator) {
        coordinator.cancelPendingLoad()
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (Result<UIImage?, Error>) -> Void
        private var isLoading = false
        private var isFinished = false
        private var progress: Progress?
        init(completion: @escaping (Result<UIImage?, Error>) -> Void) { self.completion = completion }
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !isFinished else { return }
            guard let provider = results.first?.itemProvider else { finish(.success(nil)); return }
            guard !isLoading else { return }
            guard provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) else {
                finish(.failure(PhotoError.unreadable))
                return
            }
            isLoading = true
            // Decode a thumbnail while the temporary file is valid. Loading a
            // full-resolution 48 MP UIImage first can exhaust a phone's memory.
            progress = provider.loadFileRepresentation(forTypeIdentifier: UTType.image.identifier) { url, error in
                let image = url.flatMap { UIImage.recognitionThumbnail(at: $0) }
                DispatchQueue.main.async {
                    if let error = error { self.finish(.failure(error)) }
                    else if let image = image { self.finish(.success(image)) }
                    else { self.finish(.failure(PhotoError.unreadable)) }
                }
            }
        }

        func cancelPendingLoad() {
            isFinished = true
            progress?.cancel()
            progress = nil
        }

        private func finish(_ result: Result<UIImage?, Error>) {
            guard !isFinished else { return }
            cancelPendingLoad()
            completion(result)
        }
    }
}

struct CameraPicker: UIViewControllerRepresentable {
    let completion: (Result<UIImage?, Error>) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let completion: (Result<UIImage?, Error>) -> Void
        init(completion: @escaping (Result<UIImage?, Error>) -> Void) { self.completion = completion }
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            guard let image = info[.originalImage] as? UIImage else { completion(.failure(PhotoError.unreadable)); return }
            completion(.success(image))
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { completion(.success(nil)) }
    }
}

enum PhotoError: LocalizedError {
    case unreadable
    var errorDescription: String? { "This photo could not be opened. Try a different photo or add the ingredient by hand." }
}
