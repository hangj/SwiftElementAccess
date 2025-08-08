import Cocoa

// public struct SwiftElementAccess {
//     public private(set) var text = "Hello, World!"

//     public init() {
//     }
// }


// guard #available(macOS 10.13, *) else {
//     print("macOS 10.13+ is required")
//     exit(0)
// }

func isSandboxingEnabled() -> Bool {
    let environment = ProcessInfo.processInfo.environment
    return environment["APP_SANDBOX_CONTAINER_ID"] != nil
}

/// https://stackoverflow.com/a/50901425/1936057
/// It appears, in 10.13.3 at least, that applications which are using the app sandbox will not have the alert shown. If you turn off app sandbox in the project entitlements then the alert is shown
public func checkIsProcessTrusted(prompt: Bool = false) -> Bool {
    if isSandboxingEnabled() {
        print("sandbox is enabled.")
        // print("This app is not trusted to use Accessibility API. Please enable it in System Preferences > Security & Privacy > Privacy > Accessibility")
        return false
    }
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let opts = [promptKey: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
}

class Node<T> {
    public let value: T
    public var next: Node<T>?

    init(_ value: T) {
        self.value = value
        self.next = nil
    }
}

class Queue<T> {
    var head: Node<T>? = nil
    var tail: Node<T>? = nil
    var count: UInt = 0

    init() {
        self.head = nil
        self.tail = nil
        self.count = 0
    }

    public var isEmpty: Bool {
        return self.count == 0
    }

    public func push_back(value: T) {
        let node = Node(value)
        if self.isEmpty {
            self.head = node
            self.tail = node
        } else {
            self.tail!.next = node
            self.tail = node
        }
        self.count += 1
    }

    public func push_back<S>(contentsOf newElements: S) where S : Sequence, T == S.Element {
        for v in newElements {
            self.push_back(value: v)
        }
    }

    public func pop_front() -> T? {
        if let head = self.head {
            self.head = head.next
            self.count -= 1
            return head.value
        }
        return nil
    }
}

extension Queue: CustomStringConvertible {
    var description: String {
        var ret = "("
        var head = self.head
        while let node = head {
            ret += "\(node.value),"
            head = node.next
        }
        return ret + ")"
    }
}


func stringFromAXValue(_ value: AnyObject) -> String {
    if value is Element {
        print("value is Element")
        let ele = value as! Element
        return "\(ele)"
    }

    let cfType = CFGetTypeID(value)
    if cfType == AXValueGetTypeID() {
        let v = value as! AXValue
        let type = AXValueGetType(v)

        switch type {
            case .axError: 
                var err = AXError.success
                AXValueGetValue(v, type, &err)
                return "\(err)"
            case .cfRange:
                var range = CFRange()
                AXValueGetValue(v, type, &range)
                return "CFRange\(range)"
            case .cgPoint:
                var point = CGPoint()
                AXValueGetValue(v, type, &point)
                return "CGPoint\(point)"
            case .cgRect:
                var rect = CGRect()
                AXValueGetValue(v, type, &rect)
                return "CGRect\(rect)"
            case .cgSize:
                var size = CGSize()
                AXValueGetValue(v, type, &size)
                return "CGSize\(size)"
            case .illegal:
                return "illegal"
            @unknown default:
                return "unknown"
        }
    } else if cfType == AXUIElementGetTypeID() {
        let ele = Element(value as! AXUIElement)
        return "\(ele)"
    } else {
        // var s = CFCopyTypeIDDescription(cfType)
        // s = CFCopyDescription(value)

        if cfType == CFStringGetTypeID() {
            return value as! String
        }
        if cfType == CFNumberGetTypeID() {
            let v = value as! NSNumber
            return "\(v)"
        }
        if cfType == CFBooleanGetTypeID() {
            let b = value as! Bool
            return "\(b)"
        }
        if cfType == CFNullGetTypeID() {
            return "nil"
        }
        if cfType == CFArrayGetTypeID() {
            let arr = value as! [AnyObject]
            return "\(arr)"
        }
        if cfType == CFDictionaryGetTypeID() {
            let dict = value as! [String: AnyObject]
            return "\(dict)"
        }
    }

    return ""
}

/// return dict/array/string/number
func axValueToJsonValue(_ value: AnyObject, unique: inout Set<AXUIElement>) -> Any {
    if value is Element {
        print("value is Element")
        let ele = value as! Element
        return ele.toDict(unique: &unique)
    }

    let cfType = CFGetTypeID(value)
    if cfType == AXValueGetTypeID() {
        let v = value as! AXValue
        let type = AXValueGetType(v)

        switch type {
            case .axError: 
                var err = AXError.success
                AXValueGetValue(v, type, &err)
                return "\(err)"
            case .cfRange:
                var range = CFRange()
                AXValueGetValue(v, type, &range)
                return ["type": "CFRange", "location": range.location, "length": range.length]
            case .cgPoint:
                var point = CGPoint()
                AXValueGetValue(v, type, &point)
                return ["type": "CGPoint", "x": point.x, "y": point.y]
            case .cgRect:
                var rect = CGRect()
                AXValueGetValue(v, type, &rect)
                return ["type": "CGRect", "origin": ["x": rect.origin.x, "y": rect.origin.y], "size": ["height": rect.size.height, "width": rect.size.width]]
            case .cgSize:
                var size = CGSize()
                AXValueGetValue(v, type, &size)
                return ["type": "CGSize", "height": size.height, "width": size.width]
            case .illegal:
                return "illegal"
            @unknown default:
                return "unknown"
        }
    } else if cfType == AXUIElementGetTypeID() {
        let ele = Element(value as! AXUIElement)
        return ele.toDict(unique: &unique)
    } else {
        if cfType == CFStringGetTypeID() {
            return value as! String
        }
        if cfType == CFNumberGetTypeID() {
            let v = value as! NSNumber
            return v
        }
        if cfType == CFBooleanGetTypeID() {
            let b = value as! Bool
            return b
        }
        if cfType == CFNullGetTypeID() {
            return "nil"
        }
        if cfType == CFArrayGetTypeID() {
            let arr = value as! [AnyObject]
            return arr.map { axValueToJsonValue($0, unique: &unique) } //.joined(separator: ",")
        }
        if cfType == CFDictionaryGetTypeID() {
            let dict = value as! [String: AnyObject]
            return dict.mapValues { axValueToJsonValue($0, unique: &unique) }
        }
    }

    // var s = CFCopyTypeIDDescription(cfType)!
    // return s
    // s = CFCopyDescription(value)

    return "nil"
}

/// https://gist.github.com/z3t0/e2338f99680e462533e5e41691f51e99
/// For some reason values don't get described in this enum, so we have to do it manually.
extension AXError: CustomStringConvertible {
  fileprivate var valueAsString: String {
    switch self {
    case .success:
      return "Success"
    case .failure:
      return "Failure"
    case .illegalArgument:
      return "IllegalArgument"
    case .invalidUIElement:
      return "InvalidUIElement"
    case .invalidUIElementObserver:
      return "InvalidUIElementObserver"
    case .cannotComplete:
      return "CannotComplete"
    case .attributeUnsupported:
      return "AttributeUnsupported"
    case .actionUnsupported:
      return "ActionUnsupported"
    case .notificationUnsupported:
      return "NotificationUnsupported"
    case .notImplemented:
      return "NotImplemented"
    case .notificationAlreadyRegistered:
      return "NotificationAlreadyRegistered"
    case .notificationNotRegistered:
      return "NotificationNotRegistered"
    case .apiDisabled:
      return "APIDisabled"
    case .noValue:
      return "NoValue"
    case .parameterizedAttributeUnsupported:
      return "ParameterizedAttributeUnsupported"
    case .notEnoughPrecision:
      return "NotEnoughPrecision"
    default:
        return "unknown"
    }
  }

  public var description: String {
    return "AXError.\(valueAsString)"
  }
}

func carbonScreenPointFromCocoaScreenPoint(_ point : NSPoint) -> CGPoint? {
    var foundScreen: NSScreen?
    for screen in NSScreen.screens {
        if NSPointInRect(point, screen.frame) {
            foundScreen = screen
            break
        }
    }
    if let screen = foundScreen {
        let height = screen.frame.size.height
        return CGPoint(x: point.x, y: height - point.y - 1)
    }

    return nil
}

extension Element: CustomStringConvertible {
    public var description: String {
        let pid = self.pid
        let role = self.role

        let title = self.title
        let label = self.label
        let desc = self.desc

        var txtInfo = ""

        if !title.isEmpty {
            txtInfo += "title: \(title),"
        }
        if !label.isEmpty {
            txtInfo += "label: \(label),"
        }
        if !desc.isEmpty {
            txtInfo += "description: \(desc),"
        }

        if let v: AnyObject = self.value() {
            let s = stringFromAXValue(v)
            if !s.isEmpty {
                txtInfo += "value: \(s),"
            }
        }

        var frame = ""
        if let frm = self.frame {
            frame = "frame: \(frm)"
        }
        let hash = "hashValue: \(self.ele.hashValue)"
        return "Element(role: \(role), pid: \(pid), \(txtInfo) enabled: \(self.isEnabled), \(frame)) \(hash)"
    }
}


func observerCallback(_ observer:AXObserver, _ element:AXUIElement, _ notification:CFString, _ userData:UnsafeMutableRawPointer?) -> Void {
    guard let userData = userData else { return }
    let ele = Unmanaged<Element>.fromOpaque(userData).takeUnretainedValue()

    if let cb = ele.notificationCallback {
        cb(notification as String, Element(element))
    }
}

// This is the main class to access UI elements in macOS.
// It provides methods to find elements by process name, bundle identifier, position, etc.
// It also allows you to set up observers for various notifications related to UI elements.
// You can get attributes, perform actions, and convert elements to JSON format.
public class Element {
    public typealias Callback = (_ notification: String, _ element: Element)->Void
    static let systemRef = AXUIElementCreateSystemWide()
    static var observers: [pid_t: AXObserver] = [:]

    let ele: AXUIElement
    var notificationCallback: Callback? = nil
    var notifications: [String] = []

    init(_ ele: AXUIElement) {
        self.ele = ele
    }

    public convenience init(fromPid pid: pid_t) {
        let kAXManualAccessibility: CFString = "AXManualAccessibility" as CFString;
        let e = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(e, kAXManualAccessibility, kCFBooleanTrue)
        self.init(e)
    }

    deinit {
        if self.isAppTerminated {
            if let _ = Self.observers.removeValue(forKey: pid) {
                print("removed observer for pid:", pid)
            }
            return
        }

        if let obs = Self.observers[pid] {
            for notification in self.notifications {
                AXObserverRemoveNotification(obs, self.ele, notification as CFString)
            }
        }
    }

    public var hashValue: Int {
        return self.ele.hashValue
    }

    public var isAppTerminated: Bool {
        let pid = self.pid
        if pid < 0 {
            return true
        }
        // NSRunningApplication(processIdentifier: pid)?.isActive
        return NSRunningApplication(processIdentifier: pid)?.isTerminated ?? true
    }

    /// Only valid from Dock
    public var isApplicationRunning: Bool {
        if let s: Bool = self.valueOfAttr(kAXIsApplicationRunningAttribute) {
            return s
        }
        return false
    }

    public static func fromPid(_ pid: pid_t) -> Element {
        return Element(fromPid: pid)
    }

    /// ```
    /// Element.fromProcessName("WeChat")
    /// ```
    public static func fromProcessName(_ name: String) -> [Element] {
        var ret: [Element] = []

        NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == name
        }.forEach {
            ret.append(Element.fromPid($0.processIdentifier))
        }

        return ret
    }

    /// ```
    /// Element.fromBundleIdentifier("com.tencent.xinWeChat")
    /// ```
    public static func fromBundleIdentifier(_ bundleIdentifier: String) -> [Element] {
        var ret: [Element] = []
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).forEach {
            ret.append(Element.fromPid($0.processIdentifier))
        }

        return ret
    }

    public static func fromFrontMostApplication() -> Element? {
        if let app = NSWorkspace.shared.frontmostApplication {
            return Element(fromPid: app.processIdentifier)
        }
        return nil
    }

    public static func fromPosition(x: Float, y: Float) -> Element? {
        var ele: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(Element.systemRef, x, y, &ele)
        if err == .success {
            return Element(ele!)
        }
        return nil
    }

    public static func fromPosition(_ pos: NSPoint) -> Element? {
        return fromPosition(x: Float(pos.x), y: Float(pos.y))
    }

    public static func fromMouseLocation() -> Element? {
        let cocoaPoint = NSEvent.mouseLocation
        if let point = carbonScreenPointFromCocoaScreenPoint(cocoaPoint) {
            return Self.fromPosition(point)
        }
        return nil
    }

    public func setNotificationCallback(_ callback: @escaping Callback) {
        self.notificationCallback = callback
    }

    public func watch(_ notification: String) {
        let pid = self.pid

        var obs = Self.observers[pid];

        if obs == nil {
            let e = AXObserverCreate(pid, observerCallback, &obs)
            if e == .success {
                Self.observers[pid] = obs!
                CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(obs!), CFRunLoopMode.defaultMode)
            } else {
                print("AXObserverCreate error:", e)
                return
            }
        }

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let e = AXObserverAddNotification(obs!, self.ele, notification as CFString, selfPtr)
        if e == .success || e == .notificationAlreadyRegistered {
            self.notifications.append(notification)
        }
    }

    public func watchAll() {
        self.watch(kAXMainWindowChangedNotification)
        self.watch(kAXFocusedWindowChangedNotification)
        self.watch(kAXFocusedUIElementChangedNotification)
        self.watch(kAXApplicationActivatedNotification)
        self.watch(kAXApplicationDeactivatedNotification)
        self.watch(kAXApplicationHiddenNotification)
        self.watch(kAXApplicationShownNotification)
        self.watch(kAXWindowCreatedNotification)
        self.watch(kAXWindowMovedNotification)
        self.watch(kAXWindowResizedNotification)
        self.watch(kAXWindowMiniaturizedNotification)
        self.watch(kAXWindowDeminiaturizedNotification)
        self.watch(kAXDrawerCreatedNotification)
        self.watch(kAXSheetCreatedNotification)
        self.watch(kAXHelpTagCreatedNotification)
        self.watch(kAXValueChangedNotification)
        self.watch(kAXUIElementDestroyedNotification)
        self.watch(kAXElementBusyChangedNotification)
        self.watch(kAXMenuOpenedNotification)
        self.watch(kAXMenuClosedNotification)
        self.watch(kAXMenuItemSelectedNotification)
        self.watch(kAXRowCountChangedNotification)
        self.watch(kAXRowExpandedNotification)
        self.watch(kAXRowCollapsedNotification)
        self.watch(kAXSelectedCellsChangedNotification)
        self.watch(kAXUnitsChangedNotification)
        self.watch(kAXSelectedChildrenMovedNotification)
        self.watch(kAXSelectedChildrenChangedNotification)
        self.watch(kAXResizedNotification)
        self.watch(kAXMovedNotification)
        self.watch(kAXCreatedNotification)
        self.watch(kAXSelectedRowsChangedNotification)
        self.watch(kAXSelectedColumnsChangedNotification)
        self.watch(kAXSelectedTextChangedNotification)
        self.watch(kAXTitleChangedNotification)
        self.watch(kAXLayoutChangedNotification)
        self.watch(kAXAnnouncementRequestedNotification)
    }

    public func activate() {
        if let app = NSRunningApplication(processIdentifier: self.pid) {
            print("app.isActive:", app.isActive)
            // Indicates whether the application is currently frontmost
            if !app.isActive {
                app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
                app.unhide()
            }
        }
    }

    public var isAppFrontMost: Bool {
        if self.isApplicationUIElement {
            if let b: Bool = self.valueOfAttr(kAXFrontmostAttribute) {
                return b
            }
            return false
        } else {
            return Element(fromPid: self.pid).isAppFrontMost
        }
    }

    public func setAppFrontmost() {
        if self.isApplicationUIElement {
            self.activate()
            while !self.isAppFrontMost {
                let e = AXUIElementSetAttributeValue(self.ele, kAXFrontmostAttribute as CFString, true as CFTypeRef)
                if e != .success {
                    print("setAppFrontmost failed:", e)
                    break
                }
                sleep(1)
            }
        } else {
            Element(fromPid: self.pid).setAppFrontmost()
        }
    }

    public var isWindowFrontMost: Bool {
        if self.isWindowUIElement {
            if let b: Bool = self.valueOfAttr(kAXMainAttribute) {
                return b
            }
            return false
        } else {
            return self.window?.isAppFrontMost ?? false
        }
    }

    public func setWindowFrontmost() {
        if self.isWindowUIElement {
            while !self.isWindowFrontMost {
                let e = AXUIElementSetAttributeValue(self.ele, kAXMainAttribute as CFString, true as CFTypeRef)
                if e != .success {
                    print("setWindowFrontmost failed:", e)
                    break
                }
                sleep(1)
            }
        } else {
            self.window?.setWindowFrontmost()
        }
    }


    public var pid: pid_t {
        var pid: pid_t = 0
        if AXUIElementGetPid(self.ele, &pid) == .success {
            return pid
        }
        return -1
    }

    public var attrNames: [String] {
        var arrNames: CFArray?
        let err = AXUIElementCopyAttributeNames(self.ele, &arrNames)
        if err == .success {
            if let arr = arrNames as? [String] {
                return arr
            }
        }
        return []
    }

    public func valueOfAttr<T>(_ attr: String) -> T? {
        var value: AnyObject?
        let axError = AXUIElementCopyAttributeValue(self.ele, attr as CFString, &value)
        if axError == .success {
            return value as? T
        }
        return nil
    }

    public var actionNames: [String] {
        var arrNames: CFArray?
        let err = AXUIElementCopyActionNames(self.ele, &arrNames)
        if err == .success {
            if let arr = arrNames as? [String] {
                return arr
            }
        }
        return []
    }

    public func valueOfAction(_ action: String) -> String? {
        var value : CFString?
        let axError = AXUIElementCopyActionDescription(self.ele, action as CFString, &value)
        if axError == .success {
            return value as String?
        }
        return nil
    }

    public func canSetAttr(_ name: String) -> Bool {
        var value : DarwinBoolean = false // https://stackoverflow.com/questions/33667321/what-is-darwinboolean-type-in-swift
        let err = AXUIElementIsAttributeSettable(self.ele, name as CFString, &value)
        if err == .success {
            return value.boolValue
        }
        return false
    }

    public func performAction(_ name: String) -> AXError {
        return AXUIElementPerformAction(self.ele, name as CFString)
    }

    public func setTimeout(_ timeoutInSeconds: Float) {
        AXUIElementSetMessagingTimeout(self.ele, timeoutInSeconds)
    }

    public var role: String {
        if let s: String = self.valueOfAttr(kAXRoleAttribute) {
            return s
        }
        return ""
    }

    public var subRole: String {
        if let s: String = self.valueOfAttr(kAXSubroleAttribute) {
            return s
        }
        return ""
    }

    /// Example:
    /// ```
    /// assert(Element.fromProcessName("WeChat")[0].isApplicationUIElement())
    /// ```
    public var isApplicationUIElement: Bool {
        self.role == kAXApplicationRole
    }

    public var isWindowUIElement: Bool {
        self.role == kAXWindowRole
    }

    public var appUIElement: Element {
        if self.isApplicationUIElement {
            return self
        } else {
            return Element(fromPid: self.pid)
        }
    }

    public var roleDesc: String {
        if let s: String = self.valueOfAttr(kAXRoleDescriptionAttribute) {
            return s
        }
        return ""
    }

    public var title: String {
        if let title: String = self.valueOfAttr(kAXTitleAttribute) {
            return title
        }
        return ""
    }

    public var label: String {
        if let label: String = self.valueOfAttr(kAXLabelValueAttribute) {
            return label
        }
        return ""
    }

    /// kAXDescriptionAttribute
    public var desc: String {
        if let s: String = self.valueOfAttr(kAXDescriptionAttribute) {
            return s
        }
        return ""
    }

    public var help: String {
        if let s: String = self.valueOfAttr(kAXHelpAttribute) {
            return s
        }
        return ""
    }

    public func value<T>() -> T? {
        if let v: T = self.valueOfAttr(kAXValueAttribute) {
            return v
        }
        return nil
    }

    public var isEnabled: Bool {
        if let enable: Bool = self.valueOfAttr(kAXEnabledAttribute) {
            return enable
        }
        return false
    }

    public var isSelected: Bool {
        if let selected: Bool = self.valueOfAttr(kAXSelectedAttribute) {
            return selected
        }
        return false
    }

    public var isFocused: Bool {
        if let focused: Bool = self.valueOfAttr(kAXFocusedAttribute) {
            return focused
        }
        return false
    }

    /// top-left corner of the element
    public var position: CGPoint? {
        // Value: An AXValueRef with type kAXValueCGPointType
        if let v: AXValue = self.valueOfAttr(kAXPositionAttribute) {
            var pos = CGPoint()
            AXValueGetValue(v, AXValueGetType(v), &pos)
            return pos
        }
        return nil
    }   

    /// The vertical and horizontal dimensions of the element
    public var size: CGSize? {
        // Value: An AXValueRef with type kAXValueCGSizeType. Units are points.
        if let v: AXValue = self.valueOfAttr(kAXSizeAttribute) {
            var size = CGSize()
            AXValueGetValue(v, AXValueGetType(v), &size)
            return size
        }
        return nil
    }

    public var frame: CGRect? {
        if let v: AXValue = self.valueOfAttr("AXFrame") {
            var rect = CGRect()
            AXValueGetValue(v, AXValueGetType(v), &rect)
            return rect
        } else {
            if let pos = self.position {
                if let size = self.size {
                    return CGRect(origin: pos, size: size)
                }
            }
        }
        return nil
    }

    public var parent: Element?{
        var value : AnyObject?
        let axError = AXUIElementCopyAttributeValue(self.ele, kAXParentAttribute as CFString, &value)
        if axError == .success {
            return Element(value as! AXUIElement)
        }
        return nil
    }

    public var children: [Element] {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self.ele, kAXChildrenAttribute as CFString, &value)
        if err == .success {
            if let arr = value as? [AXUIElement] {
                return arr.map { Element($0) }
            }
        }
        return []
    }

    public var contents: [Element] {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self.ele, kAXContentsAttribute as CFString, &value)
        if err == .success {
            if let arr = value as? [AXUIElement] {
                return arr.map { Element($0) }
            }
        }
        return []
    }

    public var windows: [Element] {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self.ele, kAXWindowsAttribute as CFString, &value)
        if err == .success {
            if let arr = value as? [AXUIElement] {
                return arr.map { Element($0) }
            }
        }
        return []
    }

    public var window: Element? {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self.ele, kAXWindowAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                if CFGetTypeID(v) == AXUIElementGetTypeID() {
                    return Element(v as! AXUIElement)
                }
            }
        }
        return nil
    }

    public var mainWindow: Element? {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self.ele, kAXMainWindowAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                if CFGetTypeID(v) == AXUIElementGetTypeID() {
                    return Element(v as! AXUIElement)
                }
            }
        }
        return nil
    }

    public var focusedWindow: Element? {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self.ele, kAXFocusedWindowAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                if CFGetTypeID(v) == AXUIElementGetTypeID() {
                    return Element(v as! AXUIElement)
                }
            }
        }
        return nil
    }

    public var focusElements: [Element] {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self.ele, kAXSharedFocusElementsAttribute as CFString, &value)
        if err == .success {
            if let arr = value as? [AXUIElement] {
                return arr.map { Element($0) }
            }
        }
        return []
    }

    public var menuBar: Element? {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self.ele, kAXMenuBarAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                if CFGetTypeID(v) == AXUIElementGetTypeID() {
                    return Element(v as! AXUIElement)
                }
            }
        }
        return nil
    }

    public var extrasMenuBar: Element? {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self.ele, kAXExtrasMenuBarAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                if CFGetTypeID(v) == AXUIElementGetTypeID() {
                    return Element(v as! AXUIElement)
                }
            }
        }
        return nil
    }

    /// return the first found element
    public func findElement(_ attrs: [String: Any]) -> Element? {
        let queue = Queue<Element>()
        queue.push_back(value: self)

        while let ele = queue.pop_front() {
            var good = true
            for (attr, value) in attrs {
                if let v: AnyObject? = ele.valueOfAttr(attr) {
                    let s = stringFromAXValue(v!)
                    if let regex = try? NSRegularExpression(pattern: "\(value)", options: []) {
                        let arr = regex.matches(in: s, options: [], range: NSMakeRange(0, s.utf16.count))
                        if arr.count == 1 {
                            // print("s: \(s), value: \(value)")
                            continue
                        }
                    }
                }

                good = false
                break
            }
            if good {
                return ele
            }

            var array: [Element]?
            if let role = attrs[kAXRoleAttribute] {
                if "\(role)" == "AXWindow" {
                    array = ele.windows
                }
            }
            if array == nil {
                array = ele.children
            }

            if array != nil && !array!.isEmpty {
                queue.push_back(contentsOf: array!)
            }
        }

        return nil
    }

    /// return all the found elements
    public func findAllElement(_ attrs: [String: Any]) -> [Element] {
        var ret: [Element] = []

        let queue = Queue<Element>()
        queue.push_back(value: self)

        while let ele = queue.pop_front() {
            var good = true
            for (attr, value) in attrs {
                if let v: AnyObject? = ele.valueOfAttr(attr) {
                    let s = stringFromAXValue(v!)
                    if let regex = try? NSRegularExpression(pattern: "\(value)", options: []) {
                        let arr = regex.matches(in: s, options: [], range: NSMakeRange(0, s.utf16.count))
                        if arr.count == 1 {
                            // print("s: \(s), value: \(value)")
                            continue
                        }
                    }
                }

                good = false
                break
            }
            if good {
                ret.append(ele)
            }

            var array: [Element]?
            if let role = attrs[kAXRoleAttribute] {
                if "\(role)" == "AXWindow" {
                    array = ele.windows
                }
            }
            if array == nil {
                array = ele.children
            }

            if array != nil && !array!.isEmpty {
                queue.push_back(contentsOf: array!)
            }
        }

        return ret
    }

    public func waitUntilElement(_ attrs: [String: Any], timeout: Int = 10) -> Element? {
        var count = 0
        while true {
            if count >= timeout {
                return nil
            }
            count += 1
            guard let e = self.findElement(attrs) else {
                sleep(1)
                continue
            }
            return e
        }
    }

    public func waitUntil(timeout: Int = 10, _ condition: ()-> Element?) -> Element? {
        var count = 0
        while true {
            if count >= timeout {
                return nil
            }
            count += 1

            guard let e = condition() else {
                sleep(1)
                continue
            }
            return e
        }
    }

    public func waitUntil(timeoutInSeconds: Int=10, _ condition: ()-> Bool) -> Bool {
        var count = 0
        while true {
            if count >= timeoutInSeconds {
                return false
            }
            count += 1

            guard condition() else {
                sleep(1)
                continue
            }
            return true
        }
    }

    public func toDict(unique: inout Set<AXUIElement>) -> Any {
        if unique.contains(self.ele) {
            return "\(self)"
        }
        unique.insert(self.ele)

        var dict: [String: Any] = [:]
        for attr in self.attrNames {
            if attr != kAXChildrenAttribute {
                if let v: AnyObject = self.valueOfAttr(attr) {
                    if attr == kAXParentAttribute {
                        dict[attr] = stringFromAXValue(v)
                    } else {
                        dict[attr] = axValueToJsonValue(v, unique: &unique)
                    }
                }
            } else {
                let children = self.children
                if !children.isEmpty {
                    dict[attr] = children.map { $0.toDict(unique: &unique) }
                }
            }
        }
        for action in self.actionNames {
            if let v = self.valueOfAction(action) {
                dict[action] = v
            }
        }

        return dict
    }

    public func toJsonString() -> String {
        var unique: Set<AXUIElement> = []
        let dict = self.toDict(unique: &unique)
        // print("dict: \(dict)")
        // self.checkJsonObj(dict)
        if !JSONSerialization.isValidJSONObject(dict) {
            print("this dict is not valid JSON")
        }

        let jsonData = try! JSONSerialization.data(withJSONObject: dict) // options: .prettyPrinted
        return String(data: jsonData, encoding: .utf8) ?? ""
    }

    public func printAttrs() {
        for attr in self.attrNames {
            if let v: AnyObject = self.valueOfAttr(attr) {
                let s = stringFromAXValue(v)
                print("\(attr): \(s)")
            }
        }
    }

    public func printActions() {
        for action in self.actionNames {
            if let v = self.valueOfAction(action) {
                print("\(action): \(v)")
            }
        }
    }

    public func take_screenshot() -> CGImage? {
        guard let frame = self.frame else {
            print("Element frame is nil")
            return nil
        }
        guard let win_frame = self.window?.frame else {
            print("Window frame is nil")
            return nil
        }
        // https://stackoverflow.com/questions/30336740/how-to-get-window-list-from-core-grapics-api-with-swift
        guard let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[ String : Any]] else {
            return nil
        }

        for dict in info {
            let window_number = dict[kCGWindowNumber as String] as? Int ?? 0
            let owner_pid = dict[kCGWindowOwnerPID as String] as? Int ?? 0
            // let owner_name = dict[kCGWindowOwnerName as String] as? String ?? "Unknown"
            let window_name = dict[kCGWindowName as String] as? String ?? "Unknown"
            let window_bounds = dict[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]

            if self.pid != owner_pid || self.window?.title != window_name {
                continue
            }
            let x = window_bounds["X"] ?? 0
            let y = window_bounds["Y"] ?? 0
            let width = window_bounds["Width"] ?? 0
            let height = window_bounds["Height"] ?? 0
            if x != win_frame.origin.x || y != win_frame.origin.y || width != win_frame.size.width || height != win_frame.size.height {
                print("Window frame does not match element frame")
                print("window bounds:", window_bounds)
                print("win_frame of ele:", win_frame)
                continue
            }

            let image = CGWindowListCreateImage(
                frame,
                .optionIncludingWindow, 
                CGWindowID(window_number), 
                [.boundsIgnoreFraming, .bestResolution]
            )

            return image

            // guard let cgImage = image else {
            //     print("Failed to create CGImage for window \(window_number)")
            //     break
            // }

            // let img = CIImage(cgImage: cgImage)

            // let context = CIContext(options: nil)
            // let url = URL(fileURLWithPath: String(format: "/tmp/screenshot_%d.png", window_number))
            // try? context.writePNGRepresentation(of: img, to: url, format: .RGBA8, colorSpace: img.colorSpace!, options: [:])

            // // take a screenshot of the window
            // // `/usr/sbin/screencapture -l <window_number> image.png`
            // Process.launchedProcess(
            //     launchPath: "/usr/sbin/screencapture",
            //     arguments: ["-l", "\(window_number)", url.path]
            // ).waitUntilExit()

            // return url
        }
        return nil
    }

    public func scan_qrcodes() -> [String]? {
        guard let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else {
            print("Detector not intialized")
            return nil
        }

        guard let cgimg = self.take_screenshot() else {
            return nil
        }

        let img = CIImage(cgImage: cgimg)

        let features = detector.features(in: img)
        let qrCodes = features.compactMap { $0 as? CIQRCodeFeature }.compactMap { $0.messageString }

        return qrCodes
    }
}
