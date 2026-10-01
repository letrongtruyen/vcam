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
                }
                .padding()
            }
            .navigationTitle("VCam Control")
        }
    }

    private func handleSelectedPhotoPickerItem(_ item: PhotosPickerItem) {
        // Logic xử lý file chọn
    }
}
