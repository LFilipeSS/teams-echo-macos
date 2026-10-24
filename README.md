# Teams Echo para macOS

Acompanhe a **lista de chats e os indicadores de mensagens novas do Teams** na sua Echo Show. Um aplicativo nativo no Mac recorta a coluna de chats e transmite a imagem pela rede local. A Echo exibe essa imagem no navegador Silk.

**[Tutorial completo de instalação — Mac, Alexa e botão desenvolvimento](INSTALACAO.md)**

## O que faz

- Amplia a lista de chats, preservando os indicadores visuais do próprio Teams.
- Oferece dois checkboxes independentes: **girar 90°** e **exibir em duas colunas**. Os ajustes ficam salvos.
- Mantém os quadros em memória, com até 5 atualizações por segundo e saída de até 1280 × 800.
- Inclui uma skill privada **Painel de Trabalho** para abrir o endereço no Silk.
- Integra opcionalmente o botão **desenvolvimento** do macOS: oculta o Dock, organiza Chrome/Codex/VS Code em 50%/25%/25% e abre o painel na Echo.
- Não cria atalhos nem integra mouse, teclado, Rectangle ou Logitech.

Não é um monitor estendido. A Echo mostra uma imagem da área visível da lista, sem responder mensagens, controlar o Teams ou marcar conversas como lidas. Mantenha a janela do Teams aberta e a coluna desejada visível. Ajuste o recorte ao seu layout antes de compartilhar a imagem.

## Requisitos e custo

Build atual para **Apple Silicon**, macOS 13 ou posterior, ferramentas Swift com SDK recente, Node.js 22 ou posterior para a automação e uma Echo Show com Silk e suporte a APL OpenURL. O dispositivo usado no desenvolvimento foi uma **Echo Show 8 de segunda geração**; outros modelos precisam de teste. Mac e Echo devem estar na mesma rede local, sem isolamento entre clientes.

O projeto não cobra assinatura nem impõe limite de tempo ou quantidade de visualizadores. A imagem circula na rede local. Login e acionamento da skill usam os serviços da Amazon, sujeitos às [cotas do Alexa-hosted](https://developer.amazon.com/en-GB/docs/alexa/hosted-skills/usage-limits.html). Não há garantia de serviço ilimitado da Amazon.

A skill é criada na conta de cada usuário, em modo de desenvolvimento; não é uma skill pública da loja. A ponte usa as bibliotecas comunitárias [alexa-remote2](https://github.com/Apollon77/alexa-remote) e [alexa-cookie2](https://github.com/Apollon77/alexa-cookie), que dependem de interfaces não oficiais e podem exigir novo login ou ajustes futuros. O projeto é independente da Amazon e da Microsoft.

## Estrutura

| Pasta | Conteúdo |
| --- | --- |
| `teams-echo/` | Aplicativo Swift/AppKit e ScreenCaptureKit |
| `teams-echo/alexa-bridge/` | Login local, seleção da Echo e acionamento da skill |
| `teams-echo/alexa-skill/` | Modelo pt-BR e backend da skill privada |
| `modo-desenvolvedor/` | Aplicativo opcional da barra superior e layout por Accessibility |

## Privacidade

Quem tem o link privado e acesso à mesma rede consegue ver o recorte. Não publique o endereço, capturas de conversas ou a pasta `~/Library/Application Support/TeamsEcho/Alexa/`. Ela guarda a sessão Amazon e os arquivos de configuração. O instalador auxiliar mantém esses arquivos fora do repositório, com permissões restritas ao usuário. O endereço privado é enviado ao backend da sua skill para que ela o abra na Echo; os quadros não passam por esse backend.

O código publicado não inclui credenciais, dispositivos pessoais, configurações privadas ou dependências vendorizadas. Consulte [os testes e seus limites](TESTES.md).

## Licença

[MIT](LICENSE), copyright 2026 LFilipeSS. As dependências conservam suas próprias licenças.
