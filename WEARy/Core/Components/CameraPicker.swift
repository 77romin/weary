@preconcurrency import AVFoundation
import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void

    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.cameraCaptureMode = .photo
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            defer { parent.dismiss() }
            guard let image = info[.originalImage] as? UIImage,
                  let data = CameraImageEncoder.jpegData(from: image) else { return }
            parent.onCapture(data)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct OutfitCameraView: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    let onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> OutfitCameraViewController {
        OutfitCameraViewController(onCapture: onCapture, onFailure: onFailure)
    }

    func updateUIViewController(_ uiViewController: OutfitCameraViewController, context: Context) {}
}

@MainActor
final class OutfitCameraViewController: UIViewController, @preconcurrency AVCapturePhotoCaptureDelegate, PHPickerViewControllerDelegate {
    private let onCapture: (Data) -> Void
    private let onFailure: (String) -> Void
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.weary.camera.session")
    private let photoOutput = AVCapturePhotoOutput()
    private let previewLayer = AVCaptureVideoPreviewLayer()
    private var videoInput: AVCaptureDeviceInput?
    private var cameraPosition: AVCaptureDevice.Position = .back
    private var zoomButtons: [UIButton] = []
    private let zoomLevels: [CGFloat] = [0.5, 1, 2]

    init(onCapture: @escaping (Data) -> Void, onFailure: @escaping (String) -> Void) {
        self.onCapture = onCapture
        self.onFailure = onFailure
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configurePreview()
        configureControls()
        configureSession(position: cameraPosition)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        let session = session
        sessionQueue.async {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = session
        sessionQueue.async {
            if session.isRunning { session.stopRunning() }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer.frame = view.bounds
    }

    private func configurePreview() {
        previewLayer.session = session
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }

    private func configureSession(position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let videoInput { session.removeInput(videoInput) }
        guard let device = cameraDevice(position: position),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            session.commitConfiguration()
            onFailure("카메라를 준비하지 못했어요. 잠시 후 다시 시도해 주세요.")
            return
        }

        session.addInput(input)
        videoInput = input
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        session.commitConfiguration()
        setZoom(displayFactor: 1)
    }

    private func cameraDevice(position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if position == .back {
            deviceTypes = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
        } else {
            deviceTypes = [.builtInTrueDepthCamera, .builtInWideAngleCamera]
        }
        return deviceTypes.lazy.compactMap {
            AVCaptureDevice.default($0, for: .video, position: position)
        }.first
    }

    private func configureControls() {
        let guide = UIView()
        guide.translatesAutoresizingMaskIntoConstraints = false
        guide.layer.cornerRadius = 32
        guide.layer.borderWidth = 1.5
        guide.layer.borderColor = UIColor.white.withAlphaComponent(0.7).cgColor
        guide.isUserInteractionEnabled = false
        view.addSubview(guide)

        let libraryButton = controlButton(title: "사진 보관함", systemImage: "photo.on.rectangle") { [weak self] in
            self?.showPhotoLibrary()
        }
        libraryButton.accessibilityIdentifier = "capture.library"

        let flipButton = controlButton(title: nil, systemImage: "arrow.triangle.2.circlepath.camera.fill") { [weak self] in
            self?.flipCamera()
        }
        flipButton.accessibilityLabel = "전후 카메라 전환"
        flipButton.accessibilityIdentifier = "capture.flip"

        let topBar = UIStackView(arrangedSubviews: [libraryButton, UIView(), flipButton])
        topBar.axis = .horizontal
        topBar.alignment = .center
        topBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(topBar)

        let zoomStack = UIStackView()
        zoomStack.axis = .horizontal
        zoomStack.spacing = 7
        zoomStack.alignment = .center
        zoomLevels.forEach { level in
            let title = level == 0.5 ? "0.5×" : "\(Int(level))×"
            let button = zoomButton(title: title, level: level)
            zoomButtons.append(button)
            zoomStack.addArrangedSubview(button)
        }
        zoomStack.translatesAutoresizingMaskIntoConstraints = false
        zoomStack.backgroundColor = UIColor.black.withAlphaComponent(0.38)
        zoomStack.layer.cornerRadius = 21
        zoomStack.layoutMargins = UIEdgeInsets(top: 4, left: 6, bottom: 4, right: 6)
        zoomStack.isLayoutMarginsRelativeArrangement = true
        view.addSubview(zoomStack)

        let shutterButton = UIButton(type: .custom)
        shutterButton.translatesAutoresizingMaskIntoConstraints = false
        shutterButton.backgroundColor = .white
        shutterButton.layer.cornerRadius = 36
        shutterButton.layer.borderWidth = 5
        shutterButton.layer.borderColor = UIColor.black.withAlphaComponent(0.32).cgColor
        shutterButton.addAction(UIAction { [weak self] _ in self?.capturePhoto() }, for: .touchUpInside)
        shutterButton.accessibilityLabel = "착장 사진 촬영"
        shutterButton.accessibilityIdentifier = "capture.shutter"
        view.addSubview(shutterButton)

        let guideLabel = UILabel()
        guideLabel.translatesAutoresizingMaskIntoConstraints = false
        guideLabel.text = "머리 끝부터 발끝까지 모두 담아주세요\n모자와 가방도 몸에 착용해 주세요"
        guideLabel.font = .preferredFont(forTextStyle: .subheadline)
        guideLabel.textColor = .white
        guideLabel.textAlignment = .center
        guideLabel.numberOfLines = 2
        guideLabel.layer.shadowColor = UIColor.black.cgColor
        guideLabel.layer.shadowOpacity = 1
        guideLabel.layer.shadowRadius = 1
        guideLabel.layer.shadowOffset = .zero
        view.addSubview(guideLabel)

        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),

            guide.topAnchor.constraint(equalTo: topBar.bottomAnchor, constant: 28),
            guide.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            guide.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
            guide.bottomAnchor.constraint(equalTo: guideLabel.topAnchor, constant: -14),

            guideLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            guideLabel.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            guideLabel.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20),
            guideLabel.bottomAnchor.constraint(equalTo: zoomStack.topAnchor, constant: -18),

