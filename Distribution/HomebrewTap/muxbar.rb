cask "muxbar" do
  version "0.1.0"
  sha256 "TBD_AFTER_BUILD"

  url "https://github.com/1989v/muxbar/releases/download/v#{version}/muxbar-#{version}.dmg"
  name "muxbar"
  desc "tmux session manager with caffeinate toggle in the menu bar"
  homepage "https://github.com/1989v/muxbar"

  depends_on formula: "tmux"
  depends_on macos: ">= :ventura"

  app "muxbar.app"

  postflight do
    system_command "xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/muxbar.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/muxbar",
    "~/Library/Preferences/com.1989v.muxbar.plist",
  ]
end
