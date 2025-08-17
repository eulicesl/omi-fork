import UIKit
import Flutter
import UserNotifications
import app_links

/// Custom AppDelegate that registers native channels for Apple Reminders,
/// Apple Notes and Apple Calendar integrations.
///
/// This file is based off the upstream `AppDelegate.swift` but extends it to
/// include two additional method channels for Notes and Calendar. These
/// channels forward calls to the corresponding service classes defined in
/// `AppleNotesService.swift` and `AppleCalendarService.swift`.
@main
@objc class AppDelegate: FlutterAppDelegate {
  private var methodChannel: FlutterMethodChannel?
  private var appleRemindersChannel: FlutterMethodChannel?
  private var appleNotesChannel: FlutterMethodChannel?
  private var appleCalendarChannel: FlutterMethodChannel?

  private let appleRemindersService = AppleRemindersService()
  private let appleNotesService = AppleNotesService()
  private let appleCalendarService = AppleCalendarService()

  private var notificationTitleOnKill: String?
  private var notificationBodyOnKill: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Handle incoming app links
    if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
      AppLinks.shared.handleLink(url: url)
      return true
    }

    // Creates a method channel to handle notifications on kill
    let controller = window?.rootViewController as? FlutterViewController
    methodChannel = FlutterMethodChannel(name: "com.friend.ios/notifyOnKill", binaryMessenger: controller!.binaryMessenger)
    methodChannel?.setMethodCallHandler { [weak self] (call, result) in
      self?.handleMethodCall(call, result: result)
    }

    // Create Apple Reminders method channel
    appleRemindersChannel = FlutterMethodChannel(name: "com.omi.apple_reminders", binaryMessenger: controller!.binaryMessenger)
    appleRemindersChannel?.setMethodCallHandler { [weak self] (call, result) in
      self?.handleAppleRemindersCall(call, result: result)
    }

    // Create Apple Notes method channel
    appleNotesChannel = FlutterMethodChannel(name: "com.omi.apple_notes", binaryMessenger: controller!.binaryMessenger)
    appleNotesChannel?.setMethodCallHandler { [weak self] (call, result) in
      self?.appleNotesService.handleMethodCall(call, result: result)
    }

    // Create Apple Calendar method channel
    appleCalendarChannel = FlutterMethodChannel(name: "com.omi.apple_calendar", binaryMessenger: controller!.binaryMessenger)
    appleCalendarChannel?.setMethodCallHandler { [weak self] (call, result) in
      self?.appleCalendarService.handleMethodCall(call, result: result)
    }

    // Register callback for foreground tasks
    SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "setNotificationOnKillService":
      handleSetNotificationOnKillService(call: call)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func handleSetNotificationOnKillService(call: FlutterMethodCall) {
    if let args = call.arguments as? [String: Any] {
      notificationTitleOnKill = args["title"] as? String
      notificationBodyOnKill = args["description"] as? String
    }
  }

  private func handleAppleRemindersCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    appleRemindersService.handleMethodCall(call, result: result)
  }

  override func applicationWillTerminate(_ application: UIApplication) {
    // If title and body are nil, then we don't need to show notification.
    guard let title = notificationTitleOnKill, let body = notificationBodyOnKill else {
      return
    }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
    let request = UNNotificationRequest(identifier: "notification on app kill", content: content, trigger: trigger)
    UNUserNotificationCenter.current().add(request) { error in
      if let error = error {
        NSLog("Failed to show notification on kill service => error: \(error.localizedDescription)")
      }
    }
  }
}

// This function is required by the Flutter foreground task plugin
func registerPlugins(registry: FlutterPluginRegistry) {
  GeneratedPluginRegistrant.register(with: registry)
}