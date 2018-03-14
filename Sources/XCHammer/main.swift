//
//  main.swift
//  XCHammer
//
//  Copyright © 2018 Pinterest Inc. All rights reserved.
//

import Foundation
import PathKit
import Commandant
import Result
import Yams
import ShellOut

extension Path: ArgumentProtocol {
    public static let name: String = "Path"

    public static func from(string: String) -> Path? {
        return Path(string)
    }
}

enum CommandError: Error {
    case swiftException(Error)
    case tulsiException(Error)
    case missingEnvVars(String)
    case io(Error)
}

func getHammerConfig(path: Path) throws -> XCHammerConfig {
    let data = try Data(contentsOf: URL(fileURLWithPath: path.string))
    let config = try YAMLDecoder().decode(XCHammerConfig.self, from: String(data: data, encoding: .utf8)!)
    return config
}

struct GenerateOptions: OptionsProtocol {
    typealias ClientError = CommandError

    let configPath: Path
    let workspaceRootPath: Path
    let bazelPath: Path
    let forceRun: Bool
    let xcworkspacePath: Path?

    private static func getEnvBazelPath() throws -> Path {
        let path = try shellOut(to: "which", arguments: ["bazel"])
        return Path(path)
    }

    static func create(_ configPath: Path) -> (Path?) -> (Path?) -> (Bool) -> (Path?) -> GenerateOptions {
        return { workspaceRootPathOpt in { bazelPathOpt in {
            forceRunOpt in { xcworkspacePathOpt -> GenerateOptions in
                // Defaults to PWD
                let workspaceRootPath: Path = workspaceRootPathOpt?.normalize() ??
                    Path(FileManager.default.currentDirectoryPath)

                // If the user gave us Bazel, then use that.
                // Otherwise, try to get bazel from the env
                let bazelPath: Path
                if let normalizedBazelPath = bazelPathOpt?.normalize() {
                    bazelPath = normalizedBazelPath
                } else {
                    guard let envBazel = try? getEnvBazelPath() else {
                        fatalError("Missing Bazel")
                    }
                    bazelPath = envBazel.normalize()
                }

                return GenerateOptions(
                configPath: configPath.normalize(),
                workspaceRootPath: workspaceRootPath,
                bazelPath: bazelPath,
                forceRun: forceRunOpt,
                xcworkspacePath: xcworkspacePathOpt?.normalize()
            )
        } } } }
    }

    static func evaluate(_ m: CommandMode) -> Result<GenerateOptions, CommandantError<ClientError>> {
        return create
            <*> m <| Argument(usage: "Path to the XCHammerConfig yaml file")
            <*> m <| Option(key: "workspace_root", defaultValue: nil,
                 usage: "The source root of the repo")
            <*> m <| Option(key: "bazel", defaultValue: nil,
                 usage: "Path to the bazel binary")
            <*> m <| Option(key: "force", defaultValue: false,
                 usage: "Force run the generator")
            <*> m <| Option(key: "xcworkspace", defaultValue: nil,
                 usage: "Path to the xcworkspace")
    }
}

struct GenerateCommand: CommandProtocol {
    let verb = "generate"
    let function = "Generate an XcodeProject"

    typealias Options = GenerateOptions

    func run(_ options: Options) -> Result<(), CommandError> {
        do {
            let config = try getHammerConfig(path: options.configPath)
            Generator.generateProjects(workspaceRootPath:
                    options.workspaceRootPath, bazelPath: options.bazelPath,
                    configPath: options.configPath, config:
                    config, xcworkspacePath: options.xcworkspacePath)
            return .success()
        } catch {
            return .failure(.swiftException(error))
        }
    }
}

struct ProcessIpaCommand: CommandProtocol {
    let verb = "process-ipa"
    let function = "Process IPA after a build -- this is expected to be run in an environment with Xcode ENV vars"

    typealias Options = NoOptions<CommandError>

    func run(_: Options) -> Result<(), CommandError> {
        guard let builtProductsDir = ProcessInfo.processInfo.environment["BUILT_PRODUCTS_DIR"] else {
            return .failure(.missingEnvVars("$BUILD_PRODUCTS_DIR not found in the env"))
        }
        guard let codesigningFolderPath = ProcessInfo.processInfo.environment["CODESIGNING_FOLDER_PATH"] else {
            return .failure(.missingEnvVars("$CODESIGNING_FOLDER_PATH not found in the env"))
        }

        return processIpa(builtProductsDir: Path(builtProductsDir), codesigningFolderPath: Path(codesigningFolderPath))
    }
}

struct VersionCommand: CommandProtocol {
    let verb = "version"
    let function = "Print the current version"

    typealias Options = NoOptions<CommandError>
    func run(_: Options) -> Result<(), CommandError> {
        print(Generator.BinaryVersion)
        return .success()
    }
}

func main() {
    let commands = CommandRegistry<CommandError>()
    commands.register(GenerateCommand())
    commands.register(ProcessIpaCommand())
    commands.register(VersionCommand())
    commands.register(HelpCommand(registry: commands))

    var arguments = CommandLine.arguments
    // Remove executable name
    arguments.remove(at: 0)

    func handle(error: CommandError) {
        print("------")
        print("--- EXCEPTION ---")
        print(error)
        print(error.localizedDescription)
        print("------")
    }

    commands.main(defaultVerb: "help", errorHandler: handle(error:))
}

main()
