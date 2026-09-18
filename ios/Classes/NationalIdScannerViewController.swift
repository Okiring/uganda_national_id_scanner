import AVFoundation
import UIKit
import ZXingCpp

/// Full-screen AVFoundation + ZXing-C++ PDF417 scanner for Ugandan National IDs.
final class NationalIdScannerViewController: UIViewController {
  var onResult: ((String?) -> Void)?

  private let captureSession = AVCaptureSession()
  private let previewLayer = AVCaptureVideoPreviewLayer()
  private let guideView = BarcodeGuideView()
  private let statusLabel = UILabel()
  private let closeButton = UIButton(type: .system)
  private let flashButton = UIButton(type: .system)

  private let sessionQueue = DispatchQueue(label: "com.uganda.scanner.session")
  private let decodeQueue = DispatchQueue(label: "com.uganda.scanner.decode")
  private let decodeLock = DispatchSemaphore(value: 1)

  private let reader: ZXIBarcodeReader = {
    let options = ZXIReaderOptions()
    options.tryHarder = false
    options.tryRotate = true
    options.tryInvert = true
    options.tryDownscale = true
    options.maxNumberOfSymbols = 1
    options.formats = [NSNumber(value: ZXIFormat.PDF_417.rawValue)]
    return ZXIBarcodeReader(options: options)
  }()

  private var decoding = true
  private var didFinish = false
  private var captureDevice: AVCaptureDevice?

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureUI()
    requestCameraAccessAndStart()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = view.bounds
  }

  override func viewWillDisappear(_ animated: Bool) {
    super.viewWillDisappear(animated)
    sessionQueue.async { [weak self] in
      self?.captureSession.stopRunning()
    }
  }

  private func configureUI() {
    previewLayer.session = captureSession
    previewLayer.videoGravity = .resizeAspectFill
    view.layer.addSublayer(previewLayer)

    guideView.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(guideView)

    statusLabel.text = "Hold the barcode inside the frame"
    statusLabel.textColor = .white
    statusLabel.textAlignment = .center
    statusLabel.numberOfLines = 0
    statusLabel.backgroundColor = UIColor.black.withAlphaComponent(0.7)
    statusLabel.layer.cornerRadius = 8
    statusLabel.clipsToBounds = true
    statusLabel.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(statusLabel)

    closeButton.setTitle("Close", for: .normal)
    closeButton.setTitleColor(.white, for: .normal)
    closeButton.backgroundColor = UIColor.darkGray.withAlphaComponent(0.8)
    closeButton.layer.cornerRadius = 8
    closeButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
    closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
    closeButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(closeButton)

    flashButton.setTitle("Flash", for: .normal)
    flashButton.setTitleColor(.white, for: .normal)
    flashButton.backgroundColor = UIColor.darkGray.withAlphaComponent(0.8)
    flashButton.layer.cornerRadius = 8
    flashButton.contentEdgeInsets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)
    flashButton.addTarget(self, action: #selector(flashTapped), for: .touchUpInside)
    flashButton.translatesAutoresizingMaskIntoConstraints = false
    view.addSubview(flashButton)

    NSLayoutConstraint.activate([
      guideView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      guideView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
      guideView.topAnchor.constraint(equalTo: view.topAnchor),
      guideView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

      statusLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
      statusLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      statusLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),

      closeButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
      closeButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),

      flashButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
      flashButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
    ])

    let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
    view.addGestureRecognizer(tap)
  }

  private func requestCameraAccessAndStart() {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureSession()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        DispatchQueue.main.async {
          if granted {
            self?.configureSession()
          } else {
            self?.statusLabel.text = "Camera permission is required to scan the ID."
          }
        }
      }
    default:
      statusLabel.text = "Camera permission is required to scan the ID."
    }
  }

  private func configureSession() {
    sessionQueue.async { [weak self] in
      guard let self else { return }

      self.captureSession.beginConfiguration()
      self.captureSession.sessionPreset = .high

      let discovery = AVCaptureDevice.DiscoverySession(
        deviceTypes: [
          .builtInTripleCamera,
          .builtInDualWideCamera,
          .builtInDualCamera,
          .builtInWideAngleCamera,
        ],
        mediaType: .video,
        position: .back
      )

      guard let device = discovery.devices.first,
            let input = try? AVCaptureDeviceInput(device: device),
            self.captureSession.canAddInput(input)
      else {
        DispatchQueue.main.async {
          self.statusLabel.text = "Could not start the camera. Check camera permission."
        }
        self.captureSession.commitConfiguration()
        return
      }

      self.captureDevice = device
      self.captureSession.addInput(input)

      let output = AVCaptureVideoDataOutput()
      output.alwaysDiscardsLateVideoFrames = true
      output.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      ]
      output.setSampleBufferDelegate(self, queue: self.decodeQueue)

      if self.captureSession.canAddOutput(output) {
        self.captureSession.addOutput(output)
      }

      if let connection = output.connection(with: .video), connection.isVideoOrientationSupported {
        connection.videoOrientation = .portrait
      }

      self.captureSession.commitConfiguration()
      self.captureSession.startRunning()
    }
  }

  @objc private func closeTapped() {
    finish(with: nil)
  }

  @objc private func flashTapped() {
    guard let device = captureDevice, device.hasTorch else { return }
    do {
      try device.lockForConfiguration()
      device.torchMode = device.torchMode == .on ? .off : .on
      device.unlockForConfiguration()
    } catch {
      // Ignore torch failures.
    }
  }

  @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
    guard let device = captureDevice else { return }
    let point = gesture.location(in: view)
    let devicePoint = previewLayer.captureDevicePointConverted(fromLayerPoint: point)

    do {
      try device.lockForConfiguration()
      if device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = devicePoint
        device.focusMode = .autoFocus
      }
      if device.isExposurePointOfInterestSupported {
        device.exposurePointOfInterest = devicePoint
        device.exposureMode = .autoExpose
      }
      device.unlockForConfiguration()
    } catch {
      // Ignore focus failures.
    }
  }

  private func finish(with rawValue: String?) {
    guard !didFinish else { return }
    didFinish = true
    decoding = false

    if let rawValue {
      NSLog("NationalIdScanner PDF417 received text: %@", rawValue)
    }

    dismiss(animated: true) { [weak self] in
      self?.onResult?(rawValue)
    }
  }
}

