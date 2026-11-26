class HashfleetCli < Formula
  desc "Terminal dashboard and reviewed controls for your mining fleet"
  homepage "https://hashfleet.app"
  url "https://github.com/SMWARREN/HashFleet/releases/download/v1.0.1/hashfleet-cli-1.0.1-macos-arm64.tar.gz"
  sha256 "d4e1892bf20fe14dd08a50b5067fc04c42e31dba60adf90207dcdf8fcbc1c8f5"
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
