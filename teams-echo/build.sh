#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ -e "$HOME/Applications/Teams Echo.app" && "${1:-}" != "--allow-rebuild" ]]; then
  print -u2 'Aplicativo já instalado. Não recompile após conceder Gravação de Tela.'
  exit 1
fi
mkdir -p 'build/Teams Echo.app/Contents/MacOS'
swiftc -O -parse-as-library -target arm64-apple-macosx13.0 TeamsEcho.swift ChatListRenderer.swift Tests/SelfTests.swift -o 'build/Teams Echo.app/Contents/MacOS/TeamsEcho' -framework AppKit -framework ScreenCaptureKit -framework Network -framework CoreImage -framework ImageIO -framework UniformTypeIdentifiers
cp Info.plist 'build/Teams Echo.app/Contents/Info.plist'
codesign --force --sign - --identifier br.com.luizfilipe.teams-echo 'build/Teams Echo.app'
codesign --verify --deep --strict 'build/Teams Echo.app'
