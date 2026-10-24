#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
if [[ -e "$HOME/Applications/Modo Desenvolvedor.app" && "${1:-}" != "--allow-rebuild" ]]; then
  print -u2 'Aplicativo já instalado. Não recompilar após conceder Acessibilidade. Use --allow-rebuild apenas para uma atualização deliberada.'
  exit 1
fi
mkdir -p build/'Modo Desenvolvedor.app'/Contents/MacOS
swiftc -O -parse-as-library -target arm64-apple-macosx13.0 Geometry.swift DeveloperMode.swift EchoIntegration.swift -o build/'Modo Desenvolvedor.app'/Contents/MacOS/ModoDesenvolvedor -framework AppKit -framework ApplicationServices -framework ServiceManagement
cp Info.plist build/'Modo Desenvolvedor.app'/Contents/Info.plist
bridge_source="${ALEXA_BRIDGE_SOURCE:-../teams-echo/alexa-bridge}"
bridge_target='build/Modo Desenvolvedor.app/Contents/Resources/AlexaBridge'
if [[ -d "$bridge_target" ]]; then rm -rf "$bridge_target"; fi
if [[ -d "$bridge_source/node_modules" ]]; then
  mkdir -p "$bridge_target"
  for source_file in bridge.cjs session.cjs local-proxy.cjs open-teams.cjs package.json package-lock.json; do
    cp "$bridge_source/$source_file" "$bridge_target/"
  done
  ditto "$bridge_source/node_modules" "$bridge_target/node_modules"
fi
codesign --force --sign - --identifier br.com.luizfilipe.modo-desenvolvedor build/'Modo Desenvolvedor.app'
codesign --verify --deep --strict --verbose=2 build/'Modo Desenvolvedor.app'
