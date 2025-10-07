import Cocoa
import IOKit.pwr_mgt
#if canImport(ScreenCaptureKit)
import ScreenCaptureKit
#endif

public extension CGEventFlags {
    /* Device-independent modifier key bits. */
    static let command = maskCommand
    static let control = maskControl
    static let option = maskAlternate
    static let alt = option
    static let alternate = alt
    static let shift = maskShift
    static let alphaShift = maskAlphaShift
    static let capsLock = alphaShift

    /* Special key identifiers. */
    static let help = maskHelp
    static let secondaryFn = maskSecondaryFn

    /* Identifies key events from numeric keypad area on extended keyboards. */
    static let numericPad = maskNumericPad

    /* Indicates if mouse/pen movement events are not being coalesced */
    static let nonCoalesced = maskNonCoalesced
}

public class Auto {
    public static func copy(str: String) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.declareTypes([.string], owner: nil)
        return pasteboard.setString(str, forType: .string)
    }

    public static func write(_ text: String) {
        for c in text {
            if let (key, IsShiftedKey) = Key.from(char: c) {
                key.click(masks: IsShiftedKey ? .maskShift : [])
                Thread.sleep(forTimeInterval: 0.1)
            } else {
                print("Unsupported character: \(c)")
            }
        }
    }

    public static func sendKey(_ key: Key, masks: CGEventFlags = [], toPid pid: pid_t? = nil) {
        key.click(masks: masks, toPid: pid)
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

    /// save and return the screenshot of the screen
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

    /// return the screenshot of the screen
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

        if let cgImage = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            .bestResolution
        ) {
            return cgImage
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

        return nil
    }

    private static var noSleepAssertionID: IOPMAssertionID = 0
    private static var noSleepEnabled = false // Could probably be replaced by a boolean value, for example 'isBlockingSleep', just make sure 'IOPMAssertionRelease' doesn't get called, if 'IOPMAssertionCreateWithName' failed.

    /// This function acts like `caffeinate -id` which prevents the system from sleeping due to inactivity.
    public static func disableScreenSleep(reason: String = "Unknown reason") -> Bool {
        if noSleepEnabled { return true }
        let r = IOPMAssertionCreateWithName(kIOPMAssertionTypeNoDisplaySleep as CFString,
                                                IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                reason as CFString,
                                                &noSleepAssertionID)
        if r == kIOReturnSuccess {
            noSleepEnabled = true
            return true
        }
        return false
    }

    public static func enableScreenSleep() -> Bool {
        if !noSleepEnabled { return true }

        if IOPMAssertionRelease(noSleepAssertionID) == kIOReturnSuccess {
            noSleepEnabled = false
            return true
        }
        return false
    }

    public static func lockFile(_ path: String) throws -> Bool {
        let fd = open(path, O_CREAT | O_RDWR, 0o644)
        if fd < 0 {
            let cErrno = errno
            // Get a human-readable description of the error
            let errorMessage = String(cString: strerror(cErrno))
            let userInfo: [String: Any] = [
                NSLocalizedDescriptionKey: "C function failed with errno \(cErrno): \(errorMessage)"
            ]
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(cErrno), userInfo: userInfo)
        }
        var lock = flock(l_start: 0, l_len: 0, l_pid: getpid(), l_type: Int16(F_WRLCK), l_whence: Int16(SEEK_SET))
        return fcntl(fd, F_SETLK, &lock) == 0
    }


    /// https://gist.github.com/dagronf/51a1ccf92f528ffab7183e3bdc457ac4
    public enum Key: Int {

        //    *  Discussion:
        //    *    These constants are the virtual keycodes defined originally in
        //    *    Inside Mac Volume V, pg. V-191. They identify physical keys on a
        //    *    keyboard. Those constants with "ANSI" in the name are labeled
        //    *    according to the key position on an ANSI-standard US keyboard.
        //    *    For example, kVK_ANSI_A indicates the virtual keycode for the key
        //    *    with the letter 'A' in the US keyboard layout. Other keyboard
        //    *    layouts may have the 'A' key label on a different physical key;
        //    *    in this case, pressing 'A' will generate a different virtual
        //    *    keycode.
        //    */

        case A = 0x00 // kVK_ANSI_A
        case S = 0x01
        case D = 0x02
        case F = 0x03
        case H = 0x04
        case G = 0x05
        case Z = 0x06
        case X = 0x07
        case C = 0x08
        case V = 0x09
        case B = 0x0B
        case Q = 0x0C
        case W = 0x0D
        case E = 0x0E
        case R = 0x0F
        case Y = 0x10
        case T = 0x11
        case _1 = 0x12
        case _2 = 0x13
        case _3 = 0x14
        case _4 = 0x15
        case _6 = 0x16
        case _5 = 0x17
        case equal = 0x18
        case _9 = 0x19
        case _7 = 0x1A
        case minus = 0x1B
        case _8 = 0x1C
        case _0 = 0x1D
        public static let zero = _0
        public static let one = _1
        public static let two = _2
        public static let three = _3
        public static let four = _4
        public static let five = _5
        public static let six = _6
        public static let seven = _7
        public static let eight = _8
        public static let nine = _9

        public static let a = A
        public static let b = B
        public static let c = C
        public static let d = D
        public static let e = E
        public static let f = F
        public static let g = G
        public static let h = H
        public static let i = I
        public static let j = J
        public static let k = K
        public static let l = L
        public static let m = M
        public static let n = N
        public static let o = O
        public static let p = P
        public static let q = Q
        public static let r = R
        public static let s = S
        public static let t = T
        public static let u = U
        public static let v = V
        public static let w = W
        public static let x = X
        public static let y = Y
        public static let z = Z

        case rightBracket = 0x1E
        case O = 0x1F
        case U = 0x20
        case leftBracket = 0x21
        case I = 0x22
        case P = 0x23
        case L = 0x25
        case J = 0x26
        case quote = 0x27
        case K = 0x28
        case semicolon = 0x29
        case backslash = 0x2A // \
        case comma = 0x2B
        case slash = 0x2C // /
        public static let forwardSlash = slash
        case N = 0x2D
        case M = 0x2E
        case period = 0x2F
        case grave = 0x32 // `

        case keypadDecimal = 0x41
        case keypadMultiply = 0x43
        case keypadPlus = 0x45
        case keypadClear = 0x47
        case keypadDivide = 0x4B
        case keypadEnter = 0x4C
        public static let enter = keypadEnter
        case keypadMimus = 0x4E
        case keypadEquals = 0x51
        case keypad0 = 0x52
        case keypad1 = 0x53
        case keypad2 = 0x54
        case keypad3 = 0x55
        case keypad4 = 0x56
        case keypad5 = 0x57
        case keypad6 = 0x58
        case keypad7 = 0x59
        case keypad8 = 0x5B
        case keypad9 = 0x5C

        /* keycodes for keys that are independent of keyboard layout */

        case `return` = 0x24
        public static let returnKey = Self.return

        case tab = 0x30
        case space = 0x31
        case delete = 0x33
        case escape = 0x35
        case command = 0x37
        case shift = 0x38
        case capslock = 0x39
        case option = 0x3A
        case control = 0x3B
        case rightCommand = 0x36
        case rightShift = 0x3C
        case rightOption = 0x3D
        case rightControl = 0x3E
        case fn = 0x3F
        case f17 = 0x40
        case volumeUp = 0x48 // kVK_VolumeUp
        case volumeDown = 0x49 // kVK_VolumeDown
        case mute = 0x4A
        case f18 = 0x4F
        case f19 = 0x50
        case f20 = 0x5A
        case f5 = 0x60
        case f6 = 0x61
        case f7 = 0x62
        case f3 = 0x63
        case f8 = 0x64
        case f9 = 0x65
        case f11 = 0x67
        case f13 = 0x69
        case f16 = 0x6A
        case f14 = 0x6B
        case f10 = 0x6D
        case f12 = 0x6F
        case f15 = 0x71
        case help = 0x72
        case home = 0x73
        case pageUp = 0x74
        case forwardDelete = 0x75
        case f4 = 0x76
        case `end` = 0x77
        case f2 = 0x78
        case pageDown = 0x79
        case f1 = 0x7A
        case leftArrow = 0x7B
        case rightArrow = 0x7C
        case downArrow = 0x7D
        case upArrow = 0x7E

        /* ISO keyboards only*/

        case isoSection = 0x0A

        /* JIS keyboards only*/

        case jis_yen = 0x5D
        case jis_underscore = 0x5E
        case jis_keypadComma = 0x5F
        case jis_eisu = 0x66
        case jis_kana = 0x68


        public typealias IsShiftedKey = Bool
        public static func from(char: Character) -> (Key, IsShiftedKey)? {
            switch char {
            case "a": return (.A, false)
            case "b": return (.B, false)
            case "c": return (.C, false)
            case "d": return (.D, false)
            case "e": return (.E, false)
            case "f": return (.F, false)
            case "g": return (.G, false)
            case "h": return (.H, false)
            case "i": return (.I, false)
            case "j": return (.J, false)
            case "k": return (.K, false)
            case "l": return (.L, false)
            case "m": return (.M, false)
            case "n": return (.N, false)
            case "o": return (.O, false)
            case "p": return (.P, false)
            case "q": return (.Q, false)
            case "r": return (.R, false)
            case "s": return (.S, false)
            case "t": return (.T, false)
            case "u": return (.U, false)
            case "v": return (.V, false)
            case "w": return (.W, false)
            case "x": return (.X, false)
            case "y": return (.Y, false)
            case "z": return (.Z, false)

            case "A": return (.A, true)
            case "B": return (.B, true)
            case "C": return (.C, true)
            case "D": return (.D, true)
            case "E": return (.E, true)
            case "F": return (.F, true)
            case "G": return (.G, true)
            case "H": return (.H, true)
            case "I": return (.I, true)
            case "J": return (.J, true)
            case "K": return (.K, true)
            case "L": return (.L, true)
            case "M": return (.M, true)
            case "N": return (.N, true)
            case "O": return (.O, true)
            case "P": return (.P, true)
            case "Q": return (.Q, true)
            case "R": return (.R, true)
            case "S": return (.S, true)
            case "T": return (.T, true)
            case "U": return (.U, true)
            case "V": return (.V, true)
            case "W": return (.W, true)
            case "X": return (.X, true)
            case "Y": return (.Y, true)
            case "Z": return (.Z, true)

            case "0": return (.zero, false)
            case "1": return (.one, false)
            case "2": return (.two, false)
            case "3": return (.three, false)
            case "4": return (.four, false)
            case "5": return (.five, false)
            case "6": return (.six, false)
            case "7": return (.seven, false)
            case "8": return (.eight, false)
            case "9": return (.nine, false)
            case " ": return (.space, false)
            case "\t": return (.tab, false)
            case "\n": return (.returnKey, false)
            case "\r": return (.returnKey, false)
            case "=": return (.equal, false)
            case "-": return (.minus, false)
            case ";": return (.semicolon, false)
            case "'": return (.quote, false)
            case ",": return (.comma, false)
            case ".": return (.period, false)
            case "/": return (.forwardSlash, false)
            case "\\": return (.backslash, false)
            case "`": return (.grave, false)
            case "[": return (.leftBracket, false)
            case "]": return (.rightBracket, false)

            case "!": return (.one, true)      // Shift+1
            case "@": return (.two, true)      // Shift+2
            case "#": return (.three, true)    // Shift+3
            case "$": return (.four, true)     // Shift+4
            case "%": return (.five, true)     // Shift+5
            case "^": return (.six, true)      // Shift+6
            case "&": return (.seven, true)    // Shift+7
            case "*": return (.eight, true)    // Shift+8
            case "(": return (.nine, true)     // Shift+9
            case ")": return (.zero, true)     // Shift+0
            case "_": return (.minus, true)    // Shift+-
            case "+": return (.equal, true)   // Shift+=
            case "{": return (.leftBracket, true)  // Shift+[
            case "}": return (.rightBracket, true) // Shift+]
            case "|": return (.backslash, true)    // Shift+\
            case ":": return (.semicolon, true)    // Shift+;
            case "\"": return (.quote, true)  // Shift+'
            case "<": return (.comma, true)        // Shift+,
            case ">": return (.period, true)       // Shift+.
            case "?": return (.forwardSlash, true) // Shift+/
            case "~": return (.grave, true)        // Shift+`
            default: return nil
            }
        }

        public func click(masks: CGEventFlags = [], toPid pid: pid_t? = nil) {
            down(masks: masks, toPid: pid)
            up(masks: masks, toPid: pid)
        }

        public func down(masks: CGEventFlags = [], toPid pid: pid_t? = nil) {
            let keyCode = CGKeyCode(self.rawValue)
            let source = CGEventSource(stateID: .hidSystemState)
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) else {
                print("CGEvent init failed")
                return
            }

            down.flags = masks

            if let pid = pid, pid >= 0 {
                down.postToPid(pid)
            } else {
                down.post(tap: .cghidEventTap)
            }
        }
        public func up(masks: CGEventFlags = [], toPid pid: pid_t? = nil) {
            let keyCode = CGKeyCode(self.rawValue)
            let source = CGEventSource(stateID: .hidSystemState)
            guard let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
                print("CGEvent init failed")
                return
            }

            up.flags = masks

            if let pid = pid, pid >= 0 {
                up.postToPid(pid)
            } else {
                up.post(tap: .cghidEventTap)
            }
        }
    }
}

