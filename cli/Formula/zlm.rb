# Homebrew formula for zlm (ZLaunch Manager CLI)
# Install: brew install zavora-ai/tap/zlm

class Zlm < Formula
  desc "ZLaunch Manager - macOS launchd service manager CLI"
  homepage "https://github.com/zavora-ai/macos-zlaunch-manager"
  # Use git tag + revision instead of the auto-generated source tarball.
  # GitHub's archive/refs/tags/*.tar.gz files are NOT guaranteed to be
  # byte-stable over time, which causes intermittent brew checksum
  # mismatches. A pinned git revision is reproducible and immune to that.
  url "https://github.com/zavora-ai/macos-zlaunch-manager.git",
      tag:      "v1.2.0",
      revision: "c1e77c6e045a07dc5bfaa4bba0fadc740480d7b5"
  license "Apache-2.0"
  head "https://github.com/zavora-ai/macos-zlaunch-manager.git", branch: "main"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    cd "cli" do
      system "swift", "build", "-c", "release", "--disable-sandbox"
      bin.install ".build/release/zlm"
    end
  end

  test do
    assert_match "ZLaunch Manager", shell_output("#{bin}/zlm --help")
  end
end