extension NationalIdScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard decoding else { return }
    guard decodeLock.wait(timeout: .now()) == .success else { return }
    defer { decodeLock.signal() }

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    do {
      let results = try reader.read(pixelBuffer)
      guard let match = results.first(where: {
        $0.format == .PDF_417 && !$0.text.isEmpty
      }) else {
        return
      }
      let text = match.text

      decoding = false
      DispatchQueue.main.async { [weak self] in
        self?.finish(with: text)
      }
    } catch {
      // Keep scanning on decode errors.
    }
  }
}

private final class BarcodeGuideView: UIView {
  private let borderLayer = CAShapeLayer()

  override init(frame: CGRect) {
    super.init(frame: frame)
    isUserInteractionEnabled = false
    borderLayer.strokeColor = UIColor.white.cgColor
    borderLayer.fillColor = UIColor.clear.cgColor
    borderLayer.lineWidth = 3
    layer.addSublayer(borderLayer)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    var guideWidth = bounds.width * 0.92
    var guideHeight = guideWidth / 2.8
    let maximumHeight = bounds.height * 0.55
    if guideHeight > maximumHeight {
      guideHeight = maximumHeight
      guideWidth = guideHeight * 2.8
    }
    let left = (bounds.width - guideWidth) / 2
    let top = (bounds.height - guideHeight) / 2
    let rect = CGRect(x: left, y: top, width: guideWidth, height: guideHeight)
    borderLayer.path = UIBezierPath(roundedRect: rect, cornerRadius: 12).cgPath
  }
}
