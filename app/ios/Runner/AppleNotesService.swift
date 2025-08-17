import Foundation
import UIKit
import Flutter

/// Native service for interacting with Apple Notes via Flutter.
///
/// Handles two methods invoked from Dart: `shareToNotes` to present the
/// native share sheet pre‑filled with the action item content, and
/// `isNotesAppAvailable` to determine if the Notes app is installed on the
/// device. All UI operations occur on the main thread.
class AppleNotesService {
    func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "shareToNotes":
            shareToNotes(call: call, result: result)
        case "isNotesAppAvailable":
            isNotesAppAvailable(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    private func shareToNotes(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let content = args["content"] as? String else {
            result(FlutterError(code: "INVALID_ARGUMENTS",
                                message: "Invalid arguments for shareToNotes",
                                details: nil))
            return
        }
        
        DispatchQueue.main.async {
            let activityViewController = UIActivityViewController(activityItems: [content], applicationActivities: nil)
            activityViewController.completionWithItemsHandler = { _, completed, _, error in
                if let error = error {
                    result(FlutterError(code: "SHARE_FAILED", message: error.localizedDescription, details: nil))
                } else {
                    result(completed)
                }
            }
            if let controller = UIApplication.shared.keyWindow?.rootViewController {
                controller.present(activityViewController, animated: true)
            } else {
                result(false)
            }
        }
    }
    
    private func isNotesAppAvailable(result: @escaping FlutterResult) {
        guard let url = URL(string: "mobilenotes://") else {
            result(false)
            return
        }
        result(UIApplication.shared.canOpenURL(url))
    }
}