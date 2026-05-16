# Homebrew formula for lm (Launch Manager CLI)
# Install: brew install zavora/tap/lm

class Lm < Formula
  desc "macOS launchd service manager - CLI interface"
  homepage "https://github.com/zavora/macos-launch-manager"
  url "https://github.com/zavora/macos-launch-manager/archive/refs/tags/v1.0.0.tar.gz"
  sha256 "PLACEHOLDER_SHA256"
  license "Apache-2.0"

  depends_on xcode: ["15.0", :build]
  depends_on :macos

  def install
    cd "cli" do
      system "swift", "build", "-c", "release", "--disable-sandbox"
      bin.install ".build/release/lm"
    end
  end

  test do
    assert_match "Launch Manager", shell_output("#{bin}/lm --help")
  end
end
