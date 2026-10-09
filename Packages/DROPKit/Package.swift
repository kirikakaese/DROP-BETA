// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DROPKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DROPCore", targets: ["DROPCore"]),
        .library(name: "DROPGitHub", targets: ["DROPGitHub"]),
        .library(name: "DROPRegistries", targets: ["DROPRegistries"]),
        .library(name: "DROPPersistence", targets: ["DROPPersistence"]),
        .library(name: "DROPServices", targets: ["DROPServices"]),
        .library(name: "DROPUI", targets: ["DROPUI"]),
    ],
    dependencies: [
        // SQLite toolkit for the project list, drop history and audit log. Chosen over SwiftData
        // for explicit migrations and Swift 6 concurrency support. Never stores secrets.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
    ],
    targets: [
        // Models, errors and pure logic. No UI, no networking.
        .target(name: "DROPCore"),
        // The GitHub REST client: releases, tags, assets, Actions, pull requests. Tokens are passed
        // in for each request, never stored here.
        .target(name: "DROPGitHub", dependencies: ["DROPCore"]),
        // Package registry publishers (Homebrew tap, Scoop bucket, GHCR, npm).
        .target(name: "DROPRegistries", dependencies: ["DROPCore", "DROPGitHub"]),
        // Metadata store (GRDB/SQLite). Metadata only: no secrets.
        .target(name: "DROPPersistence", dependencies: ["DROPCore", .product(name: "GRDB", package: "GRDB.swift")]),
        // Protocol-based services with live and in-memory implementations.
        .target(name: "DROPServices", dependencies: ["DROPCore", "DROPGitHub", "DROPRegistries", "DROPPersistence"]),
        // SwiftUI feature views. Depends on service protocols only.
        .target(name: "DROPUI", dependencies: ["DROPCore", "DROPServices"]),
        // Test-only fixtures. Not part of any product, so it never ships in the app.
        .target(name: "DROPTestFixtures", dependencies: ["DROPCore"]),

        .testTarget(name: "DROPCoreTests", dependencies: ["DROPCore", "DROPTestFixtures"]),
        .testTarget(name: "DROPGitHubTests", dependencies: ["DROPGitHub", "DROPTestFixtures"]),
        .testTarget(name: "DROPRegistriesTests", dependencies: ["DROPRegistries"]),
        .testTarget(name: "DROPPersistenceTests", dependencies: ["DROPPersistence", "DROPTestFixtures"]),
        .testTarget(name: "DROPServicesTests", dependencies: ["DROPServices", "DROPTestFixtures"]),
        .testTarget(name: "DROPUITests", dependencies: ["DROPUI", "DROPServices", "DROPTestFixtures"]),
    ]
)
