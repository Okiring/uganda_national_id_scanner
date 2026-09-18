import Flutter
import UIKit

public class NationalIdScannerPlugin: NSObject, FlutterPlugin {
  private static let channelName = "com.uganda.scanner/national_id_scanner"

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = NationalIdScannerPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "scan" else {
      result(FlutterMethodNotImplemented)
      return
    }

    guard let controller = topViewController() else {
      result(
        FlutterError(
          code: "NO_VIEW_CONTROLLER",
          message: "Scanner requires an active iOS view controller.",
          details: nil
        )
      )
      return
    }

    let scanner = NationalIdScannerViewController()
    scanner.modalPresentationStyle = .fullScreen
    scanner.onResult = { rawValue in
      result(rawValue)
    }
    controller.present(scanner, animated: true)
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let window = scenes
      .flatMap { $0.windows }
      .first { $0.isKeyWindow }
      ?? scenes.first?.windows.first

    var top = window?.rootViewController
    while let presented = top?.presentedViewController {
      top = presented
    }
    return top
  }
}
