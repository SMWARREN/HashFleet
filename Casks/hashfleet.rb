cask "hashfleet" do
  version "0.1.0"
  sha256 "8dc45b35331c58cd1097e08911815e1ab971e1774259554a7261a6286f8c79d0"

  url "https://github.com/SMWARREN/HashFleet/releases/download/v#{version}/HashFleet-#{version}-macos-arm64.zip"
  name "Hash Fleet"
  desc "Native mining fleet monitoring app"
  homepage "https://hashfleet.app"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Hash Fleet.app"
end
