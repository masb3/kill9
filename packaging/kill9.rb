# Template for masb3/homebrew-tap; the Build workflow fills in @VERSION@ and @SHA256@ on each release.
cask "kill9" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/masb3/kill9/releases/download/v#{version}/Kill9.dmg"
  name "Kill9"
  desc "Menu-bar app that shows what's listening on every port and stops it"
  homepage "https://masb3.github.io/kill9/"

  depends_on macos: ">= :ventura"

  app "Kill9.app"

  uninstall quit: "dev.kill9.app"

  zap trash: "~/Library/Preferences/dev.kill9.app.plist"
end
