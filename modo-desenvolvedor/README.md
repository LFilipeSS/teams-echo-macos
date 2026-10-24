# Modo Desenvolvedor

Aplicativo Swift/AppKit exclusivo da barra de menus. Instalação: `~/Applications/Modo Desenvolvedor.app`. Identidade: `br.com.luizfilipe.modo-desenvolvedor`.

## Instalação

Siga o [roteiro de instalação](INSTALACAO.md), que inclui requisitos, compilação, assinatura, Acessibilidade, início automático, atualização e solução de problemas. O build atual gera uma versão para Macs com Apple Silicon (`arm64`).

Clique no botão **desenvolvimento** na barra superior para ativar diretamente o layout. O clique direito oferece **Sair** e o estado atual. O aplicativo abre Chrome, ChatGPT/Codex e VS Code quando necessário, aguarda janelas padrão utilizáveis, restaura minimização/tela cheia, aplica 50% / 25% / 25% da largura e confere o resultado via Accessibility. Usa a tela mais larga, com área como desempate, e sua área útil, respeitando barra e Dock. A diferença de até 3 pontos aceita limitações de tamanho dos aplicativos.

Antes de abrir ou organizar os aplicativos, habilita a ocultação automática do Dock e aguarda a nova área útil estabilizar. Usa o comando nativo de ocultação do Dock via Acessibilidade, compatível com os títulos de menu em português e inglês. Confirma a preferência e a área útil real antes de iniciar os aplicativos. O Dock volta a aparecer temporariamente quando o ponteiro chega à borda. A ocultação automática permanece habilitada depois da execução.

Não configura mouse, teclado, Rectangle ou Logi Options+. Não registra atalhos de teclado. **Sair** encerra somente este aplicativo; o início no próximo login permanece habilitado.

## Teams na Echo Show (opcional, versão 1.3.0)

Quando a integração Alexa está configurada neste Mac, o mesmo botão também abre o Teams Echo, aguarda uma transmissão válida e aciona a skill privada **Painel de Trabalho** na Echo Show 8. Essa ação acontece depois da verificação do layout. Uma falha de conexão com a Echo mantém o layout aplicado e aparece no log e em um aviso.

`EchoIntegration.swift` coordena a abertura nativa e o botão Iniciar do Teams Echo via AX. O worker `AlexaBridge/open-teams.cjs` acompanha o aplicativo em `Contents/Resources`, usa Node.js e a biblioteca comunitária `alexa-remote2`; o comando `OpenURL` pertence à interface oficial APL. A conexão remota depende da Internet e pode precisar de novo login se a Amazon alterar sua interface. As imagens continuam restritas à rede local.

O build inclui o worker quando encontra `../teams-echo/alexa-bridge/node_modules`, ou o diretório indicado por `ALEXA_BRIDGE_SOURCE`. As instruções e o código da skill ficam no projeto local Teams Echo. Sem configuração Alexa, o aplicativo executa apenas o layout.

Os tokens e a configuração pessoal ficam **fora do repositório**, em `~/Library/Application Support/TeamsEcho/Alexa/`, com acesso restrito ao usuário. Não publique essa pasta. `integration.json` contém `enabled`, o dispositivo, a skill, o endereço do visualizador e o executável Node. `enabled: false` desativa somente a integração. Se o IP local do Mac mudar, é necessário atualizar o endereço na configuração da skill e no arquivo local.

## Início automático e permissão

Usa `SMAppService.mainApp`, associado ao bundle instalado. Pode ser desabilitado nos Itens de Início dos Ajustes do Sistema. `LSUIElement` e política `.accessory` impedem a presença no Dock.

A assinatura é local (ad hoc), sem certificado Apple Developer. A versão final deve ser autorizada em Privacidade e Segurança → Acessibilidade. Não substituir o binário após autorizar: uma atualização altera sua identidade criptográfica e pode exigir nova autorização. O script de build recusa recompilação após instalar, exceto com a opção explícita `--allow-rebuild`.

## Diagnóstico

Log legível: `~/Library/Logs/ModoDesenvolvedor/modo-desenvolvedor.log` (rotacionado aos 2 MB). Último resultado: `ultima-execucao.json`, na mesma pasta. Evidências locais podem ser guardadas em `validation/`, que é ignorado pelo Git.

Comandos somente de diagnóstico do mesmo binário: `--diagnose`, `--inspect` e `--verify`. O último retorna código 0 somente quando as três posições, alturas e proporções conferem. Executado pelo terminal, pode herdar a autorização do aplicativo responsável; por isso a validação inclui o resultado gerado pela própria instância da barra, iniciada pelo Launch Services.

`Tests/ButtonProbe.swift` opera o botão real da barra com `AXPress`, sem chamar o método de layout diretamente. `Tests/IndependentVerifier.swift` mede janelas novamente por uma implementação independente, confere o botão dentro da tela e a ausência do aplicativo no Dock. Os auxiliares de interface exigem Acessibilidade do processo responsável e devem ser usados após salvar seu trabalho.

## Fontes e testes de geometria

`Geometry.swift` converte AppKit (origem inferior esquerda da tela primária) para AX (origem superior esquerda da tela primária). `DeveloperMode.swift` contém o engine, menu, registro de login e diagnósticos. `EchoIntegration.swift` coordena a integração opcional. `Info.plist` define o bundle.

```sh
swiftc -parse-as-library Geometry.swift Tests/GeometryTests.swift -o /tmp/modo-geometry-tests
/tmp/modo-geometry-tests
```

As APIs de referência são [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp) e [NSScreen.visibleFrame](https://developer.apple.com/documentation/appkit/nsscreen/visibleframe).
