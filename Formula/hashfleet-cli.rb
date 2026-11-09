class HashfleetCli < Formula
  desc "Terminal dashboard and reviewed controls for your mining fleet"
  homepage "https://hashfleet.app"
  url "https://github.com/SMWARREN/HashFleet/releases/download/v0.1.0/hashfleet-cli-0.1.0-macos-arm64.tar.gz"
  sha256 "513a868ee3f178fcfde8e8382fee4c620db0241e3ed639cbf3bdbc562edb0b8d"
  license "GPL-3.0-only"

  depends_on :macos
  depends_on arch: :arm64
  on_macos do
    depends_on macos: :sonoma
  end

  def install
    libexec.install "hashfleet", "GRDB_GRDB.bundle"
    bin.write_exec_script libexec/"hashfleet"
    pkgshare.install "THIRD_PARTY_NOTICES.txt"
  end

  test do
    assert_match "hashfleet", shell_output("#{bin}/hashfleet --help")
  end
end
