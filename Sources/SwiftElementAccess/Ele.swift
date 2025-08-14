import Cocoa
import MyObjCTarget

/// https://stackoverflow.com/a/50901425/1936057
/// It appears, in 10.13.3 at least, that applications which are using the app sandbox will not have the alert shown. If you turn off app sandbox in the project entitlements then the alert is shown
public func checkIsProcessTrusted(prompt: Bool = true) -> Bool {
    if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
        print("sandbox is enabled.")
        // print("This app is not trusted to use Accessibility API. Please enable it in System Preferences > Security & Privacy > Privacy > Accessibility")
        return false
    }
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let opts = [promptKey: prompt] as CFDictionary
    return AXIsProcessTrustedWithOptions(opts)
}

private func carbonScreenPointFromCocoaScreenPoint(_ point : NSPoint) -> CGPoint? {
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

private func stringFromAttrValue(_ value: AnyObject) -> String {
    if value is String {
        return value as! String
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
        let ele = value as! AXUIElement
        return ele.toString()
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

    return "Unknown cfType: \(cfType)"
}

/// return dict/array/string/number
private func attrValueToJson(_ value: AnyObject, unique: inout Set<AXUIElement>) -> Any {
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
        let ele = value as! AXUIElement
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
            return arr.map { attrValueToJson($0, unique: &unique) } //.joined(separator: ",")
        }
        if cfType == CFDictionaryGetTypeID() {
            let dict = value as! [String: AnyObject]
            return dict.mapValues { attrValueToJson($0, unique: &unique) }
        }
    }

    // var s = CFCopyTypeIDDescription(cfType)!
    // return s
    // s = CFCopyDescription(value)

    return "Unknown cfType: \(cfType)."
}

extension AXUIElement {
    public typealias Callback = (_ notification: String, _ element: AXUIElement)->Void
    static let systemRef = AXUIElementCreateSystemWide()
    static var observers: [pid_t: AXObserver] = [:]
    static var notificationCallbacks: [AXUIElement: Callback] = [:]
    static var notifications: [AXUIElement: [String]] = [:]

    static private func observerCallback(_ observer:AXObserver, _ element:AXUIElement, _ notification:CFString, _ userData:UnsafeMutableRawPointer?) -> Void {
        guard let userData = userData else { return }
        let ele = Unmanaged<AXUIElement>.fromOpaque(userData).takeUnretainedValue()

        if let cb = notificationCallbacks[ele] {
            cb(notification as String, element)
        }
    }

    public static func fromPid(_ pid: pid_t) -> AXUIElement {
        let kAXManualAccessibility = "AXManualAccessibility" as CFString;
        let e = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(e, kAXManualAccessibility, kCFBooleanTrue)
        return e
    }

    /// ```
    /// AXUIElement.fromProcessName("WeChat")
    /// ```
    public static func fromProcessName(_ name: String) -> [AXUIElement] {
        var ret: [AXUIElement] = []

        NSWorkspace.shared.runningApplications.filter {
            $0.localizedName == name
        }.forEach {
            ret.append(AXUIElement.fromPid($0.processIdentifier))
        }

        return ret
    }

    /// ```
    /// AXUIElement.fromBundleIdentifier("com.tencent.xinWeChat")
    /// ```
    public static func fromBundleIdentifier(_ bundleIdentifier: String) -> [AXUIElement] {
        var ret: [AXUIElement] = []
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).forEach {
            ret.append(AXUIElement.fromPid($0.processIdentifier))
        }

