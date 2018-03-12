//
//  Created by Jose Pereira on 2/14/16.
//  Copyright © 2016 fidalgo.io. All rights reserved.
//

import Carbon
import Cocoa

let kDefaultsGlobalShortcutKeycode = "kDefaultsGlobalShortcutKeycode"
let kDefaultsGlobalShortcutModifiedFlags = "kDefaultsGlobalShortcutModifiedFlags"

fileprivate extension NSTouchBar.CustomizationIdentifier {
	static let appBar = NSTouchBar.CustomizationIdentifier("com.ezopen.appBar")
}

fileprivate extension NSTouchBarItem.Identifier {
	static let test = NSTouchBarItem.Identifier("com.ezopen.test")
	static let appScrubber = NSTouchBarItem.Identifier("com.ezopen.appScrubber")
}

class SearchViewController: NSViewController, NSTextFieldDelegate,
	NSWindowDelegate, SettingsViewControllerDelegate {
	
	@IBOutlet fileprivate var searchText: NSTextField!
	@IBOutlet fileprivate var resultsView: ResultsView!
	
	@objc var settingsWindow = NSWindow()
	@objc var hotkey: DDHotKey?
	
	@objc var topHitWindow: NSWindow!
	@objc var topHitView: NSImageView!
	
	@objc var ignoreDirectories = [String: Bool]()
	@objc var appDirDict = [String: Bool]()
	@objc var appList = [URL]()
	@objc var appNameList = [String]()

	var barAppList = [URL]()
	
	var openDate = [String: Double]() // app path -> unix timestamp
	
	struct Shortcut {
		let keycode: UInt16
		let modifierFlags: UInt
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		searchText.delegate = self;
		
		let applicationDir = NSSearchPathForDirectoriesInDomains(
			.applicationDirectory, .localDomainMask, true)[0];
		
		// appName to dir recursivity key/value dict
		appDirDict[applicationDir] = true
		appDirDict["/System/Library/CoreServices/"] = false
		ignoreDirectories["/System/Library/CoreServices"] = true

		if let openDate = UserDefaults.standard.dictionary(forKey: "openDate") as? [String:Double] {
			self.openDate = openDate
		}
		initFileWatch(Array(appDirDict.keys))
		updateAppList()
		
		UserDefaults.standard.register(defaults: [
			//cmd+Space is the default shortcut
			kDefaultsGlobalShortcutKeycode: kVK_Space,
			kDefaultsGlobalShortcutModifiedFlags: NSEvent.ModifierFlags.command.rawValue
			])
		
		configureGlobalShortcut()
		createTopHitWindow();
	}

	override func makeTouchBar() -> NSTouchBar? {
		print("making touch bar")
		let touchBar = NSTouchBar()
		touchBar.delegate = self
		
		touchBar.customizationIdentifier = .appBar
		touchBar.defaultItemIdentifiers = [.test, .appScrubber]
		touchBar.customizationAllowedItemIdentifiers = [.appScrubber]
		touchBar.principalItemIdentifier = .appScrubber
		
		return touchBar
	}
	
	@objc let callback: FSEventStreamCallback = {
		(streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) -> Void in
		let mySelf: SearchViewController = unsafeBitCast(clientCallBackInfo, to: SearchViewController.self)
		mySelf.updateAppList()
	}
	
	@objc func initFileWatch(_ dirs: [String]) {
		let allocator: CFAllocator? = kCFAllocatorDefault
		
		typealias FSEventStreamCallback = @convention(c) (ConstFSEventStreamRef, UnsafeMutableRawPointer, Int, UnsafeMutableRawPointer, UnsafePointer<FSEventStreamEventFlags>, UnsafePointer<FSEventStreamEventId>) -> Void
		
		var context = FSEventStreamContext(
			version: 0,
			info: Unmanaged.passUnretained(self).toOpaque(),
			retain: nil,
			release: nil,
			copyDescription: nil)
		
		let sinceWhen: FSEventStreamEventId = UInt64(kFSEventStreamEventIdSinceNow)
		let latency: CFTimeInterval = 1.0
		let flags: FSEventStreamCreateFlags = UInt32(kFSEventStreamCreateFlagNone)
		
		let eventStream: FSEventStreamRef! = FSEventStreamCreate(
			allocator,
			callback,
			&context,
			dirs as CFArray,
			sinceWhen,
			latency,
			flags
		)
		
		FSEventStreamScheduleWithRunLoop(eventStream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
		FSEventStreamStart(eventStream)
	}
	
	@objc func updateAppList() {
		appList.removeAll()
		appNameList.removeAll()
		for dir in appDirDict.keys {
			appList.append(
				contentsOf: getAppList(
					URL(fileURLWithPath: dir, isDirectory: true),
					recursive: appDirDict[dir]!))
		}
		
		for app in appList {
			let appName = (app.deletingPathExtension().lastPathComponent)
			appNameList.append(appName)
		}
		updateBarAppList()
	}

	private func updateBarAppList() {
		let src = self.resultsView.list.count > 0 ? self.resultsView.list : self.appList;
		barAppList = src.sorted(by: { (openDate[$0.path] ?? 0) > (openDate[$1.path] ?? 0) })
	}
	
	func getGlobalShortcut() -> Shortcut {
		let keycode =  UserDefaults.standard
			.integer(forKey: kDefaultsGlobalShortcutKeycode)
		let modifierFlags = UserDefaults.standard
			.integer(forKey: kDefaultsGlobalShortcutModifiedFlags)
		return Shortcut(keycode: UInt16(keycode), modifierFlags: UInt(modifierFlags))
	}
	
	@objc func configureGlobalShortcut() {
		let globalShortcut = getGlobalShortcut()

		if hotkey != nil {
			DDHotKeyCenter.shared()
				.unregisterHotKey(hotkey)
		}
		
		hotkey = DDHotKeyCenter.shared()
			.registerHotKey(withKeyCode: globalShortcut.keycode,
				modifierFlags: globalShortcut.modifierFlags,
				target: self, action: #selector(resumeApp), object: nil)

		if hotkey == nil {
			print("Could not register global shortcut.")
		}
	}
	
	@objc func createTopHitWindow() {
		let size: CGFloat = 384;
		let ssize = NSScreen.main!.frame.size;
		let frame = NSRect(x: ssize.width/CGFloat(2) - size/CGFloat(2), y: ssize.height/CGFloat(2) - size/CGFloat(2), width: size, height: size)
		
		self.topHitWindow = NSWindow(contentRect: frame, styleMask: NSWindow.StyleMask.borderless, backing: .buffered, defer: false)
		self.topHitWindow.backgroundColor = NSColor.clear
		self.topHitWindow.isOpaque = false
		self.topHitWindow.orderFrontRegardless()
		
		self.topHitView = NSImageView(frame: NSRect(x: 0, y:0, width: size, height: size))
		
		self.topHitWindow.contentView?.addSubview(self.topHitView)
	}
	
	@objc func resumeApp() {
		NSApplication.shared.activate(ignoringOtherApps: true)
		topHitWindow.collectionBehavior = NSWindow.CollectionBehavior.canJoinAllSpaces
		topHitWindow.orderFrontRegardless()
		view.window?.collectionBehavior = NSWindow.CollectionBehavior.canJoinAllSpaces
		view.window?.orderFrontRegardless()
		
		let controller = view.window as! SearchWindow;
		controller.updatePosition();
	}
	
	@objc func getAppList(_ appDir: URL, recursive: Bool = true) -> [URL] {
		if ignoreDirectories[appDir.path] ?? false {
			return [URL]()
		}
		var list = [URL]()
		let fileManager = FileManager.default
		do {
			let subs = try fileManager.contentsOfDirectory(atPath: appDir.path)
			
			for sub in subs {
				let dir = appDir.appendingPathComponent(sub)
				
				if dir.pathExtension == "app" {
					list.append(dir);
				} else if dir.hasDirectoryPath && recursive {
					list.append(contentsOf: self.getAppList(dir))
				}
			}
		} catch {
			print(error)
		}
		return list
	}
	
	override func controlTextDidChange(_ obj: Notification) {
		let list = self.getFuzzyList()
		if !list.isEmpty {
			self.resultsView.list = list
			if false {
				// update top hit display after a short delay, to avoid flickering through early possibilities
				DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: self.updateTopHit);
			} else {
				self.updateTopHit()
			}
		} else {
			self.resultsView.clear()
			self.updateTopHit()
		}
		self.updateBarAppList()
	}
	
	func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
		if commandSelector == #selector(moveLeft(_:)) {
			self.resultsView.selectedAppIndex -= 1
			self.updateTopHit()
			return true
		} else if commandSelector == #selector(moveRight(_:)) {
			self.resultsView.selectedAppIndex += 1
			self.updateTopHit()
			return true
		} else if commandSelector == #selector(insertTab(_:)) {
			let list = getStartingBy(searchText.stringValue)
			if !list.isEmpty {
				self.resultsView.list = list
			} else {
				self.resultsView.clear()
			}
			self.updateTopHit()
			return true
		} else if commandSelector == #selector(insertNewline(_:)) {
			// open current selected app
			if let app = resultsView.selectedApp {
				NSWorkspace.shared.launchApplication(app.path)
				
				openDate[app.path] = NSDate().timeIntervalSince1970
				UserDefaults.standard.set(openDate, forKey: "openDate")
			}
			self.clearFields()
			return true
		} else if commandSelector == #selector(cancelOperation(_:)) {
			closeApp()
			return true
		}
		return false
	}
	
	@objc func clearFields() {
		self.searchText.stringValue = ""
		self.resultsView.clear()
		self.topHitView.image = nil
	}
	
	@objc func closeApp() {
		clearFields()
		NSApplication.shared.hide(nil)
	}
	
	@objc func getStartingBy(_ text: String) -> [URL] {
		//todo turn this into a regex
		return appList.sorted(by: {
			//make it sorted
			let appName1 = (($0 as NSURL).deletingPathExtension!.lastPathComponent.lowercased())
			let appName2 = (($1 as NSURL).deletingPathExtension!.lastPathComponent.lowercased())
			
			return appName1.localizedCaseInsensitiveCompare(appName2) == ComparisonResult.orderedAscending
		}).filter({
			let appName = (($0 as NSURL).deletingPathExtension!.lastPathComponent.lowercased())
			return appName.hasPrefix(text.lowercased()) ||
				appName.contains(" " + text.lowercased())
		})
	}
	
	@objc func getFuzzyList() -> [URL] {
		var scoreDict = [URL: Double]()
		
		for app in appList {
			let appName = (app.deletingPathExtension().lastPathComponent)
			
			let score = FuzzySearch.score(
				originalString: appName, stringToMatch: self.searchText.stringValue)
			
			if score > 0 {
				scoreDict[app] = score
			}
		}
		
		// sort by most-recent-open date
		let resultsList = scoreDict.sorted(by: {
			let t0 = openDate[$0.0.path] ?? 0
			let t1 = openDate[$1.0.path] ?? 0
			if t0 > t1 {
				return true
			}
			if t1 > t0 {
				return false
			}
			// tie break on search score for never-opened items
			return $0.1 > $1.1
		}).map({$0.0})
		
		return resultsList
	}
	
	@objc func updateTopHit() {
		if let app = resultsView.selectedApp {
			let img = NSWorkspace.shared.icon(forFile: app.path)
			img.size = NSSize(width: 512, height: 512)
			topHitView.image = img
		} else {
			topHitView.image = nil
		}
	}
	
	@IBAction func openSettings(_ sender: AnyObject) {
		let sb = NSStoryboard(name: NSStoryboard.Name(rawValue: "Settings"), bundle: Bundle.main)
		let settingsView = sb.instantiateInitialController() as? SettingsViewController
		settingsView?.delegate = self
		
		settingsWindow.contentViewController = settingsView
		weak var wSettingsWindow = settingsWindow
		
		view.window?.beginSheet(settingsWindow,
			completionHandler: { (response) -> Void in
				wSettingsWindow?.contentViewController = nil
		})
	}
	
	@objc func onSettingsApplied() {
		view.window?.endSheet(settingsWindow)

		//reconfigure global shortcuts if changed
		configureGlobalShortcut()
	}
	
	@objc func onSettingsCanceled() {
		view.window?.endSheet(settingsWindow)
	}

	// func settingsURL() -> URL? {
	// 	return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("/.ezopen.json")
	// }

}

