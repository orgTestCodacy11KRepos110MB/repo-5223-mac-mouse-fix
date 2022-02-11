//
// --------------------------------------------------------------------------
// ScrollControl.m
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2020
// Licensed under MIT
// --------------------------------------------------------------------------
//

#import "Scroll.h"
#import "DeviceManager.h"
#import "TouchSimulator.h"
#import "ScrollModifiers.h"
#import "Config.h"
#import "ScrollUtility.h"
#import "VectorUtility.h"
#import "HelperUtility.h"
#import "WannabePrefixHeader.h"
#import "ScrollAnalyzer.h"
#import "ScrollConfigObjC.h"
#import <Cocoa/Cocoa.h>
#import "Queue.h"
#import "Mac_Mouse_Fix_Helper-Swift.h"
#import "SubPixelator.h"
#import "GestureScrollSimulator.h"
#import "SharedUtility.h"
#import "ScrollModifiers.h"
#import "Actions.h"

@implementation Scroll

#pragma mark - Variables - static

static CFMachPortRef _eventTap;
static CGEventSourceRef _eventSource;

static dispatch_queue_t _scrollQueue;

static PixelatedVectorAnimator *_animator;

static AXUIElementRef _systemWideAXUIElement; // TODO: should probably move this to Config or some sort of OverrideManager class
+ (AXUIElementRef) systemWideAXUIElement {
    return _systemWideAXUIElement;
}

#pragma mark - Variables - dynamic

static MFScrollModificationResult _modifications;
static ScrollConfig *_scrollConfig;

#pragma mark - Public functions

+ (void)load_Manual {
    
    /// Setup dispatch queue
    ///  For multithreading while still retaining control over execution order.
    dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INTERACTIVE, -1);
    _scrollQueue = dispatch_queue_create("com.nuebling.mac-mouse-fix.helper.scroll", attr);
    
    /// Create AXUIElement for getting app under mouse pointer
    _systemWideAXUIElement = AXUIElementCreateSystemWide();
    /// Create Event source
    if (_eventSource == nil) {
        _eventSource = CGEventSourceCreate(kCGEventSourceStateHIDSystemState);
    }
    
    /// Create/enable scrollwheel input callback
    if (_eventTap == nil) {
        CGEventMask mask = CGEventMaskBit(kCGEventScrollWheel);
        _eventTap = CGEventTapCreate(kCGHIDEventTap, kCGHeadInsertEventTap, kCGEventTapOptionDefault, mask, eventTapCallback, NULL);
        DDLogDebug(@"_eventTap: %@", _eventTap);
        CFRunLoopSourceRef runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, _eventTap, 0);
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, kCFRunLoopCommonModes);
        CFRelease(runLoopSource);
        CGEventTapEnable(_eventTap, false); // Not sure if this does anything
    }
    
    /// Create animator
    _animator = [[PixelatedVectorAnimator alloc] init];
    
    /// Init config instance
    _scrollConfig = [[ScrollConfig alloc] init];
}

+ (void)resetState {
    /// This is untested
    
    [_animator stop];
    [GestureScrollSimulator stopMomentumScroll];
    [ScrollAnalyzer resetState];
}

+ (void)decide {
    /// TODO: Think about / update this
    /// Either activate SmoothScroll or RoughScroll or stop scroll interception entirely
    /// Call this whenever a value which the decision depends on changes
    
    BOOL disableAll =
    ![DeviceManager devicesAreAttached];
    //|| (!_isSmoothEnabled && _scrollDirection == 1);
//    || isEnabled == NO;
    
    if (disableAll) {
        DDLogInfo(@"Disabling scroll interception");
        // Disable scroll interception
        if (_eventTap) {
            CGEventTapEnable(_eventTap, false);
        }
        // Disable other scroll classes
//        [ScrollModifiers stop];
//        [SmoothScroll stop];
//        [RoughScroll stop];
    } else {
        // Enable scroll interception
        CGEventTapEnable(_eventTap, true);
        // Enable other scroll classes
//        [ScrollModifiers start];
//        if (ScrollConfig.smoothEnabled) {
//            DDLogInfo(@"Enabling SmoothScroll");
//            [SmoothScroll start];
//            [RoughScroll stop];
//        } else {
//            DDLogInfo(@"Enabling RoughScroll");
//            [SmoothScroll stop];
//            [RoughScroll start];
//        }
    }
}

