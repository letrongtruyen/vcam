import SwiftUI
import PhotosUI
import AVKit
import Foundation
import CoreFoundation
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var isEnabled: Bool = false
    @State private var isRunning: Bool = false
    @State private var mediaType: String = "image"
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var previewURL: URL?
    @State private var statusMessage: String = "Stopped"
    @State private var errorMessage: String?

    private let vcamRootPath = "/var/mobile/Library/Preferences/VCam"
    private let mediaDirectoryPath = "/var/mobile/Library/Preferences/VCam/input_media"
    private let configFilePath = "/var/mobile/Library/Preferences/VCam/config.plist"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    HeaderCardView(
                        title: "Virtual Camera",
                        subtitle: "Control Panel",
                        statusText: statusMessage,
                        isRunning: isRunning,
                        accentColor: isRunning ? .green : .red
                    )

                    VStack(spacing: 16) {
                        HStack {
                            Text("VCam")
                                .font(.headline)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isEnabled },
                                set: { newValue in
                                    isEnabled = newValue
                                    isRunning = newValue
                                    statusMessage = newValue ? "Running" : "Stopped"
                                    saveSettings()
                                }
                            ))
                            .labelsHidden()
                            .toggleStyle(SwitchToggleStyle(tint: .green))
                        }
                        .padding(.vertical, 4)

                        HStack(spacing: 12) {
                            ActionButton(
                                title: "Start Camera",
                                color: .green,
                                icon: "camera.fill"
                            ) {
                                startCamera()
                            }

                            ActionButton(
                                title: "Stop Camera",
                                color: .red,
                                icon: "camera.fill"
                            ) {
                                stopCamera()
                            }
                        }
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 14) {
                        Label("Source Media", systemImage: "photo.on.rectangle.angled")
                            .font(.headline)

                        PhotosPicker(
                            selection: $selectedPhotoItem,
                            matching: .any(of: [.images, .videos]),
                            preferredItemEncoding: .current,
                            label: {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Choose Photo or Video")
                                    Spacer()
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.secondarySystemFill))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        )
                        .onChange(of: selectedPhotoItem) { newValue in
                            guard let item = newValue else { return }
                            handleSelectedPhotoPickerItem(item)
                        }

                        if let previewURL {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Preview")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.secondary)

                                PreviewMediaView(url: previewURL, mediaType: mediaType)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 220)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .cardStyle()

                    VStack(alignment: .leading, spacing: 12) {
                        Label("System & Storage", systemImage: "internaldrive")
                            .font(.headline)

                        InfoRow(label: "Media folder", value: mediaDirectoryPath)
                        InfoRow(label: "Config file", value: configFilePath)
                        InfoRow(label: "Notification", value: "com.vcam.settingschanged")
                    }
                    .cardStyle()
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("VCam Control")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear {
            loadSettings()
        }
    }

    private func startCamera() {
        isEnabled = true
        isRunning = true
        statusMessage = "Running"
        saveSettings()
    }

    private func stopCamera() {
        isEnabled = false
        isRunning = false
        statusMessage = "Stopped"
        saveSettings()
    }

    private func saveSettings() {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: vcamRootPath)

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            errorMessage = "Unable to create VCam directory: \(error.localizedDescription)"
            return
        }

        let config: [String: Any] = [
            "enabled": isEnabled,
            "media_type": mediaType
        ]

        let plistURL = URL(fileURLWithPath: configFilePath)
        let dict = NSDictionary(dictionary: config)
        dict.write(to: plistURL, atomically: true)

        postDarwinNotification()
    }

    private func loadSettings() {
        let fileURL = URL(fileURLWithPath: configFilePath)
        guard let dict = NSDictionary(contentsOf: fileURL) as? [String: Any] else { return }

        if let enabled = dict["enabled"] as? Bool {
            isEnabled = enabled
            isRunning = enabled
            statusMessage = enabled ? "Running" : "Stopped"
        }

        if let savedMediaType = dict["media_type"] as? String {
            mediaType = savedMediaType
        }

        if let mediaPath = dict["media_path"] as? String {
            let candidateURL = URL(fileURLWithPath: mediaPath)
            if FileManager.default.fileExists(atPath: candidateURL.path) {
                previewURL = candidateURL
            }
        }
    }

    private func handleSelectedPhotoPickerItem(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    errorMessage = "Unable to load selected media."
                    return
                }

                let contentType = item.supportedContentTypes.first
                let candidateType = (contentType?.conforms(to: .movie) == true) ? "video" : "image"
                let fileExtension = resolvedFileExtension(for: contentType, mediaType: candidateType)

                let fileURL = saveMediaToSystemFolder(data: data, fileExtension: fileExtension)
                previewURL = fileURL
                mediaType = candidateType
                isEnabled = true
                isRunning = true
                statusMessage = "Running"

                let config: [String: Any] = [
                    "enabled": true,
                    "media_type": candidateType,
                    "media_path": fileURL.path
                ]

                let directoryURL = URL(fileURLWithPath: vcamRootPath)
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true, attributes: nil)

                let plistURL = URL(fileURLWithPath: configFilePath)
                let dict = NSDictionary(dictionary: config)
                dict.write(to: plistURL, atomically: true)

                postDarwinNotification()
            } catch {
                errorMessage = "Failed to process selection: \(error.localizedDescription)"
            }
        }
    }

    private func saveMediaToSystemFolder(data: Data, fileExtension: String) -> URL {
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: mediaDirectoryPath)

        try? fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)

        let fileName = "input_\(Int(Date().timeIntervalSince1970 * 1000)).\(fileExtension)"
        let destinationURL = folderURL.appendingPathComponent(fileName)

        do {
            try data.write(to: destinationURL)
        } catch {
            errorMessage = "Failed to save media to system folder: \(error.localizedDescription)"
        }

        return destinationURL
    }

    private func resolvedFileExtension(for contentType: UTType?, mediaType: String) -> String {
        if mediaType == "video" {
            return contentType?.preferredFilenameExtension ?? "mp4"
        }

        return contentType?.preferredFilenameExtension ?? "png"
    }

    private func postDarwinNotification() {
        let notificationName = CFNotificationName(rawValue: "com.vcam.settingschanged" as CFString)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            notificationName,
            nil,
            nil,
            true
        )
    }
}

private struct HeaderCardView: View {
    let title: String
    let subtitle: String
    let statusText: String
    let isRunning: Bool
    let accentColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.bold))
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(isRunning ? Color.green : Color.red)
                        .frame(width: 10, height: 10)
                        .shadow(color: accentColor.opacity(0.7), radius: 6)

                    Text(statusText)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isRunning ? .green : .red)
                }
            }
        }
        .cardStyle()
    }
}

private struct ActionButton: View {
    let title: String
    let color: Color
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .foregroundStyle(.white)
            .font(.headline)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

private struct PreviewMediaView: View {
    let url: URL
    let mediaType: String

    var body: some View {
        Group {
            if mediaType == "video" {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        Image(systemName: "photo.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.secondary)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 2)
    }
}

#Preview {
    ContentView()
}
