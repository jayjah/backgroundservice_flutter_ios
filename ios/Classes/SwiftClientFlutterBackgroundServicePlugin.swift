



//
///  BackgroundService.swift
///  Runner
///
///  Created by Markus Krebs on 23.06.19.
///  Copyright © 2019
///

import Flutter
import UIKit
import Foundation
import CoreLocation
import SystemConfiguration
import UserNotifications



///Global Properties
let TAG = "BackgroundService"
let debug = true
let syncSeconds:TimeInterval = 2
let interval = 5.0
let stationaryTimout = (Double)(5 * 60) // 5 minutes

///Global Classes
var taskManager = TaskManager()
@available(iOS 10.0, *)
var customViewController = CustomViewController()

@available(iOS 10.0, *)
var instance: SwiftClientFlutterBackgroundServicePlugin? = nil
var registerPlugins: FlutterPluginRegistrantCallback? = nil
var initialized = false
var appBounded = false
var gpsServiceEnabled = false
var pushNotificationServiceEnabled = false
var registerLifecycleCallbacks = false
var mainModeEnabled = false
var backgroundFetchEnabled = false
var backgroundTimer: Timer!
var locationTimer: Timer!
var stopUpdateTimer: Timer!
var backgroundTaskCount = 0


///Logger with NSLog
///logs only if debug session
func log(message: String){
    if(debug == true) {
        NSLog("%@ - %@", TAG, message)
    }
}

///Enum specific callback name to specific callback to find easily right callback
enum CallbackType : String {
    case mainCallback = "main_callback"
    case gpsCallback = "gps_callback"
    case pushNotificationCallback = "push_notification_callback"
    case appLifecycleOnCreate = "lifecycle_oncreate_callback"
    case appLifecycleOnResume = "lifecycle_onresume_callback"
    case appLifecycleOnTerminate = "lifecycle_ontermiante_callback"
}

/**
    SwiftClientFlutterBackgroundServicePlugin
 Class for handling gps data in background, code will trigger dart code
 where the socket connection is established. This is caused by dispatching
 callbacks to flutter, after received gps data.
 Finally should this class prevent the os to shut down the dart code, where the socket connection is established and should be established till the very eeend.
 */
@available(iOS 10.0, *)
public class SwiftClientFlutterBackgroundServicePlugin: NSObject, CLLocationManagerDelegate, FlutterPlugin {
    
