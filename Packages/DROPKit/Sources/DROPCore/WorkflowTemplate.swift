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

    /// The workflow that publishes a registry DROP manages by starting it on the tag, for
    /// destinations that publish through a workflow (GHCR and npm).
    public static func publishPath(for destination: Destination) -> String? {
        switch destination {
        case .ghcr: ".github/workflows/publish-ghcr.yml"
        case .npm: ".github/workflows/publish-npm.yml"
        case .githubRelease, .homebrewTap, .scoopBucket: nil
        }
    }

    public static func publish(for destination: Destination) -> String? {
        switch destination {
        case .ghcr: ghcr
        case .npm: npm
        case .githubRelease, .homebrewTap, .scoopBucket: nil
        }
    }

    /// Pushes the image to GitHub Container Registry with the workflow's own `GITHUB_TOKEN`.
    public static let ghcr = #"""
        name: Publish image

        # Builds the Dockerfile at the root of the repository for the tag DROP starts this on, and
        # pushes it to GitHub Container Registry as ghcr.io/OWNER/REPO, tagged with the version and,
        # for releases that aren't betas, latest. It signs in with the workflow's own GITHUB_TOKEN,
        # so no registry token is stored anywhere.
        on:
          workflow_dispatch:

        permissions:
          contents: read
          packages: write

        jobs:
          publish:
            runs-on: ubuntu-24.04
            steps:
              - uses: actions/checkout@v5
              - uses: docker/setup-buildx-action@v3
              - uses: docker/login-action@v3
                with:
                  registry: ghcr.io
                  username: ${{ github.actor }}
                  password: ${{ secrets.GITHUB_TOKEN }}
              - id: meta
                uses: docker/metadata-action@v5
                with:
                  images: ghcr.io/${{ github.repository }}
                  tags: |
                    type=semver,pattern={{version}}
                    type=raw,value=latest,enable=${{ !contains(github.ref_name, '-') }}
              - uses: docker/build-push-action@v6
                with:
                  context: .
                  push: true
                  tags: ${{ steps.meta.outputs.tags }}
                  labels: ${{ steps.meta.outputs.labels }}
        """#

    /// Publishes to npm with trusted publishing (OpenID Connect) and provenance.
    public static let npm = #"""
        name: Publish to npm

        # Publishes the package for the tag DROP starts this on, with provenance. It uses npm's trusted
        # publishing, so no npm token is stored anywhere: on npmjs.com, add this repository and
        # workflow as a trusted publisher of the package first. Betas are published under the "next"
        # dist-tag instead of "latest".
        on:
          workflow_dispatch:

        permissions:
          contents: read
          id-token: write

        jobs:
          publish:
            runs-on: ubuntu-24.04
            steps:
              - uses: actions/checkout@v5
              - uses: actions/setup-node@v5
                with:
                  node-version: 24
                  registry-url: https://registry.npmjs.org
              - run: npm ci
              - name: Publish
                env:
                  DIST_TAG: ${{ contains(github.ref_name, '-') && 'next' || 'latest' }}
                run: npm publish --provenance --access public --tag "$DIST_TAG"
        """#
}
