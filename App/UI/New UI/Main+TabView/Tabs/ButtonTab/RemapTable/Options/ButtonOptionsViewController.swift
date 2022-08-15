//
// --------------------------------------------------------------------------
// ButtonOptionsViewController.swift
// Created for Mac Mouse Fix (https://github.com/noah-nuebling/mac-mouse-fix)
// Created by Noah Nuebling in 2022
// Licensed under MIT
// --------------------------------------------------------------------------
//

import Cocoa
import ReactiveCocoa
import ReactiveSwift

class ButtonOptionsViewController: NSViewController {

    /// Vars
    
    static var instance: ButtonOptionsViewController? = nil
    
    var lockPointer = ConfigValue<Bool>(configPath: "Other.lockPointerDuringDrag")
    
    /// IB outlets & actions
    
    @IBOutlet weak var doneButton: NSButton!
    @IBOutlet weak var lockPointerButton: NSButton!
        
    @IBAction func done(_ sender: Any) {
        ButtonOptionsViewController.remove()
    }
    
    /// Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        lockPointerButton.reactive.boolValue <~ lockPointer
        lockPointer <~ lockPointerButton.reactive.boolValues
    }
    
    /// Interface
    
    @objc static func add() {
        
        /// Create new instance every time. Otherwise the done button won't be blue after the first open
        instance?.nibBundle?.unload()
        instance = nil
        instance = ButtonOptionsViewController(nibName: "ButtonOptionsViewController", bundle: Bundle.main)
        
        /// Open sheet
        MainAppState.shared.tabViewController.presentAsSheet(instance!)
    }
    
    @objc static func remove() {
        
        /// Close sheet
        MainAppState.shared.tabViewController.dismiss(instance!)
    }
    
    
    
}