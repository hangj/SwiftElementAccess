// https://stackoverflow.com/questions/1742890/cgwindowid-from-axuielement
// https://github.com/rxhanson/Rectangle/blob/main/Rectangle/Rectangle-Bridging-Header.h

#import <AppKit/AppKit.h>

// extern "C" AXError _AXUIElementGetWindow(AXUIElementRef, CGWindowID* out);
AXError _AXUIElementGetWindow(AXUIElementRef element, uint32_t *identifier);