    ///Class Properties
    private var locationManager: CLLocationManager?
    private var headlessRunner: FlutterEngine?
    private var callbackChannel: FlutterMethodChannel?
    private var mainChannel: FlutterMethodChannel?
    private weak var registrar: FlutterPluginRegistrar?
    private var persistentState: UserDefaults?
    private var eventQueue: [AnyHashable]? = []
    private let onLocationUpdateHandle: Int64 = 0
    var locationArray = [CLLocation]()
    var updatingLocation = false
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        //let channel = FlutterMethodChannel(name: "background_service", binaryMessenger: registrar.messenger())
        log(message: "BackgroundService Native :: register : was called")
        let lockQueue = DispatchQueue(label: "self")
        lockQueue.sync {
            if instance == nil {
                instance = SwiftClientFlutterBackgroundServicePlugin(registrar)
                registrar.addApplicationDelegate(instance! as FlutterPlugin)
                //registrar.addMethodCallDelegate(instance!, channel: channel)
                log(message: "BackgroundService Native :: register : was succesfully called")
            }
        }
    }
    
    public static func setPluginRegistrantCallback(_ callback: @escaping FlutterPluginRegistrantCallback) {
        registerPlugins = callback
        log(message: "BackgroundService Native :: setPluginRegistrant : was called with \(callback)")
    }

    init(_ registrar: FlutterPluginRegistrar?) {
        super.init()

        log(message: "BackgroundService Native :: init :")
        // 1. Retrieve NSUserDefaults which will be used to store callback handles
        // between launches.
        persistentState = UserDefaults.standard
        
        // 3. Initialize the Dart runner which will be used to run the callback
        // dispatcher.
        self.headlessRunner = FlutterEngine(name: "de.movementfam.webapp/background_plugin_background", project: nil, allowHeadlessExecution: true)
        self.registrar = registrar!
        
        // 4. Create the method channel used by the Dart interface to invoke
        // methods and register to listen for method calls.
        self.mainChannel = FlutterMethodChannel(name: "de.movementfam.webapp/background_service", binaryMessenger: registrar!.messenger())
        
        self.registrar?.addMethodCallDelegate(self, channel: mainChannel!)
        
        // 5. Create a second method channel to be used to communicate with the
        // callback dispatcher. This channel will be registered to listen for
        // method calls once the callback dispatcher is started.
        self.callbackChannel = FlutterMethodChannel(name: "de.movementfam.webapp/background_plugin_background", binaryMessenger: self.headlessRunner!)
        
        // 6. Register app lifecycle methods
        NotificationCenter.default.addObserver(self, selector: #selector(SwiftClientFlutterBackgroundServicePlugin.onFinishLaunching(notification:)), name: NSNotification.Name.UIApplicationDidFinishLaunching, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(SwiftClientFlutterBackgroundServicePlugin.onResume), name: NSNotification.Name.UIApplicationWillEnterForeground,
            object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(SwiftClientFlutterBackgroundServicePlugin.onAppTerminate) , name: NSNotification.Name.UIApplicationWillTerminate, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(SwiftClientFlutterBackgroundServicePlugin.willResign), name: NSNotification.Name.UIApplicationWillResignActive,
         object: nil)
        
         NotificationCenter.default.addObserver(
         self,
         selector: #selector(SwiftClientFlutterBackgroundServicePlugin.onSuspend),
         name: NSNotification.Name.UIApplicationDidEnterBackground,
         object: nil)
        
    }
    
    @objc func onFetchEvent(performFetchWithCompletionHandler completionHandler:
        @escaping (UIBackgroundFetchResult) -> Void) {
        log(message: "Backgroundserviceplugin Native :: fetch handler from  is called!!!")
        instance!.prepareToSendEvents()
        if (backgroundFetchEnabled) {
            completionHandler(.newData)

        } else {
            completionHandler(.newData)

            //completionHandler(.noData)
        }
    }
    
    ///Lifecycle Methods
    @objc func onResume() {
        log(message: "BackgroundServicePlugin Native :: App Resumed")
        instance!.prepareToSendEvents()
        
        if (initialized || gpsServiceEnabled) {
            taskManager.endAllBackgroundTasks()
        }
        if (registerLifecycleCallbacks) {
            
        }
    }
    
    @objc func onSuspend() {
        log(message: "BackgroundServicePlugin Native :: App Suspended.")
        instance!.prepareToSendEvents()
        
        if (initialized || gpsServiceEnabled) {
            instance!.startUpdating(force: true)
        }
    }
    
    @objc func onAppTerminate() {
        log(message: "BackgroundServicePlugin Native :: App was Terminated.")
        instance!.prepareToSendEvents()
        if (initialized || gpsServiceEnabled) {
            instance!.startTerminatedMode()
        }
        if (registerLifecycleCallbacks) {
            
        }
    }
    
    @objc func willResign() {
        log(message: "BackgroundServicePlugin Native :: App Will Resign.")
        instance!.prepareToSendEvents()

        if (initialized || gpsServiceEnabled) {
            instance!.startUpdating(force: true)
        }
    }
    
    @objc func onFinishLaunching(notification: NSNotification) {
        log(message: "BackgroundServicePlugin Native :: App finished launching")
        let launchOptions = notification.userInfo
        UIApplication.shared.setMinimumBackgroundFetchInterval(UIApplicationBackgroundFetchIntervalMinimum)
        if (launchOptions?[UIApplicationLaunchOptionsKey.location] != nil) {
            log(message: "BackgroundServicePlugin Native :: application : was launched cause of new gps coordinate")
            instance!.startBackgroundService(getCallbackDispatcherHandle())
            instance!.startTerminatedMode()
            instance!.prepareToSendEvents()
            
            if (gpsServiceEnabled) {
                
            }
        }
        if (registerLifecycleCallbacks) {
            
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard (call.arguments as? NSArray) != nil else {return}
        
        log(message:"BackgroundService Native :: handle : arguments of flutter method call \(call.arguments)")
        log(message:"BackgroundService Native :: handle : handle method to call \(call.method)")
        
        let arguments = call.arguments as? NSArray
        
        if ("BackgroundService.initialized" == call.method) {
            ///is on ios not called -> not needed

            result(nil)
        } else if ("BackgroundService.registerMainCallback" == call.method) {
            ///register main callback
            ///enables most background processing time for dart callback
            ///main functionality for this plugin
            let lockQueue = DispatchQueue(label: "self")
            lockQueue.sync {
                registerCallback(arguments!, callback: CallbackType.mainCallback)
                initialized=true
            }

            result(NSNumber(value: true))
        } else if ("BackgroundService.registerGPSCallback" == call.method) {
            //EXTRA gps callback if present
            
            let lockQueue = DispatchQueue(label: "self")
            lockQueue.sync {
                gpsServiceEnabled = true
            }
            result(NSNumber(value: false))

        } else if ("BackgroundService.registerPushNotificationCallback" == call.method) {
            //EXTRA push notification callback if present
            let lockQueue = DispatchQueue(label: "self")
            lockQueue.sync {
                pushNotificationServiceEnabled = true
            }
            result(NSNumber(value: false))

        } else if ("BackgroundService.registerLifecycleCallbacks" == call.method) {
            /// register lifecycle callback methods here
            /// if is called all parameters are registered!
            /// arguments[0] == onCreate
            /// arguments[1] == onResume
            /// arguments[2] == onTerminated
            guard let oncreateCallback = arguments![0] as? Int64 else {return result(false)}
            guard let onresumeCallback = arguments![1] as? Int64 else {return result(false)}
            guard let onterminateCallback = arguments![2] as? Int64 else {return result(false)}
            
            let lockQueue = DispatchQueue(label: "self")
            lockQueue.sync {
                registerLifecycleCallbacks = true
            }
            
            //TODO: register lifecycle callbacks
            
            result(NSNumber(value: false))

        } else if ("BackgroundService.enableBackgroundFetch" == call.method) {
            ///register main callback for background fetch event
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(SwiftClientFlutterBackgroundServicePlugin.onFetchEvent),
                name: NSNotification.Name.UIApplicationBackgroundRefreshStatusDidChange,
                object: nil)
            
            /// arguments[0] == if present registers extra fetch callback, if not main callback will only be called, cause main callback should be allready present here
            ///this means, background fetch is an only plus functionality, cause this is only an ios feature
            guard (arguments!.count > 0) else {return result(NSNumber(value: true));}
            guard let fetchCallback = arguments![0] as? Int64 else {return result(NSNumber(value: true));}
            //backgroundFetchEnabled = true
            //TODO: register extra callback
            
            result(NSNumber(value: true))
        } else if ("BackgroundService.initializeService" == call.method) {
            ///intializte Service with Config, config explains which Service should be registered
            ///plus is needed to ask for specifig permission
            /// if arguments[0] == 0 gps service should start and ask for permission plus main callback is registered here to (arguments[1])
            /// if arguments[0] == 1 push service should start and ask for permission plus main callback is registered here to (arguments[1])
            /// if arguments[0] == 2 gps and push service should start and ask for permission plus main callback is registered here to (arguments[1])
            /// arguments[1] == callback for main callback, must be present
            guard let permissionConfig = arguments![0] as? Int else {return result(false)}
            guard let mainCallback = arguments![1] as? Int64 else {return result(false)}

            let lockQueue = DispatchQueue(label: "self")
            lockQueue.sync {
                switch permissionConfig {
                case 0:
                    startGPSService()
                    startBackgroundService(mainCallback)
                    
                    return result(NSNumber(value: true))
                case 1:
                    startPushNotificationService()
                    startBackgroundService(mainCallback)

                    return result(NSNumber(value: true))
                case 2:
                    startGPSService()
                    startPushNotificationService()
                    startBackgroundService(mainCallback)

                    return result(NSNumber(value: true))
                default:
                    return result(NSNumber(value: false))
                }
            }
        } else if ("BackgroundService.checkConnectivity" == call.method) {
            let connectivity = SwiftClientFlutterBackgroundServicePlugin.isConnectedToNetwork()
            result(connectivity)
        } else if ("BackgroundService.sendPushNotification" == call.method) {
            ///send local push notification
            ///to let this fully work BackgroundService.initializeService with correct parameter should be called first!
            let titel = arguments![0] as? String
            let shorti = arguments![1] as? String
            let longi = arguments![2] as? String
            guard ((titel != nil) && (shorti != nil) && (longi != nil)) else {return result(false);}
            let lockQueue = DispatchQueue(label: "self")
            lockQueue.sync {
                NotificationManager.manager.notify(titel: titel!, shortText: shorti!, text: longi!)
            }

            result(NSNumber(value: true))
        } else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]){
        log(message: "BackgroundService Native :: locationManager : received new location \(locations)")
        
        guard let locationObj = locations.last else {return;}
        
        if(locationTimer != nil) {
            return
        }
        
        let lockQueue = DispatchQueue(label: "self")
        lockQueue.sync {
            let locationDic = locationToDict(loc: locationObj )
            let state = UIApplication.shared.applicationState
            
            if state == .background || state == .inactive {
                //app is inactive
                NotificationManager.manager.notify(titel: "TEST", shortText: "received gps data", text: "when app is background or suspended")
            }
            
            instance!.eventQueue!.append(locationDic)
            
            taskManager.beginNewBackgroundTask()
            
            locationTimer = Timer.scheduledTimer(timeInterval: appBounded ? stationaryTimout : interval, target: self, selector: #selector(SwiftClientFlutterBackgroundServicePlugin.restartUpdates), userInfo: nil, repeats: false)
            
            if(stopUpdateTimer != nil) {
                stopUpdateTimer.invalidate()
                stopUpdateTimer = nil
            }
            
            stopUpdateTimer = Timer.scheduledTimer(timeInterval: syncSeconds, target: self, selector: #selector(SwiftClientFlutterBackgroundServicePlugin.prepareToSendEvents), userInfo: nil, repeats: false)
            
        }
        
        
    }
    
    func startBackgroundService(_ handle: Int64) {
        log(message:"BackgroundService Native :: startGeofencingService : was called with : \(handle)")
        setCallbackDispatcherHandle(handle)
        
        let info = FlutterCallbackCache.lookupCallbackInformation(handle)
        assert(info != nil, "failed to find callback")
        
        let entrypoint = info?.callbackName
        let uri = info?.callbackLibraryPath
        headlessRunner!.run(withEntrypoint: entrypoint, libraryURI: uri)
        assert(registerPlugins != nil, "failed to set registerPlugins")
        
        // Once our headless runner has been started, we need to register the application's plugins
        // with the runner in order for them to work on the background isolate. `registerPlugins` is
        // a callback set from AppDelegate.m in the main application. This callback should register
        // all relevant plugins (excluding those which require UI).
        registerPlugins!(headlessRunner!)
        
        registrar!.addMethodCallDelegate(self as FlutterPlugin, channel: callbackChannel!)
    }
    
    private func startGPSService() {
        // 2. Initialize the location manager, and register as its delegate.
        locationManager = CLLocationManager()
        locationManager!.delegate = self
        requestLocationPermissions(gps: true, pn: false, am: false)
        locationManager!.allowsBackgroundLocationUpdates = true
        locationManager!.pausesLocationUpdatesAutomatically = false
        locationManager!.startMonitoringSignificantLocationChanges()
        locationManager!.startUpdatingLocation()
    }
    
    private func startPushNotificationService() {
        customViewController.viewDidLoad()
        requestLocationPermissions(gps: false, pn: true, am: false)
    }
    
    func requestLocationPermissions(gps:Bool,pn:Bool, am:Bool) {
        if (gps) {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert,.sound,.badge]) {
                (granted, error) in
                if granted {
                    log(message: "Push Notification services is enabled")
                } else {
                    log(message: "Push Notification services is not enabled")
                    if (am) {
                        //aggresive mode -> exit app if permission not permitted
                    }
                }
            }
        }
        if (pn) {
            locationManager!.requestAlwaysAuthorization()
            
            if (!CLLocationManager.locationServicesEnabled()) {
                log(message: "Location services is not enabled")
                if (am) {
                    //aggresive mode -> exit app if permission not permitted
                }
            } else {
                log(message: "Location services enabled")
            }
            /*if CLLocationManager.authorizationStatus() == .notDetermined {
             // For use when the app is open
             //locationManager.requestWhenInUseAuthorization()
             }*/
        }
    }
    
    func startTerminatedMode() {
        locationManager!.delegate = self
        locationManager!.pausesLocationUpdatesAutomatically = false
        locationManager!.allowsBackgroundLocationUpdates = true
        updatingLocation = true;
        //locationManager!.stopUpdatingLocation()
        locationManager!.startMonitoringSignificantLocationChanges()
    }
    
    @objc func prepareToSendEvents() {
        guard (instance!.eventQueue!.last as? NSDictionary != nil) else {return;}
        let lockQueue = DispatchQueue(label: "self")
        lockQueue.sync {
            let state = UIApplication.shared.applicationState
            let locationDic = instance!.eventQueue!.last as? NSDictionary

            if state == .background || state == .inactive {
                //app is inactive
                instance!.sendLocationEvent(dic: locationDic!)
            } else {
                //app is active
                if initialized {
                    instance!.sendLocationEvent(dic: locationDic!)
                }
            }
        }
    }
    
    @objc func restartUpdates() {
        log(message: "restartUpdates called")
        if(locationTimer != nil) {
            locationTimer.invalidate()
            locationTimer = nil
        }
        
        self.locationManager!.delegate = self
        
        self.startUpdating(force: true)
    }
    
    func startUpdating(force : Bool) {
        if(!self.updatingLocation || force) {
            self.updatingLocation = true
            
            self.locationManager!.delegate = self
            
            self.locationManager!.startUpdatingLocation()
            self.locationManager!.startMonitoringSignificantLocationChanges()
            
            taskManager.beginNewBackgroundTask()
            
            log(message: "Starting Location Updates!")
        } else {
            log(message: "A request was made to start Updating, but the plugin was already updating")
        }
    }
    
    func stopUpdating() {
        log(message: "[LocationManager.stopUpdating] Stopping Location Updates!")
        self.updatingLocation = false
        
        if(locationTimer != nil) {
            locationTimer.invalidate()
            locationTimer = nil
        }
        
        if(stopUpdateTimer != nil) {
            stopUpdateTimer.invalidate()
            stopUpdateTimer = nil
        }
        
        self.locationManager!.stopUpdatingLocation()
    }
    
    func sendLocationEvent(dic:NSDictionary) {
        log(message:"BackgroundService Native :: sendLocationEvent : send message back to dart path; callback: \(getCallbackDispatcherHandle())")
        callbackChannel!.invokeMethod("", arguments:[
             NSNumber(value: getCallbackDispatcherHandle()), dic["timestamp"]]/*,[0],
             [NSNumber(value: 0), NSNumber(value: 0)],
             NSNumber(value: 0)
             ]*/)
    }
    
    func getCallbackDispatcherHandle() -> Int64 {
        let handle = persistentState!.object(forKey: "callback_dispatcher_handle")
        log(message:"BackgroundService :: getCallbackDispatcherHandle : callback to handle: \(handle)")
        if handle == nil {
            return 0
        }
        return (handle as? NSNumber)?.int64Value ?? 0
    }
    
    func setCallbackDispatcherHandle(_ handle: Int64) {
        persistentState!.set(handle, forKey:"callback_dispatcher_handle")
    }
    
    func registerCallback(_ arguments: NSArray, callback:CallbackType) {
        switch callback {
        case CallbackType.mainCallback:
            let callbackHandle = (arguments[0] as? Int64)
            guard callbackHandle != nil else { return; }
            setCallbackDispatcherHandle(callbackHandle!)
        case CallbackType.gpsCallback:
            break
        case CallbackType.pushNotificationCallback:
            break
        case CallbackType.appLifecycleOnCreate:
            break
        case CallbackType.appLifecycleOnResume:
            break
        case CallbackType.appLifecycleOnTerminate:
            break
        default:
            break
        }
    }
}