#pragma mark - Private functions

static CGEventRef eventTapCallback(CGEventTapProxy proxy, CGEventType type, CGEventRef event, void *userInfo) {
    
    /// Handle eventTapDisabled messages
    
    if (type == kCGEventTapDisabledByTimeout || type == kCGEventTapDisabledByUserInput) {
        
        if (type == kCGEventTapDisabledByUserInput) {
            DDLogInfo(@"ScrollControl eventTap was disabled by timeout. Re-enabling");
            CGEventTapEnable(_eventTap, true);
        } else if (type == kCGEventTapDisabledByUserInput) {
            DDLogInfo(@"ScrollControl eventTap was disabled by user input.");
        }
        
        return event;
    }
    
    /// Return non-scrollwheel events unaltered
    
    int64_t isPixelBased     = CGEventGetIntegerValueField(event, kCGScrollWheelEventIsContinuous);
    int64_t scrollPhase      = CGEventGetIntegerValueField(event, kCGScrollWheelEventScrollPhase);
    int64_t scrollDeltaAxis1 = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1);
    int64_t scrollDeltaAxis2 = CGEventGetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2);
    bool isDiagonal = scrollDeltaAxis1 != 0 && scrollDeltaAxis2 != 0;
    if (isPixelBased != 0
        || scrollPhase != 0 /// Adding scrollphase here is untested
        || isDiagonal) {
        
        return event;
    }
    
    /// Get timestamp
    ///     Get timestamp here instead of _scrollQueue for accurate timing
    
    CFTimeInterval tickTime = CACurrentMediaTime();
        
    /// Create copy of event
    CGEventRef eventCopy = CGEventCreateCopy(event); /// Create a copy, because the original event will become invalid and unusable in the new queue.
    
    ///  Executing heavy stuff on a different thread to prevent the eventTap from timing out. We wrote this before knowing that you can just re-enable the eventTap when it times out. But this doesn't hurt.
    
    /// Enqueue heavy processing
    dispatch_async(_scrollQueue, ^{
        heavyProcessing(eventCopy, scrollDeltaAxis1, scrollDeltaAxis2, tickTime);
    });
    
    return nil;
}

