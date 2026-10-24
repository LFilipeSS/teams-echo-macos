# Testes e limites de validação

Os testes automatizados podem ser executados sem uma conta Amazon real. Rode a partir da raiz do projeto:

```sh
npm ci --prefix teams-echo/alexa-bridge --ignore-scripts --registry=https://registry.npmjs.org
node --test teams-echo/alexa-bridge/bridge.test.cjs teams-echo/alexa-bridge/setup.test.cjs teams-echo/alexa-skill/skill.test.cjs
./teams-echo/build.sh
'./teams-echo/build/Teams Echo.app/Contents/MacOS/TeamsEcho' --self-test
swiftc -parse-as-library modo-desenvolvedor/Geometry.swift modo-desenvolvedor/Tests/GeometryTests.swift -o /tmp/teams-echo-geometry-tests
/tmp/teams-echo-geometry-tests
```

Se já instalou os aplicativos, não recompile por rotina: use o binário de teste já construído. O build recusa recompilação sem `--allow-rebuild`, reservado a atualizações deliberadas.

## Cobertura

- Renderização: quatro combinações de uma/duas colunas e rotação; ordem das áreas e exclusão da área sintética de conversa.
- Servidor HTTP real: JPEG, clientes simultâneos, link inválido e limpeza ao parar.
- Ponte: arquivo privado atômico, ausência de sessão e proxy local sem downgrade do HTTPS da Amazon.
- Instalação: configuração com dados fictícios, rejeição de destino externo e ZIP com `lambda/` na raiz e arquivos privados restritos.
- Skill: endereço local validado, APL OpenURL, disponibilidade, dispositivo sem APL e encerramento.
- Geometria: conversão entre AppKit e Accessibility e cálculo do layout.

## Testes com dados reais

A captura real exige Gravação de Tela e uma janela Teams. A exibição na Echo exige rede, login, skill implantada e conferência física. Não há credenciais nem imagens privadas no repositório. O backend aceitar um comando não prova que a tela abriu.

Durante o desenvolvimento, a abertura da imagem pela skill foi confirmada em uma Echo Show 8 de segunda geração. Recorte, rotação e duas colunas passaram por testes locais. As combinações finais precisam ser verificadas em cada dispositivo após a autorização da cópia final instalada.

Para o Modo Desenvolvedor, `Tests/ButtonProbe.swift` aciona o botão real via AX e `Tests/IndependentVerifier.swift` mede novamente as janelas. Esses auxiliares exigem autorização de Acessibilidade do processo responsável. Os testes de interface podem abrir e reorganizar aplicativos; revise-os e salve seu trabalho antes de executá-los.

O roteiro de conferência manual está na [instalação](INSTALACAO.md#11-conferência-final). Não inclua capturas dos seus chats em relatórios públicos.
