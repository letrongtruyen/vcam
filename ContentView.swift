import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

@main
struct VCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var isEnabled: Bool = false
    @State private var isRunning: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var errorMessage: String? = nil
    @State private var selectedMediaURL: URL? = nil

    private let rootPath = "/var/mobile/Library/Preferences/VCam"
    private let mediaDirectoryPath = "/var/mobile/Library/Preferences/VCam/input_media"
    private let configFilePath = "/var/mobile/Library/Preferences/VCam/config.plist"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Toggle("Enable VCam", isOn: $isEnabled)
                        .padding()

                    PhotosPicker(
                        selection: $selectedPhotoItem,
                        matching: .any(of: [.images, .videos]),
                        preferredItemEncoding: .current,
                        label: {
                            Text("Select Video / Image")
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                        }
                    )
                    .onChange(of: selectedPhotoItem) { newValue in
                        guard let item = newValue else { return }
                        handleSelectedPhotoPickerItem(item)
                    }

                    if let selectedMediaURL {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Selected media")
                                .font(.headline)
                            Text(selectedMediaURL.lastPathComponent)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .font(.footnote)
                    }
                }
                .padding()
            }
            .navigationTitle("VCam Control")
        }
        .onAppear {
            loadSettings()
        }
    }

    private func handleSelectedPhotoPickerItem(_ item: PhotosPickerItem) {
        Task {
            do {
                let data = try await item.loadTransferable(type: Data.self)
                guard let mediaData = data else {
                    errorMessage = "Unable to read selected media."
                    return
                }

                let supportedTypes = item.supportedContentTypes
                let mediaType = supportedTypes.contains(where: { $0.conforms(to: .movie) }) ? "video" : "image"
                let fileExtension = mediaType == "video" ? (supportedTypes.first?.preferredFilenameExtension ?? "mp4") : (supportedTypes.first?.preferredFilenameExtension ?? "png")

                let url = saveMediaToSharedFolder(data: mediaData, fileExtension: fileExtension)
                selectedMediaURL = url

                let config: [String: Any] = [
                    "enabled": true,
                    "media_type": mediaType,
                    "media_path": url.path
                ]

                saveConfig(config)
                postDarwinNotification()
                isEnabled = true
                isRunning = true
            } catch {
                errorMessage = "Failed to load selected media: \(error.localizedDescription)"
            }
        }
    }

    private func saveMediaToSharedFolder(data: Data, fileExtension: String) -> URL {
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: mediaDirectoryPath)

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            errorMessage = "Unable to create media directory: \(error.localizedDescription)"
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let fileName = "input_\(timestamp).\(fileExtension)"
        let destinationURL = folderURL.appendingPathComponent(fileName)

        do {
            try data.write(to: destinationURL)
            return destinationURL
        } catch {
            errorMessage = "Unable to save media to system directory: \(error.localizedDescription)"
            return destinationURL
        }
    }

    private func saveConfig(_ config: [String: Any]) {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath)

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            errorMessage = "Unable to create VCam config directory: \(error.localizedDescription)"
            return
        }

        let plistURL = URL(fileURLWithPath: configFilePath)
        let dict = NSDictionary(dictionary: config)
        dict.write(to: plistURL, atomically: true)
    }

    private func loadSettings() {
        let plistURL = URL(fileURLWithPath: configFilePath)
        guard let dict = NSDictionary(contentsOf: plistURL) as? [String: Any] else {
            return
        }

        if let enabled = dict["enabled"] as? Bool {
            isEnabled = enabled
            isRunning = enabled
        }

        if let mediaPath = dict["media_path"] as? String {
            let url = URL(fileURLWithPath: mediaPath)
            if FileManager.default.fileExists(atPath: url.path) {
                selectedMediaURL = url
            }
        }
    }

    private func postDarwinNotification() {
        let name = CFNotificationName(rawValue: "com.vcam.settingschanged" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            name,
            nil,
            nil,
            true
        )
    }
}
