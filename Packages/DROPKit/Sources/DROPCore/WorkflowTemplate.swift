import Foundation

/// The release workflow DROP offers to add to a repository that has none, always through a pull
/// request. It builds on Linux, macOS and Windows for x86-64 and arm64 and uploads each build as an
/// artifact; DROP then attaches the artifacts to the drop. It doesn't create releases itself.
public enum WorkflowTemplate {
    public static let path = ".github/workflows/release.yml"

    public static let release = #"""
        name: Release

        # Builds every tag like v1.2.3 (or a run started by hand) on Linux, macOS and Windows for
        # x86-64 and arm64, and uploads each build as an artifact. Replace the build step with your
        # project's build; put the files to release in dist/.
        on:
          push:
            tags: ["v*"]
          workflow_dispatch:

        permissions:
          contents: read

        jobs:
          build:
            name: Build (${{ matrix.os }}, ${{ matrix.arch }})
            runs-on: ${{ matrix.runner }}
            strategy:
              fail-fast: false
              matrix:
                include:
                  - { os: linux, arch: amd64, runner: ubuntu-24.04 }
                  - { os: linux, arch: arm64, runner: ubuntu-24.04-arm }
                  - { os: macos, arch: amd64, runner: macos-15-intel }
                  - { os: macos, arch: arm64, runner: macos-15 }
                  - { os: windows, arch: amd64, runner: windows-2025 }
                  - { os: windows, arch: arm64, runner: windows-11-arm }
            steps:
              - uses: actions/checkout@v5
              - name: Build
                shell: bash
                env:
                  TARGET_OS: ${{ matrix.os }}
                  TARGET_ARCH: ${{ matrix.arch }}
                run: |
                  # Replace with your build.
                  mkdir -p dist
                  echo "Build for $TARGET_OS/$TARGET_ARCH" > "dist/build-$TARGET_OS-$TARGET_ARCH.txt"
              - uses: actions/upload-artifact@v4
                with:
                  name: build-${{ matrix.os }}-${{ matrix.arch }}
                  path: dist/
        """#
}
