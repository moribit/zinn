// Desktop platform only; physics/training/inference are Pure Zig.
#import <AppKit/AppKit.h>
void rl_window_minimum(void) {
    // Fixed logical surface; a larger window letterboxes without clipping controls.
    NSWindow *window = NSApp.keyWindow ?: NSApp.mainWindow;
    if (!window) window = NSApp.windows.firstObject;
    if (window) {
        window.contentMinSize = NSMakeSize(960, 600);
        NSSize size = window.contentView.frame.size;
        if (size.width < 960 || size.height < 600)
            [window setContentSize:NSMakeSize(960, 600)];
    }
}
