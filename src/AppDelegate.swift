//
//  Created by Jose Pereira on 2/14/16.
//  Copyright © 2016 fidalgo.io. All rights reserved.
//

import Cocoa
import Carbon

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    @objc var controllerWindow: NSWindowController? = nil
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        NSApplication.shared.isAutomaticCustomizeTouchBarMenuItemEnabled = true
        let sb = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: Bundle.main)
        controllerWindow = sb.instantiateInitialController() as? NSWindowController
        controllerWindow?.window?.orderFrontRegardless()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
    }
}

