import Cocoa
import MyObjCTarget

#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif


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

    /// https://stackoverflow.com/a/50901425/1936057
    /// It appears, in 10.13.3 at least, that applications which are using the app sandbox will not have the alert shown. If you turn off app sandbox in the project entitlements then the alert is shown
    public static func checkIsProcessTrusted(prompt: Bool = true) -> Bool {
        if ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil {
            print("sandbox is enabled.")
            // print("This app is not trusted to use Accessibility API. Please enable it in System Preferences > Security & Privacy > Privacy > Accessibility")
            return false
        }
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let opts = [promptKey: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }

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

    /// Returns the accessibility object at the specified position in top-left relative screen coordinates
    public static func fromPosition(x: Float, y: Float) -> AXUIElement? {
        var ele: AXUIElement?
        let err = AXUIElementCopyElementAtPosition(AXUIElement.systemRef, x, y, &ele)
        if err == .success {
            return ele!
        }
        print("AXUIElementCopyElementAtPosition error:", err)
        return nil
    }

    /// Returns the accessibility object at the specified position in top-left relative screen coordinates
    public static func fromPosition(_ pos: NSPoint) -> AXUIElement? {
        return fromPosition(x: Float(pos.x), y: Float(pos.y))
    }

    public static func fromMouseLocation() -> AXUIElement? {
        var point = NSEvent.mouseLocation
        point.y = NSScreen.screens[0].frame.height - point.y
        return Self.fromPosition(point)
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

        if !subRole.isEmpty {
            txtInfo += "subrole: \"\(subRole)\","
        }
        if !title.isEmpty {
            txtInfo += "title: \"\(title)\","
        }
        if !label.isEmpty {
            txtInfo += "label: \"\(label)\","
        }
        if !desc.isEmpty {
            txtInfo += "description: \"\(desc)\","
        }
        if !help.isEmpty {
            txtInfo += "help: \"\(help)\","
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
        return "AXUIElement(role: \"\(role)\", \(txtInfo) enabled: \(self.isEnabled), \(frame), pid: \(pid), \(hash))"
    }

    public var trackBack: String {
        var arr: [String] = [ toString() ]
        var e = self

        while let p = e.parent {
            e = p
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
            // print("app.isActive:", app.isActive)
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
                if !self.isAppFrontmost {
                    let e = AXUIElementSetAttributeValue(self, kAXFrontmostAttribute as CFString, v as CFTypeRef)
                    if e != .success {
                        print("setAppFrontmost failed:", e)
                        return
                    }
                    print("setAppFrontmost success")
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
        print("AXUIElementGetPid error")
        return -1
    }

    public var psn: ProcessSerialNumber? {
        /// https://stackoverflow.com/questions/70823422/how-to-get-the-process-serial-number-for-an-external-process-under-macos
        /// lsappinfo find bundleid="com.tencent.xinWeChat" pid=48600
        /// lsappinfo find pid=48600
        /// output: `ASN:0x0-0x1f10f0f-"微信":`
        /// `var psn = ProcessSerialNumber(highLongOfPSN: 0, lowLongOfPSN: 0x1f10f0f)`

        var psn = ProcessSerialNumber()

        if let HIServiceBundle = CFBundleGetBundleWithIdentifier("com.apple.HIServices" as CFString), let functionPtr = CFBundleGetFunctionPointerForName(HIServiceBundle, "GetProcessForPID" as CFString) {
            let GetProcessForPID = unsafeBitCast(functionPtr,to:(@convention(c)(pid_t, UnsafePointer<ProcessSerialNumber>)->OSStatus).self)
            if noErr == GetProcessForPID(pid, &psn) {
                return psn
            }
        }

        /// https://stackoverflow.com/questions/75163201/how-can-i-get-the-dock-badge-text-of-other-applications

        guard let CoreServiceBundle = CFBundleGetBundleWithIdentifier("com.apple.CoreServices" as CFString) else {
            print("CoreServiceBundle not found")
            return nil
        }

        guard let functionPtr_LSCopyRunningApplicationArray = CFBundleGetFunctionPointerForName(CoreServiceBundle, "_LSCopyRunningApplicationArray" as CFString) else {
            print("_LSCopyRunningApplicationArray not found")
            return nil
        }

        let GetRunningApplicationArray = { () -> [CFTypeRef] in
            return unsafeBitCast(functionPtr_LSCopyRunningApplicationArray, to: (@convention(c)(UInt) -> [CFTypeRef]).self)(0xfffffffe)
        }

        guard let functionPtr_LSCopyApplicationInformation = CFBundleGetFunctionPointerForName(CoreServiceBundle, "_LSCopyApplicationInformation" as CFString) else {
            print("_LSCopyApplicationInformation not found")
            return nil
        }
        let GetApplicationInformation: (CFTypeRef) -> [String:CFTypeRef] = { app in
            return unsafeBitCast(functionPtr_LSCopyApplicationInformation, to: (@convention(c)(UInt, Any, Any) -> [String:CFTypeRef]).self)(0xffffffff, app, 0)
        }

        guard let functionPtr_LSASNExtractHighAndLowParts = CFBundleGetFunctionPointerForName(CoreServiceBundle, "_LSASNExtractHighAndLowParts" as CFString) else {
            print("_LSASNExtractHighAndLowParts not found")
            return nil
        }
        let LSASNExtractHighAndLowParts = { (asn: CFTypeRef, high: UnsafeMutablePointer<UInt32>, low: UnsafeMutablePointer<UInt32>) -> Void in
            return unsafeBitCast(functionPtr_LSASNExtractHighAndLowParts, to: (@convention(c)(CFTypeRef, UnsafeMutablePointer<UInt32>, UnsafeMutablePointer<UInt32>)->Void).self)(asn, high, low)
        }

        // let LSASNToUInt64 = { (asn: CFTypeRef) -> UInt64 in
        //     let functionPtr = CFBundleGetFunctionPointerForName(CoreServiceBundle, "_LSASNToUInt64" as CFString)
        //     return unsafeBitCast(functionPtr,to:(@convention(c)(CFTypeRef)->UInt64).self)(asn)
        // }

        let appInfos = GetRunningApplicationArray().map { GetApplicationInformation($0) }
        guard let info = appInfos.first(where: { $0["pid"] as? pid_t == pid }) else {
            print("App with pid \(pid) not found")
            return nil
        }
        guard let lsasn = info["LSASN"] else {
            print("LSASN not found")
            return nil
        }

        LSASNExtractHighAndLowParts(lsasn, &psn.highLongOfPSN, &psn.lowLongOfPSN)
        return psn
    }

    public func sendReopenEvent() -> Bool {
        guard var psn = self.psn else {
            print("psn not found")
            return false
        }

        var target = AEDesc()
        if noErr != AECreateDesc( typeProcessSerialNumber, &psn, MemoryLayout.size(ofValue: psn), &target) {
            print("AECreateDesc error")
            return false
        }

        var event = AppleEvent()
        let e = AECreateAppleEvent ( kCoreEventClass,
                kAEReopenApplication,
                &target,
                Int16(kAutoGenerateReturnID),
                Int32(kAnyTransactionID),
                &event)
        if e != noErr {
            print("AECreateAppleEvent error:", e)
            return false
        }

        var reply = AppleEvent()
        let r = AESendMessage(&event, &reply, AESendMode(kAEWaitReply), kAEDefaultTimeout)
        if r != noErr {
            print("AESendMessage error:", r)
            return false
        }

        return r == noErr
    }

    public var bundleIdentifier: String? {
        return NSRunningApplication(processIdentifier: self.pid)?.bundleIdentifier
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

    public var placeholder: String {
        if let s: String = self.valueOfAttr(kAXPlaceholderValueAttribute) {
            return s
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

    /// top-left corner of the element, display coordinate(origin at upper-left corner)
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

    /// display coordinate(origin at upper-left corner)
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
        if result == .success { return winId }

        guard let win_frame = self.window?.frame else {
            print("Window frame is nil")
            return nil
        }

        // https://stackoverflow.com/questions/30336740/how-to-get-window-list-from-core-grapics-api-with-swift
        guard let info = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[ String : Any]] else {
            print("CGWindowListCopyWindowInfo failed.")
            return nil
        }
        if let winId = info.first(where: { dict in
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
        })?[kCGWindowNumber as String] as? UInt32 {
            return winId
        }

        return nil
    }

    public static func captureImage(screen: NSScreen, path: String) async -> CGImage? {
        guard let cgImage = await captureImage(screen: screen) else {
            return nil
        }

        let img = CIImage(cgImage: cgImage)
        do {
            try CIContext(options: nil).writePNGRepresentation(of: img, to: URL(fileURLWithPath: path), format: .RGBA8, colorSpace: img.colorSpace!, options: [:])
        }catch{
            print("image save error:", error)
        }

        return cgImage
    }

    public static func captureImage(screen: NSScreen) async -> CGImage? {
        var origin = NSScreen.main!.frame.origin
        origin.y = NSScreen.main!.frame.maxY

        var frame = screen.frame
        frame.origin.y = origin.y - frame.maxY
        frame.origin.x = frame.minX - origin.x

        return await captureImage(screenBounds: frame)
    }

    /// screenBounds: origin at upper-left corner of the main display
    /// If you want the whole screenshot of all the screens, you can pass NSRect.infinite to the rect
    public static func captureImage(screenBounds: CGRect, path: String) async -> CGImage? {
        guard let cgImage = await captureImage(screenBounds: screenBounds) else {
            return nil
        }

        let img = CIImage(cgImage: cgImage)
        do {
            try CIContext(options: nil).writePNGRepresentation(of: img, to: URL(fileURLWithPath: path), format: .RGBA8, colorSpace: img.colorSpace!, options: [:])
        }catch{
            print("image save error:", error)
        }

        return cgImage
    }

    /// screenBounds: origin at upper-left corner of the main display
    /// If you want the whole screenshot of all the screens, you can pass NSRect.infinite to the rect
    public static func captureImage(screenBounds: NSRect) async -> CGImage? {
        var rect = screenBounds

        if screenBounds == .infinite || screenBounds == .null {
            var origin = NSScreen.main!.frame.origin
            origin.y = NSScreen.main!.frame.maxY

            var frame = NSScreen.main!.frame
            NSScreen.screens.forEach { frame = frame.union($0.frame) }
            frame.origin.y = origin.y - frame.maxY
            frame.origin.x = frame.minX - origin.x

            rect = frame
        }

        #if canImport(ScreenCaptureKit)
            if #available(macOS 15.2, *) {
                do {
                    return try await SCScreenshotManager.captureImage(in: rect)
                }catch{
                    print("error:", error)
                }
            }
        #endif

        return CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        )
    }

    /// return the screenshot of current AXUIElement
    public func take_screenshot() async -> CGImage? {
        guard let frame = self.frame else {
            print("Element frame is nil")
            return nil
        }

        guard let winId = windowId else {
            print("windowId not found!")
            return nil
        }

        #if canImport(ScreenCaptureKit)
        if #available(macOS 14.0, *) {
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                // guard let mainDisplayID = NSScreen.main?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
                // let display = content!.displays.first(where: { $0.displayID == mainDisplayID }) else { return nil }
                // let filter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
                guard let win = content.windows.first(where: { $0.windowID == winId }) else {
                    print("windowID not found")
                    return nil
                }
                let filter = SCContentFilter(desktopIndependentWindow: win)

                let cfg = SCStreamConfiguration()
                cfg.width = Int(frame.width * NSScreen.screens[0].backingScaleFactor)
                cfg.height = Int(frame.height * NSScreen.screens[0].backingScaleFactor)
                cfg.sourceRect = frame.offsetBy(dx: -win.frame.origin.x, dy: -win.frame.origin.y)
                cfg.captureResolution = .best
                cfg.preservesAspectRatio = true
                cfg.capturesAudio = false
                cfg.scalesToFit = false
                cfg.showsCursor = false
                return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: cfg)
            } catch {
                print("error:", error)
            }
        }
        #endif

        guard let cgImage = CGWindowListCreateImage(
            frame,
            .optionIncludingWindow,
            winId,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            print("CGWindowListCreateImage failed. If you call this function from outside of a GUI security session or when no window server is running, this function returns NULL")
            return nil
        }

        return cgImage
    }

    /// save the screenshot of current AXUIElement, and return it
    public func take_screenshot(path: String) async -> CGImage? {
        guard let cgImage = await take_screenshot() else { return nil }

        do {
            let img = CIImage(cgImage: cgImage)
            try CIContext(options: nil).writePNGRepresentation(of: img, to: URL(fileURLWithPath: path), format: .RGBA8, colorSpace: img.colorSpace!, options: [:])
        } catch {
            print("error:", error)
        }
        return cgImage

        // // take a screenshot of the window
        // // `/usr/sbin/screencapture -l <window_number> image.png`
        // Process.launchedProcess(
        //     launchPath: "/usr/sbin/screencapture",
        //     arguments: ["-l", "\(window_number)", url.path]
        // ).waitUntilExit()
    }

    public func scan_qrcodes() async -> [String]? {
        guard let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: nil,
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else {
            print("Detector not intialized")
            return nil
        }

        guard let cgimg = await take_screenshot() else {
            return nil
        }

        let img = CIImage(cgImage: cgimg)

        let features = detector.features(in: img)
        let qrCodes = features.compactMap { $0 as? CIQRCodeFeature }.compactMap { $0.messageString }

        return qrCodes
    }

    // -------------------------------------

    public static func sendKeyCode(_ keyCode: CGKeyCode, masks: CGEventFlags = [], toPid pid: pid_t? = nil) {
        let source = CGEventSource(stateID: .hidSystemState)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            print("CGEvent init failed")
            return
        }

        down.flags = masks
        up.flags = masks

        if let pid = pid, pid >= 0 {
            down.postToPid(pid)
            up.postToPid(pid)
        } else {
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    public static func copy(str: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        return pasteboard.setString(str, forType: .string)
    }

    /// Move the mouse to a point in global screen coordinates(origin at upper-left corner of the main display)
    public static func mouseMove(to: NSPoint) -> Bool {
        // Need to read the mouse location first, Or the following `CGDisplayMoveCursorToPoint(0, to)` call may stuck
        let _ = NSEvent.mouseLocation // The current mouse location in screen coordinates, the screen coordinate system's origin is at the lower-left corner of the primary screen, with positive values increasing to the right and up

        let displayID = NSScreen.screens[0].deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0

        // https://developer.apple.com/documentation/coregraphics/cgdisplaymovecursortopoint(_:_:)
        // Moves the mouse cursor to a specified point relative to the upper-left corner of the displayID
        return CGDisplayMoveCursorToPoint(displayID, to) == .success
    }

    /// Perform a left click at a point in display coordinates(origin is at the upper-left corner)
    /// `AXUIElement.checkIsProcessTrusted()` first
    public static func mouseLeftClick(position: NSPoint? = nil) {
        var mouseLoc = NSEvent.mouseLocation
        mouseLoc.y = NSScreen.screens[0].frame.height - mouseLoc.y

        // The coordinates of a point in local display space. The origin is the upper-left corner of the specified display.
        let adjustedPoint = position ?? mouseLoc

        let source = CGEventSource(stateID: CGEventSourceStateID.hidSystemState)
        let down = CGEvent(mouseEventSource: source, mouseType: CGEventType.leftMouseDown,
                            mouseCursorPosition: adjustedPoint, mouseButton: CGMouseButton.left)
        let up = CGEvent(mouseEventSource: source, mouseType: CGEventType.leftMouseUp,
                            mouseCursorPosition: adjustedPoint, mouseButton: CGMouseButton.left)
        down?.post(tap: CGEventTapLocation.cghidEventTap)
        up?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}
