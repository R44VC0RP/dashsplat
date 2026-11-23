# System packages for dashsplat on Apple Silicon, for a fresh Mac: brew bundle install --no-upgrade
# pipeline/run/setup-mac.sh installs only the ones it cannot already find on PATH, so existing ffmpeg, uv or Bun
# installs from other sources are left alone. The Xcode command-line tools (swiftc, clang) come from Apple.
brew "ceres-solver"   # rig_ba and trajectory_ba bundle adjusters (pulls in eigen, suitesparse)
brew "eigen"
brew "cmake"
brew "ninja"          # also avoids make's failure when the active Xcode path contains a space
brew "ffmpeg"
brew "uv"             # Python 3.12 environments
tap "oven-sh/bun"
brew "oven-sh/bun/bun"
