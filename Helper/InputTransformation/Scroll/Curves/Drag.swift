//
// --------------------------------------------------------------------------
// Drag.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2021
// Licensed under MIT
// --------------------------------------------------------------------------
//

/**
 Models the the effects of drag forces. Drag forces are like friction forces, but magnitude depends on the current speed
 It's easier in to just use the differential drag definition directly and calculate a new speed every frame based on the previous speed. And then figure out how far to animate each frame based on that speed.
 But you can also solve the differential drag equations in to get d(t) and v(t) functions (distance / velocity for a given time).
 These solved drag equations are what this class provides.
 The solved drag equations have the advantage, that we can simply plug them into our existing Animator.swift class.
 And they also allow us to analyze the animation in a deeper way.
 For example they let us find out how long and how far we'll animate for before coming to a stop, by setting v(t) to 0 and solving for t, and then plugging that t back into d(t).
 That kind of thing is not easy is not easy if you use the frame by frame based approach.
 Also mathsy stuff is fun and I really need to stop overengineering things but I can't please help.
 */

/**
 Here are the relevant __formulas__.
 Use these to solve/view them:
 - https://www.wolframalpha.com/
 - https://www.desmos.com/calculator/c4g8u0ysvd
 
 
 # Drag definition
 (Aka. "The differential equation")
 ```
 v'(t) = - a v(t)^b
 ```
 Source Wikipedia. Simplified and adapted for our needs.
- Stripped away things that depend on mass and area of the object and stuff
- Made the exponent into a variable (b) instead of 2. To be able to control the feel of the curve better.
 
 # Speed equation
 (Aka. Solved differential equation)
 ```
 v(t) = ((b - 1) (a t + c))^(1/(1 - b))
 ```
 Altered slightly, so that c is the time offset: that way it might be easier to deal with / reason about
 ```
 v(t)=((b-1)(a(t-c)))^{(1/(1-b))}
 ```
 - ^ WA can't integrate this for some reason, but it can integrate the original equation
 ```
 v(t) = ((b - 1) (a (t - c)))^(1/(1 - b))
 ```
 - ^ I wrote the equation more like the original and now WA __can__ integrate it. Weird
 - `c` shifts the curve along the t axis
 
 Now we want to __solve for c__, so we can ask:
 - What is the c that gives us the curve for an initial speed of v_0?
 - Or phrased differently: what is the c such that the curve crosses the v axis at v_0
 - Or phrased differently: what is the c such that the curve passes through the point: (t: 0, v: v_0)
 
 I can't get Wolfram Alpha to solve for c so we'll solve it on paper.
 Result
 ```
 c = t - ( (v^{1-b}) / ((b-1)a) )
 ```
 ^ (I might have made a mistake with the signs. Just flip the sign if this doesn't work)
 
 Now we want to solve for t, so we can ask:
 - At which point in time does the curve stop moving
 - Or phrased differently: At which t does v(t) become (reasonably close to) 0
 
 ```
 t = v^{1 - b}/(a (b - 1)) + c
 ```
 ^ (WA says: Only valid where a (b - 1) v^b != 0)
 
 # Distance equation
 (Aka. Indefinite Integral or antiderivative of the speed equation)
 ```
 d(t) = (a (b - 1) (t - c))^(1/(1 - b) + 1)/(a (b - 2)) + k
 ```
 - `k` shifts the curve along the d axis
 
 Now we want to solve for k so we can ask:
 - What is the k that gives us the curve that starts at distance 0
 - Or phrased differently: what is the k such that the curve passes through (t: 0, d: 0)
 
```
 k = ((b - 1) (c - t) (a (b - 1) (t - c))^(1/(1 - b)))/(b - 2) + d
 ```
 ^ WA says this is only valid where b != 2 and a != 0. The requirement that b != 0 might be a problem
 
 Or we can simply get k such that the curve passes through (t, d) with `k = -d(t) + d`. Where d(t) is defined as above but with k=0.
 
 That's it. Now we have all the formulas ready!
 */


import Foundation

class Drag: RealFunction {

    var a: Double
    var b: Double
    var c: Double
    var k: Double
    
    var timeToStop: Double
    var distanceToStop: Double

    init(coefficient:Double, exponent: Double, initialSpeed v0: Double, stopSpeed vs: Double) {
        /// Speed will never reach 0 exactly so we need to specify `stopSpeed`, the speed at which we consider it stopped
        
        self.a = coefficient
        self.b = exponent
        
        c = 0 // Initialize everything to 0 so swift doesn't complain when we use instance methods
        k = 0
        timeToStop = 0
        distanceToStop = 0
        
        // Choose c such that v(t) passes through (t: 0, v: v0)
        c = getC(t: 0, v: v0)
        
        // Choose k such that d(t) passes through (t: 0, d: 0)
        k = getK(t: 0, d: 0)
        
        // Get time and distance to stop
        timeToStop = getT(v: vs)
        distanceToStop = getD(t: timeToStop, k: self.k)
    }
    
    /// v(t)
    
    func getV(t: Double) -> Double {
        return pow((b - 1) * (a * (t - c)), 1/(1 - b))
    }

    func getC(t: Double, v: Double) -> Double {
        /// Get c such that v(t) passes through the point (t, v)
        return t - (pow(v, 1-b) / ((b-1) * a))
    }
    
    func getT(v: Double) -> Double {
        /// Get the t where v(t) is v
        return pow(v, 1 - b) / (a * (b - 1)) + c
    }
    
    /// d(t)
    
    func getD(t: Double, k: Double) -> Double {
        return pow(a * (b - 1) * (t - c), 1/(1 - b) + 1) / (a * (b - 2)) + k
    }
    
    func getK(t: Double, d: Double) -> Double {
        /// Get k such that d(t) passes through the point (t, d)
        return -getD(t: t, k: 0) + d
    }
    
    /// Interface
    
    func evaluate(at tUnit: Double) -> Double {
        /// Animator.swift expects its animation curves to pass through (0,0) and (1,1), so we'll scale our curve accordingly before evaluating
        
        let t = Math.scale(value: tUnit, from: .unitInterval(), to: Interval(start: 0, end: timeToStop))
        let d = getD(t: t, k: self.k)
        let dUnit = Math.scale(value: d, from: Interval(start: 0, end: distanceToStop), to: .unitInterval())
        
        return dUnit
    }
}