/**
 This extension brings functionality for:
    1. if current network access exist or not
    2. transforms CLLLocation to NSDictionary
 */
@available(iOS 10.0, *)
extension SwiftClientFlutterBackgroundServicePlugin {
    
    func locationToDict(loc:CLLocation) -> NSDictionary {
        let locDict:Dictionary = [
            "latitude" : loc.coordinate.latitude,
            "longitude" : loc.coordinate.longitude,
            "accuracy" : loc.horizontalAccuracy,
            "timestamp" : ((loc.timestamp.timeIntervalSince1970 as Double) * 1000),
            "speed" : loc.speed,
            "altitude" : loc.altitude,
            "heading" : loc.course
        ]
        return locDict as NSDictionary
    }
    
    static func isConnectedToNetwork() -> Bool {
        
        var zeroAddress = sockaddr_in(sin_len: 0, sin_family: 0, sin_port: 0, sin_addr: in_addr(s_addr: 0), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
        zeroAddress.sin_len = UInt8(MemoryLayout.size(ofValue: zeroAddress))
        zeroAddress.sin_family = sa_family_t(AF_INET)
        
        let defaultRouteReachability = withUnsafePointer(to: &zeroAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {zeroSockAddress in
                SCNetworkReachabilityCreateWithAddress(nil, zeroSockAddress)
            }
        }
        
        var flags: SCNetworkReachabilityFlags = SCNetworkReachabilityFlags(rawValue: 0)
        if SCNetworkReachabilityGetFlags(defaultRouteReachability!, &flags) == false {
            return false
        }
        
        /* Only Working for WIFI
         let isReachable = flags == .reachable
         let needsConnection = flags == .connectionRequired
         
         return isReachable && !needsConnection
         */
        
        // Working for Cellular and WIFI
        let isReachable = (flags.rawValue & UInt32(kSCNetworkFlagsReachable)) != 0
        let needsConnection = (flags.rawValue & UInt32(kSCNetworkFlagsConnectionRequired)) != 0
        let ret = (isReachable && !needsConnection)
        
        return ret
        
    }
}

extension UserDefaults {
    static func isFirstLaunch() -> Bool {
        let firstLaunchFlag = "FirstLaunchFlag"
        if !standard.bool(forKey: firstLaunchFlag) {
            standard.set(true, forKey: firstLaunchFlag)
            return true
        }
        return false
    }
    
