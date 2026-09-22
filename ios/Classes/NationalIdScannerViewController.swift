import AVFoundation
import CoreImage
import UIKit
import ZXingCpp

/// Full-screen scanner for Ugandan National ID PDF417 barcodes.
///
/// Primary path: Apple `AVCaptureMetadataOutput` (most reliable on iOS).
/// Fallback: ZXing-C++ on video frames (ROI + full frame).
final class NationalIdScannerViewController: UIViewController {
  var onResult: ((String?) -> Void)?

  private let captureSession = AVCaptureSession()
  private let previewLayer = AVCaptureVideoPreviewLayer()
  private let guideView = BarcodeGuideView()
  private let statusLabel = UILabel()
  private let closeButton = UIButton(type: .system)
  private let flashButton = UIButton(type: .system)

  private let sessionQueue = DispatchQueue(label: "com.uganda.scanner.session")
  private let metadataQueue = DispatchQueue(label: "com.uganda.scanner.metadata")
  private let decodeQueue = DispatchQueue(label: "com.uganda.scanner.decode")
  private let decodeLock = DispatchSemaphore(value: 1)

  private let reader: ZXIBarcodeReader = {
    let options = ZXIReaderOptions()
    options.tryHarder = true
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
  private var metadataOutput: AVCaptureMetadataOutput?
  private var failedFrames = 0
  private var latestGuideRectInView: CGRect = .zero
  private var latestPreviewSize: CGSize = .zero

  override func viewDidLoad() {
    super.viewDidLoad()
    view.backgroundColor = .black
    configureUI()
    requestCameraAccessAndStart()
  }

  override func viewDidLayoutSubviews() {
    super.viewDidLayoutSubviews()
    previewLayer.frame = view.bounds
    latestPreviewSize = previewLayer.bounds.size
    latestGuideRectInView = guideView.guideRect()
    updateMetadataRectOfInterest()
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
      // Dense PDF417 on National IDs needs more pixels than 720p.
      if self.captureSession.canSetSessionPreset(.hd1920x1080) {
        self.captureSession.sessionPreset = .hd1920x1080
      } else {
        self.captureSession.sessionPreset = .high
      }

      let device =
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        ?? AVCaptureDevice.default(for: .video)

      guard let device,
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
      self.configureCameraForScanning(device)

      // Primary: Apple barcode detector.
      let metadata = AVCaptureMetadataOutput()
      if self.captureSession.canAddOutput(metadata) {
        self.captureSession.addOutput(metadata)
        metadata.setMetadataObjectsDelegate(self, queue: self.metadataQueue)
        if metadata.availableMetadataObjectTypes.contains(.pdf417) {
          metadata.metadataObjectTypes = [.pdf417]
        }
        self.metadataOutput = metadata
      }

      // Fallback: ZXing on camera frames.
      let video = AVCaptureVideoDataOutput()
      video.alwaysDiscardsLateVideoFrames = true
      video.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
      ]
      video.setSampleBufferDelegate(self, queue: self.decodeQueue)
      if self.captureSession.canAddOutput(video) {
        self.captureSession.addOutput(video)
        if let connection = video.connection(with: .video), connection.isVideoOrientationSupported {
          connection.videoOrientation = .portrait
        }
      }

      self.captureSession.commitConfiguration()
      self.captureSession.startRunning()

      DispatchQueue.main.async { [weak self] in
        self?.updateMetadataRectOfInterest()
      }
    }
  }

  private func configureCameraForScanning(_ device: AVCaptureDevice) {
    do {
      try device.lockForConfiguration()
      if device.isFocusModeSupported(.continuousAutoFocus) {
        device.focusMode = .continuousAutoFocus
      }
      if device.isExposureModeSupported(.continuousAutoExposure) {
        device.exposureMode = .continuousAutoExposure
      }
      if device.isLowLightBoostSupported {
        device.automaticallyEnablesLowLightBoostWhenAvailable = true
      }
      // Mild zoom helps dense PDF417 fill more of the sensor.
      let maxZoom = min(device.activeFormat.videoMaxZoomFactor, 3.0)
      let targetZoom = min(1.6, maxZoom)
      if targetZoom > 1.0 {
        device.videoZoomFactor = targetZoom
      }
      device.unlockForConfiguration()
    } catch {
      // Ignore configuration failures; scanning may still work.
    }
  }

  private func updateMetadataRectOfInterest() {
    guard let metadataOutput, previewLayer.bounds.width > 1 else { return }
    let guide = latestGuideRectInView == .zero ? guideView.guideRect() : latestGuideRectInView
    let converted = previewLayer.metadataOutputRectConverted(fromLayerRect: guide)
    sessionQueue.async {
      metadataOutput.rectOfInterest = converted
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

    sessionQueue.async { [weak self] in
      self?.captureSession.stopRunning()
    }

    dismiss(animated: true) { [weak self] in
      self?.onResult?(rawValue)
    }
  }

  private func mapGuideToBuffer(width: Int, height: Int) -> CGRect? {
    let viewWidth = latestPreviewSize.width
    let viewHeight = latestPreviewSize.height
    let viewRoi = latestGuideRectInView
    guard viewWidth > 1, viewHeight > 1, width > 0, height > 0, viewRoi.width > 1 else {
      return nil
    }

    let bufferWidth = CGFloat(width)
    let bufferHeight = CGFloat(height)

    var coveredWidth = bufferWidth
    var coveredHeight = bufferHeight
    if viewWidth * coveredWidth < viewHeight * coveredHeight {
      coveredWidth = coveredWidth * viewHeight / coveredHeight
      coveredHeight = viewHeight
    } else {
      coveredHeight = coveredHeight * viewWidth / coveredWidth
      coveredWidth = viewWidth
    }

    let previewRect = CGRect(
      x: (viewWidth - coveredWidth) / 2,
      y: (viewHeight - coveredHeight) / 2,
      width: coveredWidth,
      height: coveredHeight
    )
    guard previewRect.width > 0, previewRect.height > 0 else { return nil }

    let normalized = CGRect(
      x: (viewRoi.minX - previewRect.minX) / previewRect.width,
      y: (viewRoi.minY - previewRect.minY) / previewRect.height,
      width: viewRoi.width / previewRect.width,
      height: viewRoi.height / previewRect.height
    )

    var mapped = CGRect(
      x: normalized.minX * bufferWidth,
      y: normalized.minY * bufferHeight,
      width: normalized.width * bufferWidth,
      height: normalized.height * bufferHeight
    )

    mapped = mapped.integral.intersection(CGRect(x: 0, y: 0, width: bufferWidth, height: bufferHeight))
    guard mapped.width >= 8, mapped.height >= 8 else { return nil }
    return mapped
  }

  private func croppedImage(from pixelBuffer: CVPixelBuffer, roi: CGRect) -> CIImage {
    let full = CIImage(cvPixelBuffer: pixelBuffer)
    let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
    let ciRoi = CGRect(
      x: roi.minX,
      y: height - roi.maxY,
      width: roi.width,
      height: roi.height
    )
    let cropped = full.cropped(to: ciRoi)
    return cropped.transformed(
      by: CGAffineTransform(translationX: -cropped.extent.origin.x, y: -cropped.extent.origin.y)
    )
  }
}