static void heavyProcessing(CGEventRef event, int64_t scrollDeltaAxis1, int64_t scrollDeltaAxis2, CFTimeInterval tickTime) {
    
    /// Get axis
    
    MFAxis inputAxis = [ScrollUtility axisForVerticalDelta:scrollDeltaAxis1 horizontalDelta:scrollDeltaAxis2];
    
    /// Get scrollDelta
    
    int64_t scrollDelta = 0;
    
    if (inputAxis == kMFAxisVertical) {
        scrollDelta = scrollDeltaAxis1;
    } else if (inputAxis == kMFAxisHorizontal) {
        scrollDelta = scrollDeltaAxis2;
    } else {
        NSCAssert(NO, @"Invalid scroll axis");
    }
    
    /// Run preliminary scrollAnalysis
    ///     To check if this is the first consecutive scrollTick
    
    MFDirection scrollDirection = [ScrollUtility directionForInputAxis:inputAxis inputDelta:scrollDelta invertSetting:[_scrollConfig scrollInvertWithEvent:event] horizontalModifier:(_modifications.effectModification == kMFScrollEffectModificationHorizontalScroll)];
    
    BOOL firstConsecutive = [ScrollAnalyzer peekIsFirstConsecutiveTickWithTickOccuringAt:tickTime withDirection:scrollDirection withConfig:_scrollConfig];
    
    /// Update stuff
    ///     on the first scrollTick
    
    if (firstConsecutive) {
        /// Checking which app is under the mouse pointer and the other stuff we do here is really slow, so we only do it when necessary
        
        DDLogDebug(@"First consec");
        
        /// Update application Overrides
        
        [ScrollUtility updateMouseDidMoveWithEvent:event];
        if (!ScrollUtility.mouseDidMove) {
            [ScrollUtility updateFrontMostAppDidChange];
            /// Only checking this if mouse didn't move, because of || in (mouseMoved || frontMostAppChanged). For optimization. Not sure if significant.
        }
        
        if (ScrollUtility.mouseDidMove || ScrollUtility.frontMostAppDidChange) {
            /// Set app overrides
            BOOL configChanged = [Config applyOverridesForAppUnderMousePointer_Force:NO];
            if (configChanged) {
                [Scroll resetState];
                /// TODO: Test if this works
                /// TODO: `applyOverridesForAppUnderMousePointer_Force:` should (probably) reset stuff itself, if it changes anything. This whole [SmoothScroll stop] stuff is kinda messy
                
            }
        }
        
        /// Init animator
        
        [_animator resetSubPixelator];
        if (ScrollUtility.mouseDidMove) {
            /// Update animator to currently used display
            [_animator linkToMainScreen];
        }
        
        /// Update modfications
        
        _modifications = [ScrollModifiers currentScrollModificationsWithEvent:event];
        
        /// Update scrollConfig
        
        _scrollConfig = [ScrollConfig currentConfig];
        
        /// Override scrollConfig based on modifications
        
        if (_modifications.inputModification == kMFScrollInputModificationQuick) {
            
            /// Make fast scroll easy to trigger
            _scrollConfig.consecutiveScrollSwipeMaxInterval *= 1.2;
            _scrollConfig.consecutiveScrollTickIntervalMax *= 1.2;
            
            /// Amp up fast scroll
            _scrollConfig.fastScrollThreshold_inSwipes = 2;
            _scrollConfig.fastScrollExponentialBase = M_E /*1.5*/;
            _scrollConfig.fastScrollScale = 0.7;
            
            /// Override acceleration curve
            _scrollConfig.accelerationCurve = _scrollConfig.quickAccelerationCurve;
            
        } else if (_modifications.inputModification == kMFScrollInputModificationPrecise) {
            
            /// Turn off fast scroll
            _scrollConfig.fastScrollThreshold_inSwipes = 69; /// Haha sex number
            _scrollConfig.fastScrollExponentialBase = 1.0;
            _scrollConfig.fastScrollScale = 1.0;
            
            /// Override acceleration curve
            _scrollConfig.accelerationCurve = _scrollConfig.preciseAccelerationCurve;
        } else {
            
            /// Set default acceleration curve
            _scrollConfig.accelerationCurve = _scrollConfig.standardAccelerationCurve;
        }
        
        if (_modifications.effectModification == kMFScrollEffectModificationCommandTab) {
            _scrollConfig.smoothEnabled = NO;
        }
        if (_modifications.effectModification == kMFScrollEffectModificationFourFingerPinch
            || _modifications.effectModification == kMFScrollEffectModificationThreeFingerSwipeHorizontal
            || _modifications.effectModification == kMFScrollEffectModificationZoom
            || _modifications.effectModification == kMFScrollEffectModificationRotate
            || _modifications.inputModification == kMFScrollInputModificationQuick) {
            
            _scrollConfig.smoothEnabled = YES;
            /// ^ These modification effects simulate gestures. They need eventPhases to work properly. So they only work when when driven by the animator.
        }
        
    }
    
    /// Get effective direction
    ///  -> With user settings etc. applied
    
    scrollDirection = [ScrollUtility directionForInputAxis:inputAxis inputDelta:scrollDelta invertSetting:[_scrollConfig scrollInvertWithEvent:event] horizontalModifier:(_modifications.effectModification == kMFScrollEffectModificationHorizontalScroll)];
    
    /// Run full scrollAnalysis
    ScrollAnalysisResult scrollAnalysisResult = [ScrollAnalyzer updateWithTickOccuringAt:tickTime withDirection:scrollDirection withConfig:_scrollConfig];
    
    /// Make scrollDelta positive, now that we have scrollDirection stored
    scrollDelta = llabs(scrollDelta);
    
    /// Get distance to scroll
    
    int64_t pxToScrollForThisTick = getPxPerTick(scrollAnalysisResult.timeBetweenTicks, scrollDelta);
    
    /// Apply fast scroll to distance
        
    /// Get fast scroll params
    int64_t fsThreshold = _scrollConfig.fastScrollThreshold_inSwipes;
    double fsFactor = _scrollConfig.fastScrollFactor;
    double fsBase = _scrollConfig.fastScrollExponentialBase;
    double fsScale = _scrollConfig.fastScrollScale;
    
    /// Evaluate fast scroll
    int64_t fastScrollThresholdDelta = scrollAnalysisResult.consecutiveScrollSwipeCounter_ForFreeScrollWheel - fsThreshold;
    fastScrollThresholdDelta += 2; /// Add 2 cause it makes sense
    if (fastScrollThresholdDelta > 0) {
        pxToScrollForThisTick *= fsFactor * pow(fsBase, fastScrollThresholdDelta*fsScale);
    }
    
    /// Debug
    
    DDLogDebug(@"\nconsecTicks: %lld, consecSwipes: %lld, consecSwipesFree: %lld", scrollAnalysisResult.consecutiveScrollTickCounter, scrollAnalysisResult.consecutiveScrollSwipeCounter, scrollAnalysisResult.consecutiveScrollSwipeCounter_ForFreeScrollWheel);
    
    DDLogDebug(@"timeBetweenTicks: %f, timeBetweenTicksRaw: %f, diff: %f, ticks: %lld", scrollAnalysisResult.timeBetweenTicks, scrollAnalysisResult.timeBetweenTicksRaw, scrollAnalysisResult.timeBetweenTicks - scrollAnalysisResult.timeBetweenTicksRaw, scrollAnalysisResult.consecutiveScrollTickCounter);
    
    /// Send scroll events
    
    if (pxToScrollForThisTick == 0) {
        
        DDLogWarn(@"pxToScrollForThisTick is 0");
        
    } else if (!_scrollConfig.smoothEnabled) {
        
        /// Send scroll event directly - without the animator. Will scroll all of pxToScrollForThisTick at once.
        
        sendScroll(pxToScrollForThisTick, scrollDirection, NO, kMFAnimationPhaseNone);
        
    } else {
        /// Send scroll events through animator, spread out over time.
        
        /// Start animation
        
        [_animator startWithParams:^NSDictionary<NSString *,id> * _Nonnull(Vector valueLeftVec, BOOL isRunning, NSObject<AnimationCurve> *animationCurve) {
            
            /// Validate
            assert(valueLeftVec.x == 0 || valueLeftVec.y == 0);
            
            /// Extract 1d valueLeft
            double valueLeft = magnitudeOfVector(valueLeftVec);
            
            /// Declare result dict (animator start params)
            
            NSMutableDictionary *p = [NSMutableDictionary dictionary];
            
            /// Get base scroll duration
            CFTimeInterval baseTimeRange = ((CFTimeInterval)_scrollConfig.msPerStep) / 1000.0; /// Need to cast to CFTimeInterval (double), to make this a float division
            
            /// Get px that the animator still wants to scroll
            double pxLeftToScroll;
            if (scrollAnalysisResult.scrollDirectionDidChange || !isRunning) {
                pxLeftToScroll = 0;
            } else if ([animationCurve isKindOfClass:SimpleBezierDragHybridCurve.class]) {
                SimpleBezierDragHybridCurve *c = (SimpleBezierDragHybridCurve *)animationCurve;
                pxLeftToScroll = [c baseValueLeftWithValueLeft:valueLeft]; /// If we feed valueLeft instead of baseValueLeft back into the animator, it will lead to unwanted acceleration
            } else {
                pxLeftToScroll = valueLeft;
            }
            
            if (_modifications.effectModification == kMFScrollEffectModificationFourFingerPinch
                || _modifications.effectModification == kMFScrollEffectModificationThreeFingerSwipeHorizontal
                || _modifications.inputModification == kMFScrollInputModificationQuick) {

                /// Use linear curve for 4 finger pinch and 3 finger swipe
                ///     because it feels much smoother
                /// Using linear for horizontal scroll
                ///     feels smoother for navigating between pages
                ///         We could not suppress natural momentum scrolling on horizontal scroll events to balance out the linear curve? But then we should probably also decrease the animationDuration... Edit: I tried it and it sucks for normal scrolling.
                
                double delta = pxToScrollForThisTick + pxLeftToScroll;
                Vector deltaVec = vectorFromDirection(delta, scrollDirection);
                
                p[@"duration"] = @(baseTimeRange);
                p[@"vector"] = valueFromVector(deltaVec);
                p[@"curve"] = ScrollConfig.linearCurve;
                
            } else {
                
                /// New curve
                SimpleBezierDragHybridCurve *c = [[SimpleBezierDragHybridCurve alloc]
                                                  initWithBaseCurve:_scrollConfig.baseCurve
                                                  baseTimeRange:baseTimeRange
                                                 baseValueRange:(pxToScrollForThisTick + pxLeftToScroll)
                                                dragCoefficient:_scrollConfig.dragCoefficient
                                                   dragExponent:_scrollConfig.dragExponent
                                                      stopSpeed:_scrollConfig.stopSpeed];
                
                /// Get values for animator from hybrid curve
                
                double delta = c.valueRange;
                Vector deltaVec = vectorFromDirection(delta, scrollDirection);
                
                p[@"duration"] = @(c.timeRange);
                p[@"vector"] = valueFromVector(deltaVec);
                p[@"curve"] = c;
            }
            
            /// Debug
            
//            static double scrollDeltaSum = 0;
//            scrollDeltaSum += labs(pxToScrollForThisTick);
//            DDLogDebug(@"Delta sum pre-animator: %f", scrollDeltaSum);
            
            /// Return
            return p;
            
        } integerCallback:^(Vector valueDeltaVec, MFAnimationCallbackPhase animationPhase) {
            
            /// Validate
            assert(valueDeltaVec.x == 0 || valueDeltaVec.y == 0);
            /// Extract
            double valueDelta = magnitudeOfVector(valueDeltaVec);
            
         /// This will be called each frame
            
            /// Debug
//            static double scrollDeltaSummm = 0;
//            scrollDeltaSummm += valueDelta;
//            DDLogDebug(@"Delta sum in-animator: %f", scrollDeltaSummm);
            
            /// Debug
            
//            static CFTimeInterval lastTs = 0;
//            CFTimeInterval ts = CACurrentMediaTime();
//            DDLogInfo(@"scrollSendInterval: %@, dT: %@, dPx: %@", @(ts - lastTs), @(timeDelta), @(valueDelta));
//            lastTs = ts;
//            DDLogDebug(@"DELTA: %ld, PHASE: %d", (long)valueDelta, animationPhase);
            
            /// Test if PixelatedAnimator works properly
            if (valueDelta == 0) {
                assert(animationPhase == kMFAnimationCallbackPhaseEnd);
            }
            
            /// Send scroll
            sendScroll(valueDelta, scrollDirection, YES, animationPhase);
            
        }];
    }
    
    CFRelease(event);
}