            zoomStack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            zoomStack.bottomAnchor.constraint(equalTo: shutterButton.topAnchor, constant: -16),

            shutterButton.widthAnchor.constraint(equalToConstant: 72),
            shutterButton.heightAnchor.constraint(equalToConstant: 72),
            shutterButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            shutterButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -22),
        ])
        updateZoomButtons(selectedLevel: 1)
    }

    private func controlButton(title: String?, systemImage: String, action: @escaping () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.image = UIImage(systemName: systemImage)
        configuration.imagePadding = 7
        configuration.baseForegroundColor = .white
        configuration.baseBackgroundColor = UIColor.black.withAlphaComponent(0.42)
        configuration.cornerStyle = .capsule
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }

    private func zoomButton(title: String, level: CGFloat) -> UIButton {
        var configuration = UIButton.Configuration.plain()
        configuration.title = title
        configuration.baseForegroundColor = .white
        configuration.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8)
        let button = UIButton(configuration: configuration, primaryAction: UIAction { [weak self] _ in
            self?.setZoom(displayFactor: level)
        })
        button.titleLabel?.font = .preferredFont(forTextStyle: .caption1)
        button.accessibilityIdentifier = "capture.zoom.\(title)"
        return button
    }

    private func setZoom(displayFactor: CGFloat) {
        guard let device = videoInput?.device else { return }
        let rawFactor = displayFactor / device.displayVideoZoomFactorMultiplier
        let factor = min(max(rawFactor, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
        do {
            try device.lockForConfiguration()
            device.cancelVideoZoomRamp()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
            updateZoomButtons(selectedLevel: factor * device.displayVideoZoomFactorMultiplier)
        } catch {
            onFailure("카메라 줌을 변경하지 못했어요.")
        }
    }

    private func updateZoomButtons(selectedLevel: CGFloat) {
        for (index, button) in zoomButtons.enumerated() {
            var configuration = button.configuration
            let level = zoomLevels[index]
            let multiplier = videoInput?.device.displayVideoZoomFactorMultiplier ?? 1
            let rawFactor = level / multiplier
            let minimum = videoInput?.device.minAvailableVideoZoomFactor ?? 1
            let maximum = videoInput?.device.maxAvailableVideoZoomFactor ?? 1
            let isAvailable = rawFactor >= minimum - 0.001 && rawFactor <= maximum + 0.001
            let isSelected = abs(level - selectedLevel) < 0.01
            configuration?.baseForegroundColor = isSelected ? .black : .white
            configuration?.baseBackgroundColor = isSelected ? UIColor(WEARyTheme.lime) : .clear
            configuration?.background.cornerRadius = 16
            button.configuration = configuration
            button.isEnabled = isAvailable
            button.alpha = isAvailable ? 1 : 0.35
        }
    }

    private func flipCamera() {
        cameraPosition = cameraPosition == .back ? .front : .back
        configureSession(position: cameraPosition)
    }

    private func capturePhoto() {
        guard session.isRunning,
              let connection = photoOutput.connection(with: .video),
              connection.isEnabled else {
            onFailure("카메라가 아직 준비 중이에요. 잠시 후 다시 촬영해 주세요.")
            return
        }
        if connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = cameraPosition == .front
        }
        let settings = AVCapturePhotoSettings()
        settings.photoQualityPrioritization = photoOutput.maxPhotoQualityPrioritization
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: (any Error)?
    ) {
        guard error == nil, let data = photo.fileDataRepresentation() else {
            onFailure("사진을 저장하지 못했어요. 다시 촬영해 주세요.")
            return
        }
        onCapture(data)
    }

    private func showPhotoLibrary() {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else { return }
        result.itemProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            guard let data else { return }
            Task { @MainActor [weak self] in
                guard let self,
                      let image = UIImage(data: data),
                      let encoded = CameraImageEncoder.jpegData(from: image) else {
                    self?.onFailure("선택한 사진을 불러오지 못했어요.")
                    return
                }
                self.onCapture(encoded)
            }
        }
    }
}

enum CameraAccess {
    enum Result {
        case ready
        case unavailable
        case denied
    }

    @MainActor
    static func request() async -> Result {
        if ProcessInfo.processInfo.arguments.contains("-ui-testing") {
            return .unavailable
        }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .unavailable
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .ready
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .video) ? .ready : .denied
        case .denied, .restricted:
            return .denied
        @unknown default:
            return .denied
        }
    }
}

private enum CameraImageEncoder {
    @MainActor
    static func jpegData(
        from image: UIImage,
        maxPixelDimension: CGFloat = 2_048,
        compressionQuality: CGFloat = 0.88
    ) -> Data? {
        let longestSide = max(image.size.width, image.size.height)
        guard longestSide > 0 else { return nil }

        let scale = min(1, maxPixelDimension / longestSide)
        let targetSize = CGSize(
            width: max(1, (image.size.width * scale).rounded()),
            height: max(1, (image.size.height * scale).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let normalized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return normalized.jpegData(compressionQuality: compressionQuality)
    }
}
