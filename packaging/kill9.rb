# Template for masb3/homebrew-tap (Formula/kill9.rb); the Build workflow fills in @VERSION@ and @SHA256@ on each release.
# Kill9 is compiled on the user's Mac, so the app isn't quarantined and opens without a Gatekeeper prompt.
class Kill9 < Formula
  desc "Menu-bar app that shows what's listening on every port and stops it"
  homepage "https://masb3.github.io/kill9/"
  url "https://github.com/masb3/kill9/archive/refs/tags/v@VERSION@.tar.gz"
  sha256 "@SHA256@"

  depends_on macos: :ventura

  def install
    ENV["ARCHS"] = Hardware::CPU.arch.to_s
    ENV["SWIFT_BUILD_FLAGS"] = "--disable-sandbox"
    system "./build-app.sh"
    prefix.install "build/Kill9.app"
    (bin/"kill9").write <<~SH
      #!/bin/bash
      exec open "#{opt_prefix}/Kill9.app"
    SH
  end

  def caveats
    <<~EOS
      Start Kill9 with:
        kill9
      To also find it in Spotlight and Applications:
        ln -sf #{opt_prefix}/Kill9.app /Applications/Kill9.app
    EOS
  end

  test do
    assert_predicate prefix/"Kill9.app/Contents/MacOS/Kill9", :executable?
  end
end
