// Desktop platform only; physics/training/inference are Pure Zig.
#import <AppKit/AppKit.h>
void rl_window_minimum(void) {
    // Fixed logical surface; a larger window letterboxes without clipping controls.
    NSWindow *window = NSApp.keyWindow;
    if (window) window.contentMinSize = NSMakeSize(1280, 720);
}
