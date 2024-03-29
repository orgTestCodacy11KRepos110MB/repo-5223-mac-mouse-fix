//
// --------------------------------------------------------------------------
// RemapUtility.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2020
// Licensed under MIT
// --------------------------------------------------------------------------
//

#import "Utility_Transformation.h"
#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>
#import "CGSPrivate.h"
#import "SharedUtility.h"
#include <sys/types.h>
#include <sys/sysctl.h>

@implementation Utility_Transformation

+ (NSTimeInterval)nsTimeStamp {
    /// Time since system startup in seconds. This value is used in NSEvent timestamps

    
    int MIB_SIZE = 2;
    
    int mib[MIB_SIZE];
    size_t size;
    struct timeval boottime;
    
    mib[0] = CTL_KERN;
    mib[1] = KERN_BOOTTIME;
    size = sizeof(boottime);
    if (sysctl(mib, MIB_SIZE, &boottime, &size, NULL, 0) != -1) {
        return boottime.tv_sec + (((double)boottime.tv_usec) / USEC_PER_SEC);
    }
    
    return 0.0;
}

+ (CFMachPortRef)createEventTapWithLocation:(CGEventTapLocation)location
                                       mask:(CGEventMask)mask
                                     option:(CGEventTapOptions)option
                                  placement:(CGEventTapPlacement)placement
                                   callback:(CGEventTapCallBack)callback {
    CFMachPortRef eventTap = CGEventTapCreate(location, placement, option, mask, callback, NULL);
    // ^ Make sure to use the same EventTapLocation and EventTapPlacement here as you do in ButtonInputReceiver, otherwise there'll be timing and ordering issues! (This was one of the causes for the stuck bug and also caused other issues)
    CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0);
    CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
    CFRelease(runLoopSource);
    CGEventTapEnable(eventTap, false);
    return eventTap;
}

+ (void)hideMousePointer:(BOOL)B {
    
    if (B) {
        void CGSSetConnectionProperty(int, int, CFStringRef, CFBooleanRef);
        int _CGSDefaultConnection(void);
        CFStringRef propertyString;

        // Hack to make background cursor setting work
        propertyString = CFStringCreateWithCString(NULL, "SetsCursorInBackground", kCFStringEncodingUTF8);
        CGSSetConnectionProperty(_CGSDefaultConnection(), _CGSDefaultConnection(), propertyString, kCFBooleanTrue);
        CFRelease(propertyString);
        // Hide the cursor and wait
        CGDisplayHideCursor(kCGDirectMainDisplay);
//        pause();
    } else {
        CGDisplayShowCursor(kCGDirectMainDisplay);
    }
}

#pragma mark - Button clicks

+ (void)postMouseButtonClicks:(MFMouseButtonNumber)button nOfClicks:(int64_t)nOfClicks {
    
    CGEventTapLocation tapLoc = kCGSessionEventTap;
    
    CGPoint mouseLoc = Utility_Transformation.CGMouseLocationWithoutEvent;
    CGEventType eventTypeDown = [SharedUtility CGEventTypeForButtonNumber:button isMouseDown:YES];
    CGEventType eventTypeUp = [SharedUtility CGEventTypeForButtonNumber:button isMouseDown:NO];
    CGMouseButton buttonCG = [SharedUtility CGMouseButtonFromMFMouseButtonNumber:button];
    
    CGEventRef buttonDown = CGEventCreateMouseEvent(NULL, eventTypeDown, mouseLoc, buttonCG);
    CGEventRef buttonUp = CGEventCreateMouseEvent(NULL, eventTypeUp, mouseLoc, buttonCG);
    
    int clickLevel = 1;
    while (clickLevel <= nOfClicks) {
        
        CGEventSetIntegerValueField(buttonDown, kCGMouseEventClickState, clickLevel);
        CGEventSetIntegerValueField(buttonUp, kCGMouseEventClickState, clickLevel);
        
        CGEventPost(tapLoc, buttonDown);
        CGEventPost(tapLoc, buttonUp);
        
        clickLevel++;
    }
    
    CFRelease(buttonDown);
    CFRelease(buttonUp);
}
+ (void)postMouseButton:(MFMouseButtonNumber)button down:(BOOL)down {
    
    /// I tried dispatching this event at a point other than the current cursor position, without moving the cursor.
    /// That would maybe help with this issue:  https://github.com/noah-nuebling/mac-mouse-fix/issues/157#issuecomment-932108105)
    /// I couldn't do it, though/ Here's what I tried:
    ///     Sending another mouse click at the original location - Only works like 1/4
    ///     Sending another mouse up event at the original location - Works exactly 1/3
    ///  I know this won't work:
    ///     CGWarpMousePointer - I'm using this in version-3 branch and has a delay after it where you can't move the poiner at all. If you turn off the delay it doesn't work anymore.
    ///  If feel like this might be impossible because macOS might need this small delay to move the pointer programmatically.
    
#if DEBUG
    NSLog(@"POSTING FAKE MOUSE BUTTON EVENT. btn: %d, down: %d", button, down);
#endif
    
    CGEventTapLocation tapLoc = kCGSessionEventTap;
    
    CGPoint mouseLoc = Utility_Transformation.CGMouseLocationWithoutEvent;
    CGEventType eventTypeDown = [SharedUtility CGEventTypeForButtonNumber:button isMouseDown:down];
    CGMouseButton buttonCG = [SharedUtility CGMouseButtonFromMFMouseButtonNumber:button];
    
    CGEventRef event = CGEventCreateMouseEvent(NULL, eventTypeDown, mouseLoc, buttonCG);
    CGEventSetIntegerValueField(event, kCGMouseEventClickState, 1);
    
    CGEventPost(tapLoc, event);
    CFRelease(event);
}

// Methods for obtaining effective remaps

/// Returns a block
///     - Which takes 2 arguments: `remaps` and `activeModifiers`
///     - The block takes the default remaps (with an empty precondition) and overrides it with the remappings defined for a precondition of `activeModifiers`.
+ (MFEffectiveRemapsMethod)effectiveRemapsMethod_Override {
    
    return ^NSDictionary *(NSDictionary *remaps, NSDictionary *activeModifiers) {
        NSDictionary *effectiveRemaps = remaps[@{}];
        NSDictionary *remapsForActiveModifiers = remaps[activeModifiers];
        if ([activeModifiers isNotEqualTo:@{}]) {
            effectiveRemaps = [SharedUtility dictionaryWithOverridesAppliedFrom:[remapsForActiveModifiers copy] to:effectiveRemaps]; // Why do we do ` - copy` here?
        }
        return effectiveRemaps;
    };
}

+ (CGPoint)CGMouseLocationWithoutEvent {
    CGEventRef locEvent = CGEventCreate(NULL);
    CGPoint mouseLoc = CGEventGetLocation(locEvent);
    CFRelease(locEvent);
    return mouseLoc;
}
+ (CGEventFlags)CGModifierFlagsWithoutEvent {
    CGEventRef flagEvent = CGEventCreate(NULL);
    CGEventFlags flags = CGEventGetFlags(flagEvent);
    CFRelease(flagEvent);
    return flags;
}

@end
