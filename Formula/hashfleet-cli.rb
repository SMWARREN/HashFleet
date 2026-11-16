class HashfleetCli < Formula
  desc "Terminal dashboard and reviewed controls for your mining fleet"
  homepage "https://hashfleet.app"
  url "https://github.com/SMWARREN/HashFleet/releases/download/v1.0.0/hashfleet-cli-1.0.0-macos-arm64.tar.gz"
  sha256 "4536a37f83a0ed0341f9214b7fa534c32245900aef9b69c0eca37de2a0e2dfe3"
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