    // For multi user login
    //need to use???
    func isFirstLaunchForUser(user: String) -> Bool {
        if !bool(forKey: user) {
            set(true, forKey: user)
            return true
        }
        return false
    }
}

@available(iOS 10.0, *)
class CustomViewController : UIViewController, UNUserNotificationCenterDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view, typically from a nib.
        UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let lockQueue = DispatchQueue(label: "self")
        log(message:"handling notifications")
        instance!.prepareToSendEvents()
        
        completionHandler([.alert, .sound, .badge])
    }
}

/**
    This class creates a local push notification
 */
@available(iOS 10.0, *)
class NotificationManager : NSObject {
    
    static var manager = NotificationManager()
    
    func notify(titel: String, shortText: String,text: String, imageName:String = "nil",imageExt:String = "nil") {
        log(message: "Sending Notification with \(titel) \(shortText) \(text)")
        
        let lockQueue = DispatchQueue(label: "self")
        lockQueue.sync {
            let content = UNMutableNotificationContent()
            content.title = titel
            content.subtitle = shortText
            content.body = text
            content.badge = 1
            content.sound = UNNotificationSound.default()
            
            if (imageName != "nil" && imageExt != "nil") {
                guard let imageURL = Bundle.main.url(forResource: imageName, withExtension: imageExt) else { return }
                
                let attachment = try! UNNotificationAttachment(identifier: imageName, url: imageURL, options: .none)
                
                content.attachments = [attachment]
            }
            
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3,
                                                            repeats: false)
            
            let requestIdentifier = TAG
            let request = UNNotificationRequest(identifier: requestIdentifier,
                                                content: content, trigger: trigger)
            
            // Schedule the request.
            let center = UNUserNotificationCenter.current()
            center.add(request, withCompletionHandler: nil)
            log(message: "Push Notification was send")
        }
    }
}

