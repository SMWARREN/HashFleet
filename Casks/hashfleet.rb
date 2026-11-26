cask "hashfleet" do
  version "1.0.1"
  sha256 "64dce5b17d2b6ba39d0063eca3c13c95b0a839e132076a6835575811164b5603"

  url "https://github.com/SMWARREN/HashFleet/releases/download/v#{version}/HashFleet-#{version}-macos-arm64.zip"
  name "Hash Fleet"
  desc "Native mining fleet monitoring app"
  homepage "https://hashfleet.app"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Hash Fleet.app"
end
