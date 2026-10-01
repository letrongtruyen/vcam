import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import UIKit

@main
struct VCamApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    @State private var isCameraEnabled: Bool = false
    @State private var isRunning: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedMediaURL: URL? = nil
    @State private var selectedMediaName: String = "Chưa có media"
    @State private var selectedMediaType: String = "image"
    @State private var errorMessage: String? = nil
    @State private var previewImage: UIImage? = nil

    private let rootPath = "/var/mobile/Library/Preferences/VCam"
    private let mediaDirectoryPath = "/var/mobile/Library/Preferences/VCam/input_media"
    private let configFilePath = "/var/mobile/Library/Preferences/VCam/config.plist"

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.10, blue: 0.18), Color(red: 0.17, green: 0.25, blue: 0.45)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("VCam Control")
                                .font(.title2.bold())
                                .foregroundStyle(.white)

                            Text("Chọn ảnh/video rồi bật camera ảo để thay thế stream camera")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 8)

                        VStack(spacing: 16) {
                            HStack {
                                Label(isRunning ? "Camera đang chạy" : "Camera đang dừng", systemImage: isRunning ? "video.fill" : "video.slash.fill")
                                    .font(.headline)
                                    .foregroundStyle(.white)

                                Spacer()

                                Toggle("", isOn: Binding(
                                    get: { isCameraEnabled },
                                    set: { newValue in
                                        if newValue {
                                            startCamera()
                                        } else {
                                            stopCamera()
                                        }
                                    }
                                ))
                                .labelsHidden()
                            }
                            .padding(14)
                            .background(Color.white.opacity(0.08))
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                            HStack(spacing: 12) {
                                Button(action: startCamera) {
                                    Label("Start Camera", systemImage: "play.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.green)

                                Button(action: stopCamera) {
                                    Label("Stop Camera", systemImage: "stop.fill")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .tint(.red)
                            }

                            PhotosPicker(
                                selection: $selectedPhotoItem,
                                matching: .any(of: [.images, .videos]),
                                preferredItemEncoding: .current,
                                label: {
                                    Label("Upload ảnh / video", systemImage: "photo.on.rectangle")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue.opacity(0.9))
                                        .foregroundColor(.white)
                                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            )
                            .onChange(of: selectedPhotoItem) { newValue in
                                guard let item = newValue else { return }
                                Task {
                                    await handleSelectedPhotoPickerItem(item)
                                }
                            }

                            if let previewImage {
                                Image(uiImage: previewImage)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: .infinity, minHeight: 220, maxHeight: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Media hiện tại")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                Text(selectedMediaName)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.white)

                                Text("Loại: \(selectedMediaType)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                            if let errorMessage {
                                Text(errorMessage)
                                    .font(.footnote)
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(16)
                        .background(Color.black.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarHidden(true)
            .onAppear {
                loadSettings()
            }
        }
    }

    private func startCamera() {
        isCameraEnabled = true
        isRunning = true
        saveConfig(enabled: true)
        postDarwinNotification()
    }

    private func stopCamera() {
        isCameraEnabled = false
        isRunning = false
        saveConfig(enabled: false)
        postDarwinNotification()
    }

    private func handleSelectedPhotoPickerItem(_ item: PhotosPickerItem) async {
        do {
            guard let mediaData = try await item.loadTransferable(type: Data.self) else {
                errorMessage = "Không thể đọc file đã chọn."
                return
            }

            let supportedTypes = item.supportedContentTypes
            let isVideo = supportedTypes.contains(where: { $0.conforms(to: .movie) })
            let mediaType = isVideo ? "video" : "image"
            let fileExtension = supportedTypes.first?.preferredFilenameExtension ?? (isVideo ? "mp4" : "png")

            let savedURL = saveMediaToSharedFolder(data: mediaData, fileExtension: fileExtension)
            selectedMediaURL = savedURL
            selectedMediaName = savedURL.lastPathComponent
            selectedMediaType = mediaType

            if let image = UIImage(contentsOfFile: savedURL.path), mediaType == "image" {
                previewImage = image
            } else {
                previewImage = nil
            }

            saveConfig(enabled: true, mediaType: mediaType, mediaPath: savedURL.path)
            isCameraEnabled = true
            isRunning = true
            postDarwinNotification()
            errorMessage = nil
        } catch {
            errorMessage = "Lỗi khi tải media: \(error.localizedDescription)"
        }
    }

    private func saveMediaToSharedFolder(data: Data, fileExtension: String) -> URL {
        let fileManager = FileManager.default
        let folderURL = URL(fileURLWithPath: mediaDirectoryPath)

        do {
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            errorMessage = "Không thể tạo thư mục media: \(error.localizedDescription)"
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let fileName = "input_\(timestamp).\(fileExtension)"
        let destinationURL = folderURL.appendingPathComponent(fileName)

        do {
            try data.write(to: destinationURL)
            return destinationURL
        } catch {
            errorMessage = "Không thể lưu media vào thư mục hệ thống: \(error.localizedDescription)"
            return destinationURL
        }
    }

    private func saveConfig(enabled: Bool, mediaType: String? = nil, mediaPath: String? = nil) {
        let fileManager = FileManager.default
        let rootURL = URL(fileURLWithPath: rootPath)

        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            errorMessage = "Không thể tạo thư mục config: \(error.localizedDescription)"
            return
        }

        let finalMediaType = mediaType ?? selectedMediaType
        let finalMediaPath = mediaPath ?? selectedMediaURL?.path ?? ""

        let config: [String: Any] = [
            "enabled": enabled,
            "media_type": finalMediaType,
            "media_path": finalMediaPath
        ]

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
            isCameraEnabled = enabled
            isRunning = enabled
        }

        if let mediaType = dict["media_type"] as? String {
            selectedMediaType = mediaType
        }

        if let mediaPath = dict["media_path"] as? String, !mediaPath.isEmpty {
            let url = URL(fileURLWithPath: mediaPath)
            if FileManager.default.fileExists(atPath: url.path) {
                selectedMediaURL = url
                selectedMediaName = url.lastPathComponent
            }

            if selectedMediaType == "image", let image = UIImage(contentsOfFile: mediaPath) {
                previewImage = image
            } else {
                previewImage = nil
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