        return ret
    }

    public static func fromFrontMostApplication() -> AXUIElement? {
        if let app = NSWorkspace.shared.frontmostApplication {
            return AXUIElement.fromPid(app.processIdentifier)
        }
        return nil
    }

    public static func fromPosition(x: Float, y: Float) -> AXUIElement? {
        var ele: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(AXUIElement.systemRef, x, y, &ele)
        if err == .success {
            return ele!
        }
        return nil
    }

    public static func fromPosition(_ pos: NSPoint) -> AXUIElement? {
        return fromPosition(x: Float(pos.x), y: Float(pos.y))
    }

    public static func fromMouseLocation() -> AXUIElement? {
        let cocoaPoint = NSEvent.mouseLocation
        if let point = carbonScreenPointFromCocoaScreenPoint(cocoaPoint) {
            return Self.fromPosition(point)
        }
        return nil
    }


    // -----------

    private func createObserver() -> AXObserver? {
        if let obs = Self.observers[self.pid] {
            return obs
        }

        var obs: AXObserver?
        let e = AXObserverCreate(pid, {AXUIElement.observerCallback($0, $1, $2, $3)}, &obs)
        if e == .success {
            CFRunLoopAddSource(RunLoop.current.getCFRunLoop(), AXObserverGetRunLoopSource(obs!), .defaultMode)
            Self.observers[pid] = obs!
            return obs
        }
        print("AXObserverCreate error:", e)
        return nil
    }

    public func setNotificationCallback(_ callback: @escaping Callback) {
        Self.notificationCallbacks[self] = callback
    }

    public func watch(_ notification: String) {
        if Self.notifications[self] == nil {
            Self.notifications[self] = []
        }

        if Self.notifications[self]!.contains(notification) {
            return
        }

        guard let obs = createObserver() else {return}

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let e = AXObserverAddNotification(obs, self, notification as CFString, selfPtr)
        if e == .success || e == .notificationAlreadyRegistered {
            Self.notifications[self]!.append(notification)
        }
    }

    public func unWatch(_ notification: String) {
        if Self.notifications[self] == nil { return }
        if !Self.notifications[self]!.contains(notification) { return }
        Self.notifications[self]!.removeAll { $0 == notification }
        guard let obs = createObserver() else {return}
        AXObserverRemoveNotification(obs, self, notification as CFString)
    }

    public static let allNotifications = [
        kAXMainWindowChangedNotification, kAXFocusedWindowChangedNotification, kAXFocusedUIElementChangedNotification,
        kAXApplicationActivatedNotification, kAXApplicationDeactivatedNotification, kAXApplicationHiddenNotification,
        kAXApplicationShownNotification, kAXWindowCreatedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
        kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification, kAXDrawerCreatedNotification,
        kAXSheetCreatedNotification, kAXHelpTagCreatedNotification, kAXValueChangedNotification,
        kAXUIElementDestroyedNotification, kAXElementBusyChangedNotification, kAXMenuOpenedNotification,
        kAXMenuClosedNotification, kAXMenuItemSelectedNotification, kAXRowCountChangedNotification,
        kAXRowExpandedNotification, kAXRowCollapsedNotification, kAXSelectedCellsChangedNotification,
        kAXUnitsChangedNotification, kAXSelectedChildrenMovedNotification, kAXSelectedChildrenChangedNotification,
        kAXResizedNotification, kAXMovedNotification, kAXCreatedNotification, kAXSelectedRowsChangedNotification,
        kAXSelectedColumnsChangedNotification, kAXSelectedTextChangedNotification, kAXTitleChangedNotification,
        kAXLayoutChangedNotification, kAXAnnouncementRequestedNotification,
    ]

    public func watchAll() {
        Self.allNotifications.forEach { watch($0) }
    }

    public func unWatchAll() {
        Self.allNotifications.forEach { unWatch($0) }
    }

    public func toString() -> String {
        var txtInfo = ""

        if !title.isEmpty {
            txtInfo += "title: \"\(title)\","
        }
        if !label.isEmpty {
            txtInfo += "label: \"\(label)\","
        }
        if !desc.isEmpty {
            txtInfo += "description: \"\(desc)\","
        }

        if let v: AnyObject = self.value() {
            let s = stringFromAttrValue(v)
            if !s.isEmpty {
                txtInfo += "value: \(s),"
            }
        }

        var frame = ""
        if let frm = self.frame {
            frame = "frame: \(frm)"
        }
        let hash = "hashValue: \(self.hashValue)"
        return "AXUIElement(role: \"\(role)\", pid: \(pid), \(txtInfo) enabled: \(self.isEnabled), \(frame), \(hash))"
    }

    public var trackBack: String {
        var arr: [String] = [ toString() ]
        while let p = parent {
            arr.append(p.toString())
        }
        return arr.reversed().enumerated().map {(n, s)in
            String(repeating: "  ", count: n) + s
        }
        .joined(separator: "\n")
    }

    public func findElement(_ filter: (AXUIElement)->Bool) -> AXUIElement? {
        if filter(self) {
            return self
        }
        for ch in self.children {
            if let e = ch.findElement(filter) {
                return e
            }
        }
        return nil
    }

    public func findElement(_ attrs: [String: Any]) -> AXUIElement? {
        return findElement { ele in
            for (k, v) in attrs {
                if let value: AnyObject = ele.valueOfAttr(k) {
                    if stringFromAttrValue(value) != "\(v)" {
                        return false
                    }
                } else {
                    return false
                }
            }
            return true
        }
    }

    public func findAllElements(_ filter: (AXUIElement)->Bool) -> [AXUIElement] {
        var ret: [AXUIElement] = []
        if filter(self) {
            ret.append(self)
        }
        let arr = self.children.map { $0.findAllElements( filter) }.flatMap { $0 }
        ret.append(contentsOf: arr)
        return ret
    }

    public func findAllElements(_ attrs: [String: Any]) -> [AXUIElement] {
        return findAllElements { ele in
            for (k, v) in attrs {
                if let value: AnyObject = ele.valueOfAttr(k) {
                    if stringFromAttrValue(value) != "\(v)" {
                        return false
                    }
                } else {
                    return false
                }
            }
            return true
        }
    }

    public func waitUntilElement(timeout: Int = 10, _ attrs: [String: Any]) async -> AXUIElement? {
        var count = 0
        while true {
            if count >= timeout {
                return nil
            }
            count += 1
            guard let e = self.findElement(attrs) else {
                // sleep(1)
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                continue
            }
            return e
        }
    }

    public func waitUntil(timeout: Int = 10, _ condition: ()-> AXUIElement?) async -> AXUIElement? {
        var count = 0
        while true {
            if count >= timeout {
                return nil
            }
            count += 1

            guard let e = condition() else {
                // sleep(1)
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                continue
            }
            return e
        }
    }

    public func waitUntil(timeoutInSeconds: Int=10, _ condition: ()-> Bool) async -> Bool {
        var count = 0
        while true {
            if count >= timeoutInSeconds {
                return false
            }
            count += 1

            guard condition() else {
                // sleep(1)
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                continue
            }
            return true
        }
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

    public var isAppFrontmost: Bool {
        get {
            if self.isApplicationUIElement {
                if let b: Bool = self.valueOfAttr(kAXFrontmostAttribute) {
                    return b
                }
                return false
            } else {
                return self.appUIElement.isAppFrontmost
            }
        }
        set(v) {
            if self.isApplicationUIElement {
                self.activate()
                while !self.isAppFrontmost {
                    let e = AXUIElementSetAttributeValue(self, kAXFrontmostAttribute as CFString, v as CFTypeRef)
                    if e != .success {
                        print("setAppFrontmost failed:", e)
                        break
                    }
                }
            } else {
                self.appUIElement.isAppFrontmost = true
            }
        }
    }

    public var isWindowFrontmost: Bool {
        get {
            if self.isWindowUIElement {
                if let b: Bool = self.valueOfAttr(kAXMainAttribute) {
                    return b
                }
                return false
            } else {
                return self.window?.isWindowFrontmost ?? false
            }
        }
        set(v) {
            if self.isWindowUIElement {
                while !self.isWindowFrontmost {
                    let e = AXUIElementSetAttributeValue(self, kAXMainAttribute as CFString, v as CFTypeRef)
                    if e != .success {
                        print("setWindowFrontmost failed:", e)
                        break
                    }
                }
            } else {
                self.window?.isWindowFrontmost = true
            }
        }
    }

    public var pid: pid_t {
        var pid: pid_t = 0
        if AXUIElementGetPid(self, &pid) == .success {
            return pid
        }
        return -1
    }

    public var attrNames: [String] {
        var arrNames: CFArray?
        let err = AXUIElementCopyAttributeNames(self, &arrNames)
        if err == .success {
            if let arr = arrNames as? [String] {
                return arr
            }
        }
        return []
    }

    public func valueOfAttr<T>(_ attr: String) -> T? {
        var value: AnyObject?
        let axError = AXUIElementCopyAttributeValue(self, attr as CFString, &value)
        if axError == .success {
            return value as? T
        }
        return nil
    }

    public var actionNames: [String] {
        var arrNames: CFArray?
        let err = AXUIElementCopyActionNames(self, &arrNames)
        if err == .success {
            if let arr = arrNames as? [String] {
                return arr
            }
        }
        return []
    }

    public func valueOfAction(_ action: String) -> String? {
        var value : CFString?
        let axError = AXUIElementCopyActionDescription(self, action as CFString, &value)
        if axError == .success {
            return value as String?
        }
        return nil
    }

    public func canSet(attr: String) -> Bool {
        var value : DarwinBoolean = false // https://stackoverflow.com/questions/33667321/what-is-darwinboolean-type-in-swift
        let err = AXUIElementIsAttributeSettable(self, attr as CFString, &value)
        if err == .success {
            return value.boolValue
        }
        return false
    }

    public func performAction(_ name: String) -> AXError {
        return AXUIElementPerformAction(self, name as CFString)
    }

    public func setTimeout(_ timeoutInSeconds: Float) {
        AXUIElementSetMessagingTimeout(self, timeoutInSeconds)
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
    /// assert(AXUIElement.fromProcessName("WeChat")[0].isApplicationUIElement())
    /// ```
    public var isApplicationUIElement: Bool {
        self.role == kAXApplicationRole
    }

    public var isWindowUIElement: Bool {
        self.role == kAXWindowRole
    }

    public var appUIElement: AXUIElement {
        if self.isApplicationUIElement {
            return self
        } else {
            return Self.fromPid(self.pid)
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

    public var selectedText: String {
        if let s: String = self.valueOfAttr(kAXSelectedTextAttribute) {
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

    public func value<T>(type: T.Type) -> T? {
        if let v: T = self.valueOfAttr(kAXValueAttribute) {
            return v
        }
        return nil
    }

    public func setValue<T>(_ v: T) -> Bool {
        let e = AXUIElementSetAttributeValue(self, kAXValueAttribute as CFString, v as CFTypeRef)
        if e != .success {
            print("setValue failed:", e)
        }
        return e == .success
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
        get {
            // Value: An AXValueRef with type kAXValueCGPointType
            if let v: AXValue = self.valueOfAttr(kAXPositionAttribute) {
                var pos = CGPoint()
                AXValueGetValue(v, AXValueGetType(v), &pos)
                return pos
            }
            return nil
        }
        set(pos){
            guard var pos = pos else { return }
            let ref = AXValueCreate(.cgPoint, &pos)
            let e = AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, ref as CFTypeRef)
            if e != .success {
                print("set position failed:", e)
            }
        }
    }   

    /// The vertical and horizontal dimensions of the element
    public var size: CGSize? {
        get {
            // Value: An AXValueRef with type kAXValueCGSizeType. Units are points.
            if let v: AXValue = self.valueOfAttr(kAXSizeAttribute) {
                var size = CGSize()
                AXValueGetValue(v, AXValueGetType(v), &size)
                return size
            }
            return nil
        }
        set(sz) {
            guard var sz = sz else { return }
            let ref = AXValueCreate(.cgSize, &sz)
            let e = AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, ref as CFTypeRef)
            if e != .success {
                print("set size failed:", e)
            }
        }
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

    public var parent: AXUIElement?{
        var value : AnyObject?
        let axError = AXUIElementCopyAttributeValue(self, kAXParentAttribute as CFString, &value)
        if axError == .success {
            return (value as! AXUIElement)
        }
        return nil
    }

    public var children: [AXUIElement] {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXChildrenAttribute as CFString, &value)
        if err == .success {
            if let arr = value as? [AXUIElement] {
                return arr
            }
        }
        return []
    }

    public var visibleChildren: [AXUIElement] {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXVisibleChildrenAttribute as CFString, &value)
        if err == .success {
            if let arr = value as? [AXUIElement] {
                return arr
            }
        }
        return []
    }

    public var selectedChildren: [AXUIElement] {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXSelectedChildrenAttribute as CFString, &value)
        if err == .success {
            if let arr = value as? [AXUIElement] {
                return arr
            }
        }
        return []
    }

    public var contents: [AXUIElement] {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXContentsAttribute as CFString, &value)
        if err == .success {
            if let arr = value as? [AXUIElement] {
                return arr
            }
        }
        return []
    }

    public var windows: [AXUIElement] {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXWindowsAttribute as CFString, &value)
        if err == .success {
            if let arr = value as? [AXUIElement] {
                return arr
            }
        }
        return []
    }

    public var window: AXUIElement? {
        if self.isWindowUIElement { return self }
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXWindowAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                if CFGetTypeID(v) == AXUIElementGetTypeID() {
                    return (v as! AXUIElement)
                }
            }
        }
        return nil
    }

    public var mainWindow: AXUIElement? {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXMainWindowAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                if CFGetTypeID(v) == AXUIElementGetTypeID() {
                    return (v as! AXUIElement)
                }
            }
        }
        return nil
    }

    public var focusedWindow: AXUIElement? {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXFocusedWindowAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                if CFGetTypeID(v) == AXUIElementGetTypeID() {
                    return (v as! AXUIElement)
                }
            }
        }
        return nil
    }

    public var focusElements: [AXUIElement] {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXSharedFocusElementsAttribute as CFString, &value)
        if err == .success {
            if let arr = value as? [AXUIElement] {
                return arr
            }
        }
        return []
    }

    public var menuBar: AXUIElement? {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXMenuBarAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                if CFGetTypeID(v) == AXUIElementGetTypeID() {
                    return (v as! AXUIElement)
                }
            }
        }
        return nil
    }

    public var extrasMenuBar: AXUIElement? {
        var value : AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXExtrasMenuBarAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                if CFGetTypeID(v) == AXUIElementGetTypeID() {
                    return (v as! AXUIElement)
                }
            }
        }
        return nil
    }

    public var hidden: Bool? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(self, kAXHiddenAttribute as CFString, &value)
        if err == .success {
            if let v = value {
                return v as? Bool
            }
        }
        return nil
    }

    public func toDict(unique: inout Set<AXUIElement>) -> Any {
        if unique.contains(self) {
            return "\(self)"
        }
        unique.insert(self)

        var dict: [String: Any] = [:]
        for attr in self.attrNames {
            if attr == kAXChildrenAttribute {
                let children = self.children
                if !children.isEmpty {
                    dict[attr] = children.map { $0.toDict(unique: &unique) }
                }
                continue
            }
            if attr == kAXVisibleChildrenAttribute {
                let children = self.visibleChildren
                if !children.isEmpty {
                    dict[attr] = children.map { $0.toDict(unique: &unique) }
                }
                continue
            }
            if attr == kAXSelectedChildrenAttribute {
                let children = self.selectedChildren
                if !children.isEmpty {
                    dict[attr] = children.map { $0.toDict(unique: &unique) }
                }
                continue
            }

            if let v: AnyObject = self.valueOfAttr(attr) {
                if attr == kAXParentAttribute {
                    dict[attr] = stringFromAttrValue(v)
                } else {
                    dict[attr] = attrValueToJson(v, unique: &unique)
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

        assert(JSONSerialization.isValidJSONObject(dict))

        let jsonData = try! JSONSerialization.data(withJSONObject: dict) // options: .prettyPrinted
        return String(data: jsonData, encoding: .utf8) ?? ""
    }

    public func printAttrs() {
        for attr in self.attrNames {
            if let v: AnyObject = self.valueOfAttr(attr) {
                let s = stringFromAttrValue(v)
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

    public var windowId: CGWindowID? {
        guard let win = self.window else {return nil}

        var winId = CGWindowID(0)
        let result = _AXUIElementGetWindow(win, &winId)
        guard result == .success else { return nil }
        return winId
    }

    public func take_screenshot(path: String? = nil) -> CGImage? {
        guard let frame = self.frame else {
            print("Element frame is nil")
            return nil
        }
        var window_number = windowId
        if window_number == nil {
            guard let win_frame = self.window?.frame else {
                print("Window frame is nil")
                return nil
            }

            // https://stackoverflow.com/questions/30336740/how-to-get-window-list-from-core-grapics-api-with-swift
            guard let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[ String : Any]] else {
                return nil
            }
            window_number = info.first(where: { dict in
                // let window_number = dict[kCGWindowNumber as String] as? UInt32 ?? 0
                let owner_pid = dict[kCGWindowOwnerPID as String] as? pid_t ?? 0
                // let owner_name = dict[kCGWindowOwnerName as String] as? String ?? "Unknown"
                let window_name = dict[kCGWindowName as String] as? String ?? "Unknown"
                let window_bounds = dict[kCGWindowBounds as String] as? [String: CGFloat] ?? [:]

                if self.pid != owner_pid || self.window?.title != window_name {
                    return false
                }
                let x = window_bounds["X"] ?? 0
                let y = window_bounds["Y"] ?? 0
                let width = window_bounds["Width"] ?? 0
                let height = window_bounds["Height"] ?? 0
                if x != win_frame.origin.x || y != win_frame.origin.y || width != win_frame.size.width || height != win_frame.size.height {
                    return false
                }
                return true
            })?[kCGWindowNumber as String] as? UInt32
        }
        if let winId = window_number {
            guard let cgImage = CGWindowListCreateImage(
                frame,
                .optionIncludingWindow,
                winId,
                [.boundsIgnoreFraming, .bestResolution]
            ) else { return nil }

            if let path = path {
                let img = CIImage(cgImage: cgImage)
                try? CIContext(options: nil).writePNGRepresentation(of: img, to: URL(fileURLWithPath: path), format: .RGBA8, colorSpace: img.colorSpace!, options: [:])
            }
            return cgImage
        }

        // // take a screenshot of the window
        // // `/usr/sbin/screencapture -l <window_number> image.png`
        // Process.launchedProcess(
        //     launchPath: "/usr/sbin/screencapture",
        //     arguments: ["-l", "\(window_number)", url.path]
        // ).waitUntilExit()

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