static int64_t getPxPerTick(CFTimeInterval timeBetweenTicks, int64_t cgEventScrollDeltaPoint) {
    /// @discussion See the RawAccel guide for more info on acceleration curves https://github.com/a1xd/rawaccel/blob/master/doc/Guide.md
    ///     -> Edit: I read up on it and I don't see why the sensitivity-based approach that RawAccel uses is useful.
    ///     They define the base curve as for sensitivity, but then go through complex maths and many hurdles to make the implied outputVelocity(inputVelocity) function and its derivative smooth. Because that is what makes the acceleration feel predictable and nice. (See their "Gain" algorithm)
    ///     Then why not just define the the outputVelocity(inputVelocity) curve to be a smooth curve to begin with? Why does sensitivity matter? It doesn't make sens to me.
    ///     I'm just gonna use a BezierCurve to define the outputVelocity(inputVelocity) curve. Then I'll extrapolate the curve linearly at the end, so its defined everywhere. That is guaranteed to be smooth and easy to configure.
    ///     Edit: Actuallyyy we ended up outputting pixels to scroll for a given tick here (so sensitivity), not speed. I don't think perfectly smooth curves are that important. This is good enough and is more easy and natural to think about and configure.
    
    if (_scrollConfig.useAppleAcceleration) {
        return llabs(cgEventScrollDeltaPoint);
    }
    AccelerationBezier *curve = _scrollConfig.accelerationCurve();
    
    if (timeBetweenTicks == DBL_MAX) timeBetweenTicks = _scrollConfig.consecutiveScrollTickIntervalMax;
    double scrollSpeed = 1/timeBetweenTicks; /// In tick/s
                                             ///
    double pxForThisTick = [curve evaluateAt:scrollSpeed]; /// In px/s
    
//    DDLogDebug(@"Time between ticks: %f, scrollSpeed: %f, pxForThisTick: %f", timeBetweenTicks, scrollSpeed, pxForThisTick);
    
    if (pxForThisTick <= 0) {
        DDLogError(@"pxForThisTick is smaller equal 0. This is invalid. Exiting. scrollSpeed: %f, pxForThisTick: %f", scrollSpeed, pxForThisTick);
        assert(false);
    }
    
    return pxForThisTick; /// We could use a SubPixelator balance out the rounding errors, but I don't think that'll be noticable
}

