//
// --------------------------------------------------------------------------
// NaturalAccelerationCurve.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2022
// Licensed under MIT
// --------------------------------------------------------------------------
//

///
/// See https://www.desmos.com/calculator/ql0uppqk4n
/// This visualizes exactly what this curve does except for the **clipping**
///

import Cocoa

@objc class NaturalAccelerationCurve: AccelerationCurve {
    
    let a: Double
    let b: Double
    let c: Double
    let d: Double
    
    convenience init(lowSpeed v0: Double, lowSens s0: Double, highSpeed v1: Double, highSens s1: Double, curvature scurve: Double) {
        let a = v0
        let b = s0
        let c = 1/(1-scurve) - 1
        let d = (b * pow(M_E, c * (a-v1)) - s1) / (pow(M_E, c * (a - v1)) - 1) - s0
        
        self.init(a: a, b: b, c: c, d: d)
    }
    
    required init(a: Double, b: Double, c: Double, d: Double) {
        self.a = a
        self.b = b
        self.c = c
        self.d = d
    }
    
    override func evaluate(at x: Double) -> Double {
        let xClipped = SharedUtilitySwift.clip(x, betweenLow: a, high: Double.infinity) /// Clipping makes it so that sens is flat below v0. This is similar to the offset in rawAccel
        return evaluateCore(at: xClipped)
    }
    
    func evaluateCore(at x: Double) -> Double {
        return (-d * (pow(M_E, -c * (x-a)) - 1)) + b
    }
}