// MARK: - NSTouchBarDelegate

extension SearchViewController: NSTouchBarDelegate {    
	func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
		if identifier == .test {
			print("test item???")
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.systemGray.cgColor
            let custom = NSCustomTouchBarItem(identifier: identifier)
            custom.view = view
            return custom
		}

		print("another item??")
		
		let item = ImageScrubberBarItemSample(identifier: identifier)
		//scrubberItem.customizationLabel = NSLocalizedString("Image Scrubber", comment:"")
		item.scrubberItemWidth = 30
			
		guard let scrubber = item.view as? NSScrubber else { return nil }
		
		// scrubber.mode = selectedMode
		// scrubber.showsArrowButtons = showsArrows.state == NSControl.StateValue.on
		// scrubber.selectionBackgroundStyle = selectedSelectionBackgroundStyle
		// scrubber.selectionOverlayStyle = selectedSelectionOverlayStyle
		scrubber.scrubberLayout = NSScrubberFlowLayout()
		
		// if useBackgroundColor.state == NSControl.StateValue.on {
		//     scrubber.backgroundColor = backgroundColorWell.color
		// }
		
		// if useBackgroundView.state == NSControl.StateValue.on {
		//     scrubber.backgroundView = CustomBackgroundView()
		// }
		
		// Set the scrubber's width to be 400.
		let viewBindings: [String: NSView] = ["scrubber": scrubber]
		let hconstraints = NSLayoutConstraint.constraints(withVisualFormat: "H:[scrubber(400)]",
		                                                   options: [],
		                                                   metrics: nil,
		                                                   views: viewBindings)
		NSLayoutConstraint.activate(hconstraints)
		
		return item
	}
}
