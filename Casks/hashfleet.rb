cask "hashfleet" do
  version "1.0.0"
  sha256 "74ae6c668dc6d891ff7cb07798e1668459782516626b941583394291e411b850"

  url "https://github.com/SMWARREN/HashFleet/releases/download/v#{version}/HashFleet-#{version}-macos-arm64.zip"
  name "Hash Fleet"
  desc "Native mining fleet monitoring app"
  homepage "https://hashfleet.app"

  depends_on arch: :arm64
  depends_on macos: :sonoma

  app "Hash Fleet.app"
end
