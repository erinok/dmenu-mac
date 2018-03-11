//
//  Created by Jose Pereira on 2/14/16.
//  Copyright © 2016 fidalgo.io. All rights reserved.
//

import Cocoa

class ResultsView: NSView {
    @objc let rectFillPadding:CGFloat = 5
    @objc var _list = [URL]()
    
    @objc var _selectedAppIndex: Int = 0
    @objc var selectedAppIndex: Int {
        get {
            return _selectedAppIndex
        }
        set {
            if newValue < 0 || newValue >= _list.count {
                return
            }
            
            _selectedAppIndex = newValue
            needsDisplay = true;
        }
    }
    
    @objc var list: [URL] {
        get {
            return _list
        }
        set {
            _selectedAppIndex = 0
            _list = newValue;
            needsDisplay = true;
        }
    }
    
    @objc var selectedApp: URL? {
        get {
            if _selectedAppIndex < 0 || _selectedAppIndex >= _list.count {
                return nil
            } else {
                return _list[_selectedAppIndex]
            }
        }
    }
    
    @objc func clear() {
        _list.removeAll()
        needsDisplay = true;
    }
    
    override func draw(_ dirtyRect: NSRect) {
        let textFontAttributes = [NSAttributedStringKey: Any]()
        
        var textX = CGFloat(rectFillPadding)
        for i in 0 ..< list.count {
            let appName = (_list[i].deletingPathExtension().lastPathComponent) as NSString
            let size = appName.size(withAttributes: textFontAttributes)
            let textY = (frame.height - size.height) / 2
            
            if _selectedAppIndex == i {
                NSColor.selectedTextBackgroundColor.setFill()
                NSRect(
                    x: textX - rectFillPadding,
                    y: textY - rectFillPadding,
                    width: size.width + rectFillPadding * 2,
                    height: size.height + rectFillPadding * 2).fill()
            }
            
            appName.draw(in: NSRect(
                x: textX,
                y: textY,
                width: size.width,
                height: size.height), withAttributes: [NSAttributedStringKey: AnyObject]())
            
            textX += 10 + size.width;
            
            //stop drawing if we passed the visible frame
            if textX > frame.width {
                break;
            }
        }
    }
}
