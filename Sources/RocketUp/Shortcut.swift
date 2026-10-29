import AppKit
import Carbon

struct Shortcut: Codable, Equatable {
    static let preferenceKey = "captureShortcut"
    static let supportedModifiers: NSEvent.ModifierFlags = [.control,.option,.shift,.command]
    static let `default` = Shortcut(keyCode:UInt16(kVK_ANSI_Backslash),modifiers:[.command])!
    let keyCode: UInt16
    private let modifierBits: UInt
    var modifiers: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue:modifierBits) }

    init?(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        let flags = modifiers.intersection(Self.supportedModifiers)
        guard !flags.intersection([.command,.control,.option]).isEmpty,
              keyCode != kVK_Escape, Self.keyEquivalent(for:keyCode) != nil else { return nil }
        self.keyCode = keyCode; self.modifierBits = flags.rawValue
    }

    static func load(from preferences: UserDefaults) -> Shortcut {
        guard let data = preferences.data(forKey:preferenceKey),
              let saved = try? JSONDecoder().decode(Self.self,from:data),
              let shortcut = Self(keyCode:saved.keyCode,modifiers:saved.modifiers) else { return .default }
        return shortcut
    }
    func save(to preferences: UserDefaults) {
        if let data = try? JSONEncoder().encode(self) { preferences.set(data,forKey:Self.preferenceKey) }
    }
    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        for (flag,value) in [(NSEvent.ModifierFlags.command,cmdKey),(.shift,shiftKey),(.option,optionKey),(.control,controlKey)] {
            if modifiers.contains(flag) { result |= UInt32(value) }
        }
        return result
    }
    var keyEquivalent: String { Self.keyEquivalent(for:keyCode) ?? "" }
    var displayString: String {
        var result = ""
        for (flag,symbol) in [(NSEvent.ModifierFlags.control,"⌃"),(.option,"⌥"),(.shift,"⇧"),(.command,"⌘")] {
            if modifiers.contains(flag) { result += symbol }
        }
        let labels = [kVK_Return:"↩",kVK_Tab:"⇥",kVK_Space:"Space",kVK_Delete:"⌫",kVK_ForwardDelete:"⌦",
                      kVK_ANSI_KeypadEnter:"⌤",kVK_LeftArrow:"←",kVK_RightArrow:"→",kVK_UpArrow:"↑",kVK_DownArrow:"↓",
                      kVK_Home:"↖",kVK_End:"↘",kVK_PageUp:"⇞",kVK_PageDown:"⇟"]
        if let label = labels[Int(keyCode)] { return result+label }
        if let index = Self.functionKeys.firstIndex(of:Int(keyCode)) { return result+"F\(index+1)" }
        return result+keyEquivalent.uppercased()
    }

    private static let functionKeys = [kVK_F1,kVK_F2,kVK_F3,kVK_F4,kVK_F5,kVK_F6,kVK_F7,kVK_F8,kVK_F9,kVK_F10,
                                       kVK_F11,kVK_F12,kVK_F13,kVK_F14,kVK_F15,kVK_F16,kVK_F17,kVK_F18,kVK_F19,kVK_F20]
    private static func keyEquivalent(for keyCode: UInt16) -> String? {
        let special = [kVK_Return:0x0D,kVK_Tab:0x09,kVK_Space:0x20,kVK_Delete:0x08,kVK_ForwardDelete:NSDeleteFunctionKey,
                       kVK_ANSI_KeypadEnter:0x03,kVK_LeftArrow:NSLeftArrowFunctionKey,kVK_RightArrow:NSRightArrowFunctionKey,
                       kVK_UpArrow:NSUpArrowFunctionKey,kVK_DownArrow:NSDownArrowFunctionKey,kVK_Home:NSHomeFunctionKey,
                       kVK_End:NSEndFunctionKey,kVK_PageUp:NSPageUpFunctionKey,kVK_PageDown:NSPageDownFunctionKey]
        if let value = special[Int(keyCode)] { return UnicodeScalar(value).map(String.init) }
        if let index = functionKeys.firstIndex(of:Int(keyCode)) { return String(UnicodeScalar(NSF1FunctionKey+index)!) }
        // Modifier keys and unknown virtual keys cannot be recorded as a shortcut.
        guard keyCode < 128, ![kVK_Command,kVK_RightCommand,kVK_Shift,kVK_RightShift,kVK_Option,kVK_RightOption,
                              kVK_Control,kVK_RightControl,kVK_CapsLock,kVK_Function,kVK_Escape].contains(Int(keyCode)) else { return nil }
        let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        guard let pointer = TISGetInputSourceProperty(source,kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to:UCKeyboardLayout.self)
        var deadKeyState: UInt32 = 0, length = 0
        var characters = [UniChar](repeating:0,count:4)
        let status = UCKeyTranslate(layout,keyCode,UInt16(kUCKeyActionDisplay),0,UInt32(LMGetKbdType()),
                                    OptionBits(kUCKeyTranslateNoDeadKeysMask),&deadKeyState,characters.count,&length,&characters)
        guard status == noErr, length > 0 else { return nil }
        let value = String(utf16CodeUnits:characters,count:length).lowercased()
        guard value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }
}
