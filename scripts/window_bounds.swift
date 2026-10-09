// Prints the on-screen bounds of a process's windows as x,y,width,height (for `screencapture -R`).
// With "front", only its frontmost window; otherwise all of its windows together, so a sheet is
// captured with the window it belongs to.
//
// Usage: swiftc -o window_bounds scripts/window_bounds.swift && ./window_bounds PID [front]
import CoreGraphics
import Foundation

guard CommandLine.arguments.count > 1, let pid = Int32(CommandLine.arguments[1]) else {
    FileHandle.standardError.write(Data("usage: window_bounds PID [front]\n".utf8))
    exit(2)
}
let frontOnly = CommandLine.arguments.dropFirst(2).first == "front"
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []

var bounds = CGRect.null
for window in windows {
    guard (window[kCGWindowOwnerPID as String] as? Int32) == pid,
        (window[kCGWindowLayer as String] as? Int) == 0,
        let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
        let rect = CGRect(dictionaryRepresentation: dictionary),
        rect.width > 50, rect.height > 50
    else { continue }
    bounds = bounds.union(rect)
    if frontOnly { break }
}
guard !bounds.isNull else { exit(1) }
print("\(Int(bounds.minX)),\(Int(bounds.minY)),\(Int(bounds.width)),\(Int(bounds.height))")