//Task Manager Singleton
class TaskManager : NSObject {
    
    //let priority = DispatchQueue.GlobalAttributes.qosUserInitiated
    
    var _bgTaskList = [Int]()
    var _masterTaskId = UIBackgroundTaskInvalid
    
    func beginNewBackgroundTask() -> UIBackgroundTaskIdentifier {
        //log(message: "beginNewBackgroundTask called")
        
        let app = UIApplication.shared
        var bgTaskId = UIBackgroundTaskInvalid
        
        if(app.responds(to: Selector(("beginBackgroundTask")))) {
            bgTaskId = app.beginBackgroundTask(expirationHandler: {
                log(message: "Background task \(bgTaskId) expired")
            })
            if(self._masterTaskId == UIBackgroundTaskInvalid) {
                self._masterTaskId = bgTaskId
                log(message: "Started Master Task ID \(self._masterTaskId)")
            } else {
                log(message: "Started Background Task \(bgTaskId)")
                self._bgTaskList.append(bgTaskId)
                self.endBackgroundTasks()
            }
        }
        
        return bgTaskId
    }
    
    func endBackgroundTasks() {
        self.drainBGTaskList(all: false)
    }
    
    func endAllBackgroundTasks() {
        self.drainBGTaskList(all: true)
    }
    
    func drainBGTaskList(all:Bool){
        let app = UIApplication.shared
        if(app.responds(to: Selector(("endBackgroundTask")))) {
            let count = self._bgTaskList.count
            
            for _ in 0 ..< count {
                let bgTaskId = self._bgTaskList[0] as Int
                log(message: "Ending Background Task  with ID \(bgTaskId)")
                app.endBackgroundTask(bgTaskId)
                self._bgTaskList.remove(at: 0)
            }
            
            if(self._bgTaskList.count > 0) {
                log(message: "Background Task Still Active \(self._bgTaskList[0])")
            }
            
            if(all) {
                log(message: "Killing Master Task \(self._masterTaskId)")
                app.endBackgroundTask(self._masterTaskId)
                self._masterTaskId = UIBackgroundTaskInvalid
            } else {
                log(message: "Kept Master Task ID \(self._masterTaskId)")
            }
        }
    }
}