static void sendScroll(int64_t px, MFDirection scrollDirection, BOOL gesture, MFAnimationCallbackPhase animationPhase) {
    
    
    if (px == 0) {
        DDLogDebug(@"Pixels to scroll are 0");
    }
    
    /// Get x and y deltas
    
    int64_t dx = 0;
    int64_t dy = 0;
    
    if (scrollDirection == kMFDirectionUp) {
        dy = px;
    } else if (scrollDirection == kMFDirectionDown) {
        dy = -px;
    } else if (scrollDirection == kMFDirectionLeft) {
        dx = -px;
    } else if (scrollDirection == kMFDirectionRight) {
        dx = px;
    } else if (scrollDirection == kMFDirectionNone) {
        
    } else {
        assert(false);
    }
    
    /// Get params for sending event
    
    MFScrollOutputType outputType;
    
    if (!gesture) {
        outputType = kMFScrollOutputTypeLineScroll;
    } else {
        outputType = kMFScrollOutputTypeGestureScroll;
    }
    
    if (_modifications.effectModification == kMFScrollEffectModificationZoom) {
        outputType = kMFScrollOutputTypeZoom;
    } else if (_modifications.effectModification == kMFScrollEffectModificationRotate) {
        outputType = kMFScrollOutputTypeRotation;
    } else if (_modifications.effectModification == kMFScrollEffectModificationFourFingerPinch) {
        outputType = kMFScrollOutputTypeFourFingerPinch;
    } else if (_modifications.effectModification == kMFScrollEffectModificationCommandTab) {
        outputType = kMFScrollOutputTypeCommandTab;
    } else if (_modifications.effectModification == kMFScrollEffectModificationThreeFingerSwipeHorizontal) {
        outputType = kMFScrollOutputTypeThreeFingerSwipeHorizontal;
    } /// kMFScrollEffectModificationHorizontalScroll is handled above when determining scroll direction
    
    /// Send event
    
    sendOutputEvents(dx, dy, outputType, animationPhase);
}

