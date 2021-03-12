//
// --------------------------------------------------------------------------
// Hyperlink.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2019
// Licensed under MIT
// --------------------------------------------------------------------------
//

#import "Hyperlink.h"
#import "Utility_App.h"
#import "AppDelegate.h"

IB_DESIGNABLE
@interface Hyperlink ()

@property (nonatomic) IBInspectable NSString *href;

@property IBInspectable NSNumber *tMrgn; // Top tracking margin
@property IBInspectable NSNumber *rMrgn; // Right tracking margin
@property IBInspectable NSNumber *bMrgn; // Bottom tracking margin
@property IBInspectable NSNumber *lMrgn; // Left tracking margin

@end

@implementation Hyperlink

NSRect _trackingRect;

BOOL _mouseInside = NO;
BOOL _mouseDownOverThis = NO;

- (void)awakeFromNib {
        
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        [self mouseDown:event];
        return event;
    }];
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseUp handler:^NSEvent * _Nullable(NSEvent * _Nonnull event) {
        [self mouseUp:event];
        return event;
    }];
    
    // Set IBInspectible default values
    
    NSNumber *zeroNS = [NSNumber numberWithInt:0.0];
    if (_tMrgn == nil) {
        _tMrgn = zeroNS;
    }
    if (_rMrgn == nil) {
        _rMrgn = zeroNS;
    }
    if (_bMrgn == nil) {
        _bMrgn = zeroNS;
    }
    if (_lMrgn == nil) {
        _lMrgn = zeroNS;
    }
    
    // Setup tracking area
    
    // Options
    NSTrackingAreaOptions trackingAreaOptions =  NSTrackingMouseEnteredAndExited | NSTrackingActiveAlways | NSTrackingEnabledDuringMouseDrag;
    _trackingRect = self.bounds;
    
    // Make area larger according to IBInspectable tracking margins
    // Top
    _trackingRect.origin.y -= _tMrgn.doubleValue;
    _trackingRect.size.height += _tMrgn.doubleValue;
    // Bottom
    _trackingRect.size.height += _bMrgn.doubleValue;
    // Left
    _trackingRect.origin.x -= _lMrgn.doubleValue;
    _trackingRect.size.width += _lMrgn.doubleValue;
    // Right
    _trackingRect.size.width += _rMrgn.doubleValue;
    
    // Add tracking area
    NSTrackingArea * area = [[NSTrackingArea alloc] initWithRect:_trackingRect
                                                         options:trackingAreaOptions
                                                           owner:self
                                                        userInfo:nil];
    [self addTrackingArea:area];
    
}
//- (void)resetCursorRects {
//    [self discardCursorRects];
//    [self addCursorRect:_trackingRect cursor:NSCursor.pointingHandCursor];
//}
- (void)mouseEntered:(NSEvent *)event {
    
    _mouseInside = YES;
    
    NSMutableAttributedString *underlinedString = [[NSMutableAttributedString alloc] initWithAttributedString: self.attributedStringValue];
    
    NSRange wholeStringRange = NSMakeRange(0, [underlinedString length]);
    
    [underlinedString addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleSingle) range:wholeStringRange];
    
//    [underlinedString setAlignment:NSTextAlignmentRight range:wholeStringRange];
    
    self.attributedStringValue = underlinedString;
}
- (void)mouseExited:(NSEvent *)event {
    
    _mouseInside = NO;
    
    NSMutableAttributedString *notUnderlinedString = [[NSMutableAttributedString alloc] initWithAttributedString: self.attributedStringValue];
    
    NSRange wholeStringRange = NSMakeRange(0, [notUnderlinedString length]);
    
    [notUnderlinedString addAttribute:NSUnderlineStyleAttributeName value:@(NSUnderlineStyleNone) range:wholeStringRange];
    
//    [notUnderlinedString setAlignment:NSTextAlignmentRight range:wholeStringRange];
    
    self.attributedStringValue = notUnderlinedString;
}
- (void)mouseDown:(NSEvent *)event {
    if (_mouseInside) {
        _mouseDownOverThis = YES;
    }
}
- (void)mouseUp:(NSEvent *)event {
    if (_mouseDownOverThis && _mouseInside) {
        [self reactToClick];
    }
    _mouseDownOverThis = NO;
}
- (void) reactToClick {
    // Open URL defined in Interface Builder
    NSLog(@"Opening: %@",_href);
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:_href]];
    // Send IBAction
    [self sendAction:self.action to:self.target];
}

@end
