import XcodeCompilationDatabaseCore
import Foundation
import ShellOut

guard CommandLine.arguments.count > 1 else {
    print("""
          usage: /path/to/xcconfig
          """)
    exit(0)
}

/// This program works by doing a build of an iOS application with a user
/// specified xcconfig, and exporting the flags that Xcode passed to various
/// compilers
do {
    guard let fixtureBundle = Bundle.main.path(forResource: "Fixtures", ofType:
                                             "bundle") else {
        fatalError("Missing fixtures")
    }
    let xcconfig = CommandLine.arguments[1]

    let tmpDir = NSTemporaryDirectory() + "/" + UUID().uuidString
    try FileManager.default.createDirectory(atPath: tmpDir,
        withIntermediateDirectories: true,
        attributes: [:])
    try FileManager.default.copyItem(atPath: fixtureBundle,
        toPath: tmpDir + "/Fixtures")
    try FileManager.default.copyItem(atPath: xcconfig,
        toPath: tmpDir + "/Config.xcconfig")


    let iOSDir = tmpDir + "/Fixtures/iOSApp"
    let buildCommand = ["/bin/bash -c 'xcodebuild -project iOSApp.xcodeproj -scheme iOSApp -sdk iphonesimulator12.2 -configuration Debug 2>&1'"]
    let log = try ShellOut.shellOut(to: buildCommand, at: iOSDir)
    let parsed = parse(log: log)
    let diagFlags = parsed.compactMap {
        parsedValue -> [String]? in
        guard case let .entry(_, lexed, _) = parsedValue else {
            return nil
        }
        return lexed.filter { $0.hasPrefix("-W") }
    }
    guard let firstDiagFlags = diagFlags.first else {
        fatalError("Missing flags")
    }

    let bzlHeader = """
    # This file is maintained by XCCHammer
    """
    let bzl = bzlHeader + "\nDIAG_FLAGS = [\n" + firstDiagFlags.compactMap {
        arg -> String in
        return "    \"" + arg + "\","
        }.joined(separator: "\n") + "\n]"
    print(bzl)
} catch {
    fatalError(error.localizedDescription)
}