/// Define output types

typedef enum {
    kMFScrollOutputTypeGestureScroll,
    kMFScrollOutputTypeFourFingerPinch,
    kMFScrollOutputTypeThreeFingerSwipeHorizontal,
    kMFScrollOutputTypeZoom,
    kMFScrollOutputTypeRotation,
    kMFScrollOutputTypeCommandTab,
    kMFScrollOutputTypeLineScroll,
} MFScrollOutputType;

/// Output

static void sendOutputEvents(int64_t dx, int64_t dy, MFScrollOutputType outputType, MFAnimationCallbackPhase animatorPhase) {
    
    /// Init eventPhase
    
    IOHIDEventPhaseBits eventPhase = [VectorAnimator IOHIDPhaseWithAnimationCallbackPhase:animatorPhase];
    
    /// Validate
    
    if (dx+dy == 0) {
        assert(eventPhase == kIOHIDEventPhaseEnded);
    }
    
    /// Send events based on outputType
    
    if (outputType == kMFScrollOutputTypeGestureScroll) {
        
        /// --- GestureScroll ---
        
        [GestureScrollSimulator postGestureScrollEventWithDeltaX:dx deltaY:dy phase:eventPhase];
        
        /// QuickScroll is *not* active
        
        /// Suppress momentumScroll unless quickScroll is active
        if (eventPhase == kIOHIDEventPhaseEnded
            && _modifications.inputModification != kMFScrollInputModificationQuick) {
            
            [GestureScrollSimulator postGestureScrollEventWithDeltaX:0 deltaY:0 phase: kIOHIDEventPhaseEnded];
            [GestureScrollSimulator stopMomentumScroll];
        }
        
    } else if (outputType == kMFScrollOutputTypeZoom) {
        
        /// --- Zoom ---
        
        double eventDelta = (dx + dy)/800.0; /// This works because, if dx != 0 -> dy == 0, and the other way around.
        
        [TouchSimulator postMagnificationEventWithMagnification:eventDelta phase:eventPhase];
        
        
    } else if (outputType == kMFScrollOutputTypeRotation) {
        
        /// --- Rotation ---
        
        double eventDelta = (dx + dy)/8.0; /// This works because, if dx != 0 -> dy == 0, and the other way around.
        
        [TouchSimulator postRotationEventWithRotation:eventDelta phase:eventPhase];
        
    } else if (outputType == kMFScrollOutputTypeFourFingerPinch
               || outputType == kMFScrollOutputTypeThreeFingerSwipeHorizontal) {
        
        /// --- FourFingerPinch or ThreeFingerSwipeHorizontal ---
        ///         ^ Used to access Launchpad or show desktop
        ///                           ^ Used to switch Spaces
        
        MFDockSwipeType type;
        double eventDelta;
        
        if (outputType == kMFScrollOutputTypeFourFingerPinch) {
            type = kMFDockSwipeTypePinch;
            eventDelta = -(dx + dy)/600.0;
            /// ^ Launchpad feels a lot less sensitive than Show Desktop, but to improve this we'd have to somehow detect which of both is active atm. Negate delta to mirror the way that zooming works
        } else if (outputType == kMFScrollOutputTypeThreeFingerSwipeHorizontal) {
            type = kMFDockSwipeTypeHorizontal;
            eventDelta = -(dx + dy)/600.0;
        } else {
            assert(false);
        }
        
        [TouchSimulator postDockSwipeEventWithDelta:eventDelta type:type phase:eventPhase];
        
        if (eventPhase == kIOHIDEventPhaseEnded) {
            
            /// v Dock swipes will sometimes get stuck when the computer is slow. This can be solved by sending several "end" events in a row with a delay (see "stuck bug" in ModifiedDrag)
            ///     Edit: Even with sending the event again after 0.2 seconds, the stuck bug still happens a bunch here for some reason. Event though this almost completely eliminates the bug in ModifiedDrag.
            ///         Hopefully, sending it again after 0.5 seconds works... Edit: Yes, seems to work better but still sometimes happens
            ///   Edit2: I don't experience the stuck bug anymore here. I'm on an M1 now, maybe that's it.
            ///     TODO: I should probably move the "sending several end events" code to the postDockSwipeEventWithDelta: function, because otherwise there might be interference when the scroll engine and the drag engine try to send those 'end' events at the same time. We also need further safety measures if several sources try to use postDockSwipeEventWithDelta: at the same time.
            ///     TODO: We should probably change the "sending several end events" code in ModifiedDrag over to using timers that we can invalidate like here - We should do this to avoid too many 'end' events being sent from old timers.
            
            static NSTimer *timer1;
            static NSTimer *timer2;
            
            [timer1 invalidate];
            [timer2 invalidate];
            
            double zero = 0.0;
            
            IOHIDEventPhaseBits iohidPhase = kIOHIDEventPhaseEnded;
            
            SEL selector = @selector(postDockSwipeEventWithDelta:type:phase:);
            NSMethodSignature *signature = [TouchSimulator methodSignatureForSelector:selector];
            NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
            invocation.target = TouchSimulator.class;
            invocation.selector = selector;
            [invocation setArgument:&zero atIndex:2];
            [invocation setArgument:&type atIndex:3];
            [invocation setArgument:&iohidPhase atIndex:4];
            
            timer1 = [NSTimer scheduledTimerWithTimeInterval:0.2 invocation:invocation repeats:NO];
            timer2 = [NSTimer scheduledTimerWithTimeInterval:0.5 invocation:invocation repeats:NO];
            
        }
        
    } else if (outputType == kMFScrollOutputTypeCommandTab) {
        
        /// --- CommandTab ---
        
        double d = -(dx + dy);
        
        if (d == 0) return;
        
        /// Send events
        
        if (!_appSwitcherIsOpen) {
            
            _appSwitcherIsOpen = YES;
            /// Send command down event
            sendKeyEvent(55, kCGEventFlagMaskCommand, true);
        }
        
        /// Send tab down and up events
        
        if (d > 0) {
            sendKeyEvent(48, kCGEventFlagMaskCommand, true);
            sendKeyEvent(48, kCGEventFlagMaskCommand, false);
        } else {
            sendKeyEvent(48, kCGEventFlagMaskCommand | kCGEventFlagMaskShift, true);
            sendKeyEvent(48, kCGEventFlagMaskCommand | kCGEventFlagMaskShift, false);
        }

        
    } else if (outputType == kMFScrollOutputTypeLineScroll) {
        
        /// --- LineScroll ---
        
        /// We ignore the phases and isFinalEvent here, they don't matter
        
        /// TODO: line delta should always be around 1/10 of pixel delta. Also subpixelate line delta.
        ///     See CGEventSource pixelsPerLine - it's 10.
        
        if (dx+dy == 0) return;
        
        CGEventRef event = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitPixel, 1, 0);
        
        int64_t dyLine;
        int64_t dxLine;
        
        /// Make line deltas 1/10 of pixel deltas
        dyLine = round(dy / 10);
        dxLine = round(dx / 10);
        
        /// Make line deltas always 1, 0, or -1. These values are probably too small. We should study what these values should be more
    //    if (dy != 0) dyLine = dy / llabs(dy);
    //    if (dx != 0) dxLine = dx / llabs(dx);
        
        CGEventSetIntegerValueField(event, kCGScrollWheelEventDeltaAxis1, dyLine);
        CGEventSetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis1, dy);
        CGEventSetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis1, dy);
        
        CGEventSetIntegerValueField(event, kCGScrollWheelEventDeltaAxis2, dxLine);
        CGEventSetIntegerValueField(event, kCGScrollWheelEventPointDeltaAxis2, dx);
        CGEventSetDoubleValueField(event, kCGScrollWheelEventFixedPtDeltaAxis2, dx);
        
        CGEventPost(kCGSessionEventTap, event);
        
    } else {
        assert(false);
    }
    
}

/// Output - Helper funcs

static BOOL _appSwitcherIsOpen = NO;

+ (void)appSwitcherModificationHasBeenDeactivated {
    /// AppSwitcherModification is aka CommandTab. Should rename to AppSwitcher.
    if (_appSwitcherIsOpen) { /// Not sure if this check is necessary. Should only be called when the appSwitcher is open.
        sendKeyEvent(55, 0, false);
        _appSwitcherIsOpen = NO;
    }
}

void sendKeyEvent(CGKeyCode keyCode, CGEventFlags flags, bool keyDown) {
    
    CGEventTapLocation tapLoc = kCGSessionEventTap;
    
    CGEventRef event = CGEventCreateKeyboardEvent(NULL, keyCode, keyDown);
    CGEventSetFlags(event, flags);
    
    CGEventPost(tapLoc, event);
    CFRelease(event);
    
}

@end
