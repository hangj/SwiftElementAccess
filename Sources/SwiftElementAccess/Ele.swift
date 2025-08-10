import Cocoa
import MyObjCTarget

extension AXUIElement {
    static let systemRef = AXUIElementCreateSystemWide()
    static var observers: [pid_t: AXObserver] = [:]

    public static func fromPid(_ pid: pid_t) -> AXUIElement {
        let kAXManualAccessibility = "AXManualAccessibility" as CFString;
        let e = AXUIElementCreateApplication(pid)
        AXUIElementSetAttributeValue(e, kAXManualAccessibility, kCFBooleanTrue)
        return e
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
            return self.appUIElement.isAppFrontMost
        }
    }

    public func setAppFrontmost() {
        if self.isApplicationUIElement {
            self.activate()
            while !self.isAppFrontMost {
                let e = AXUIElementSetAttributeValue(self, kAXFrontmostAttribute as CFString, true as CFTypeRef)
                if e != .success {
                    print("setAppFrontmost failed:", e)
                    break
                }
                sleep(1)
            }
        } else {
            self.appUIElement.setAppFrontmost()
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
                let e = AXUIElementSetAttributeValue(self, kAXMainAttribute as CFString, true as CFTypeRef)
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

    public func canSetAttr(_ name: String) -> Bool {
        var value : DarwinBoolean = false // https://stackoverflow.com/questions/33667321/what-is-darwinboolean-type-in-swift
        let err = AXUIElementIsAttributeSettable(self, name as CFString, &value)
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

    func getWindowId() -> CGWindowID? {
        guard let win = self.window else {return nil}

        var windowId = CGWindowID(0)
        let result = _AXUIElementGetWindow(win, &windowId)
        guard result == .success else { return nil }
        return windowId
    }

    public func take_screenshot() -> CGImage? {
        guard let frame = self.frame else {
            print("Element frame is nil")
            return nil
        }
        if let winId = self.getWindowId() {
            return CGWindowListCreateImage(
                frame,
                .optionIncludingWindow,
                winId,
                [.boundsIgnoreFraming, .bestResolution]
            )
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