extension NationalIdScannerViewController: AVCaptureMetadataOutputObjectsDelegate {
  func metadataOutput(
    _ output: AVCaptureMetadataOutput,
    didOutput metadataObjects: [AVMetadataObject],
    from connection: AVCaptureConnection
  ) {
    guard decoding else { return }

    for object in metadataObjects {
      guard let code = object as? AVMetadataMachineReadableCodeObject,
            code.type == .pdf417,
            let value = code.stringValue,
            !value.isEmpty
      else {
        continue
      }

      decoding = false
      DispatchQueue.main.async { [weak self] in
        self?.finish(with: value)
      }
      return
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
    // Throttle ZXing — Apple metadata is primary; ZXing is expensive.
    guard failedFrames % 3 == 0 else {
      failedFrames += 1
      return
    }
    guard decodeLock.wait(timeout: .now()) == .success else { return }
    defer { decodeLock.signal() }

    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let roi = mapGuideToBuffer(width: width, height: height)
    let useRoi = (failedFrames % 6 == 0) && roi != nil

    do {
      let results: [ZXIResult]
      if useRoi, let roi {
        results = try reader.read(croppedImage(from: pixelBuffer, roi: roi))
      } else {
        results = try reader.read(pixelBuffer)
      }

      guard let match = results.first(where: {
        $0.format == .PDF_417 && !$0.text.isEmpty
      }) else {
        failedFrames += 1
        return
      }

      decoding = false
      let text = match.text
      DispatchQueue.main.async { [weak self] in
        self?.finish(with: text)
      }
    } catch {
      failedFrames += 1
    }
  }
}

private final class BarcodeGuideView: UIView {
  private let borderLayer = CAShapeLayer()
  private var cachedGuideRect: CGRect = .zero

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

  func guideRect() -> CGRect {
    if cachedGuideRect == .zero {
      updateGuideRect()
    }
    return cachedGuideRect
  }

  private func updateGuideRect() {
    var guideWidth = bounds.width * 0.92
    var guideHeight = guideWidth / 2.8
    let maximumHeight = bounds.height * 0.55
    if guideHeight > maximumHeight {
      guideHeight = maximumHeight
      guideWidth = guideHeight * 2.8
    }
    let left = (bounds.width - guideWidth) / 2
    let top = (bounds.height - guideHeight) / 2
    cachedGuideRect = CGRect(x: left, y: top, width: guideWidth, height: guideHeight)
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    updateGuideRect()
    borderLayer.path = UIBezierPath(roundedRect: cachedGuideRect, cornerRadius: 12).cgPath
  }
}
