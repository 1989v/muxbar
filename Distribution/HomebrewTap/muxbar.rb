cask "muxbar" do
  version "0.3.0"
  sha256 "4df80b6c1811116961a9d5ad5318f217dcf970ca8c3955c3f528a9b4204c6da2"

  url "https://github.com/1989v/muxbar/releases/download/v#{version}/muxbar-#{version}.dmg"
  name "muxbar"
  desc "tmux session manager + closed-lid mode in the menu bar"
  homepage "https://github.com/1989v/muxbar"

  depends_on formula: "tmux"
  depends_on macos: ">= :ventura"
  depends_on arch: :arm64

  app "muxbar.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/muxbar.app"],
                   sudo: false
  end

  zap trash: [
    "~/Library/Application Support/muxbar",
    "~/Library/Preferences/com.1989v.muxbar.plist",
  ]
end
