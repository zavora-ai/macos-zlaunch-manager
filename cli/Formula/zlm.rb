# Homebrew formula for zlm (ZLaunch Manager CLI)
# Install: brew install zavora-ai/tap/zlm

class Zlm < Formula
  desc "macOS launchd service manager - CLI interface"
  homepage "https://github.com/zavora-ai/macos-zlaunch-manager"
  url "https://github.com/zavora-ai/macos-zlaunch-manager/archive/refs/tags/v1.2.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
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
