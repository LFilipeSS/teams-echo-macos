# Instalação passo a passo

Este guia instala o **Teams Echo**, cria sua skill privada **Painel de Trabalho** e, opcionalmente, conecta tudo ao botão **desenvolvimento** da barra do Mac. Faça primeiro a imagem funcionar no Silk e depois configure a abertura automática.

## 1. Preparar o Mac

Você precisa de:

- Mac com Apple Silicon (M1 ou posterior), macOS 13 ou posterior. O build publicado gera somente `arm64`; Intel não foi validado.
- Microsoft Teams instalado, conectado e com a lista de chats visível.
- Echo Show com Silk e suporte a APL OpenURL. O modelo usado no projeto foi a Echo Show 8 de segunda geração, configurada em português do Brasil.
- Mac e Echo na mesma rede local. Redes de convidados e isolamento entre dispositivos podem impedir o acesso.
- Conta Amazon usada na Echo e acesso ao [Alexa Developer Console](https://developer.amazon.com/alexa/console/ask).
- Node.js 22 ou posterior, instalado pelo [site oficial](https://nodejs.org/en/download). O Node é necessário somente para a automação Alexa.
- Ferramentas de desenvolvimento da Apple com Swift e SDK macOS que inclua as APIs de captura do macOS 14.2. O sistema de destino continua sendo macOS 13. Se as ferramentas antigas não compilarem, atualize as Command Line Tools ou instale uma versão compatível do Xcode.

Abra o Terminal e confira:

```sh
xcode-select -p
swift --version
node --version
npm --version
```

Se as ferramentas Apple não estiverem instaladas:

```sh
xcode-select --install
```

Conclua a instalação na janela do macOS antes de continuar. Se houver termos da Apple ou da Amazon, leia e aceite pessoalmente caso concorde.

No GitHub, use **Code → Download ZIP**, extraia e abra a pasta `teams-echo-macos-main`. No Terminal, digite `cd `, arraste essa pasta para a janela e pressione Enter. Todos os comandos abaixo começam na **raiz dessa pasta**, onde está este tutorial. Não entre em subpastas entre uma etapa e outra.

```sh
chmod +x teams-echo/build.sh modo-desenvolvedor/build.sh
```

## 2. Compilar e instalar o Teams Echo

Compile a versão final e execute os testes sintéticos antes de conceder qualquer permissão:

```sh
./teams-echo/build.sh
'./teams-echo/build/Teams Echo.app/Contents/MacOS/TeamsEcho' --self-test
```

O teste deve encerrar com código zero e relatar aprovação. Ele não captura conversas reais.

Instale e confira a assinatura local:

```sh
mkdir -p "$HOME/Applications"
ditto 'teams-echo/build/Teams Echo.app' "$HOME/Applications/Teams Echo.app"
codesign --verify --deep --strict "$HOME/Applications/Teams Echo.app"
open "$HOME/Applications/Teams Echo.app"
```

A assinatura é **ad hoc**, gerada no próprio Mac. Não é uma distribuição notarizada pela Apple. O projeto é instalado a partir do código; não exige certificado pago Apple Developer.

**A partir daqui, não recompile nem substitua o aplicativo antes de concluir as permissões e os testes.** Se já houver uma instalação, veja a seção de atualização antes de substituir arquivos.

## 3. Autorizar a captura de tela

1. No painel do Teams Echo, clique em **Autorizar captura**, se necessário.
2. Abra **Ajustes do Sistema → Privacidade e Segurança → Gravação de Tela**. Em versões recentes, o nome pode ser **Gravação de Tela e Áudio do Sistema**.
3. Habilite **Teams Echo**. Autorize a cópia que está em `~/Applications/Teams Echo.app`.
4. Encerre pelo item **Sair** do ícone **Teams → Echo** na barra superior.
5. Reabra a cópia instalada com o comando `open` da etapa anterior.
6. Mantenha a janela do Teams aberta, sem minimizar, com a coluna de chats à mostra. Clique em **Iniciar**.

O painel deve mostrar o endereço da transmissão. O Teams Echo captura a janela do Teams e transmite somente o recorte escolhido. Áudio, microfone e câmera não fazem parte da transmissão.

## 4. Conferir a imagem na Echo antes de automatizar

1. No Mac, clique em **Copiar endereço** no Teams Echo.
2. Na Echo, diga **“Alexa, abrir Silk”**.
3. Digite no navegador da Echo o endereço completo mostrado no Mac, incluindo a sequência final e a barra. O formato é `http://IP_DO_MAC:3132/CHAVE_PRIVADA/`.
4. Confira se a imagem aparece e se os indicadores dos chats estão visíveis. Se não aparecer, resolva a conexão antes de criar a skill.

O link contém uma chave privada. Quem tem o link e acesso à rede local pode ver o recorte. Não abra portas no roteador nem publique esse endereço.

No painel do Mac:

- **Esquerda**, **Topo** e **Largura** medem o recorte em pontos, a partir do canto superior esquerdo da janela do Teams. Ajuste para incluir apenas a lista desejada e clique em **Aplicar recorte**.
- **Girar imagem 90° para a direita** gira a imagem. Para vê-la na orientação correta, coloque a Echo de lado, girada para a esquerda.
- **Exibir em duas colunas** divide a lista em duas partes, com uma pequena sobreposição na continuação. Funciona com a rotação ligada ou desligada.

Os dois checkboxes são independentes, atualizam a imagem imediatamente e ficam salvos. Acompanhe nomes em negrito, pontos e outros indicadores do próprio Teams. O programa não interpreta mensagens nem procura chats que estejam fora da área visível. Se mudar a largura da barra lateral ou o layout do Teams, ajuste o recorte novamente.

## 5. Instalar a ponte e conectar sua conta Amazon

Ainda na raiz do projeto:

```sh
npm ci --prefix teams-echo/alexa-bridge --ignore-scripts --registry=https://registry.npmjs.org
node teams-echo/alexa-bridge/bridge.cjs login
```

Quando aparecer `WAITING_FOR_AMAZON_LOGIN_AT_HTTP_LOCALHOST_3133`, abra **exatamente**:

```text
http://localhost:3133/
```

Use `localhost`, sem trocar por um IP e sem mudar para HTTPS. Esse é um proxy local; a conexão com os servidores Amazon continua usando HTTPS. Digite pessoalmente sua senha e o código de verificação na página Amazon. Não coloque sua senha no Terminal ou em arquivos do projeto. Aguarde o comando concluir e retornar ao prompt.

Liste seus dispositivos:

```sh
node teams-echo/alexa-bridge/bridge.cjs devices
```

Anote o **serial** e o **nome** da Echo Show que deve receber o painel. Não publique essa lista.

A conexão fornecida é configurada para a região Amazon Brasil (`amazon.com.br` / `alexa.amazon.com.br`). Outras regiões exigem adaptação e não foram validadas. A sessão renovável é salva no seu usuário, fora do repositório; ela permite controlar a Alexa e deve ser tratada como uma credencial.

## 6. Criar a skill privada na Amazon

Entre no [Alexa Developer Console](https://developer.amazon.com/alexa/console/ask) com a **mesma conta Amazon registrada na Echo**. Se ainda não tiver uma conta de desenvolvedor, conclua seu cadastro pessoalmente.

1. Clique em **Create Skill**.
2. Nome: **Painel de Trabalho**.
3. Idioma principal: **Portuguese (BR)** / português do Brasil.
4. Experiência: **Other**, modelo **Custom**.
5. Hospedagem: **Alexa-hosted (Node.js)**. A instalação original usou **US East (N. Virginia)**.
6. Escolha **Start from Scratch** e conclua a criação.
7. Na aba **Build → Interfaces**, habilite **Alexa Presentation Language (APL)** e salve.
8. Abra **Interaction Model → JSON Editor**.
9. No Mac, abra `teams-echo/alexa-skill/pt-BR.json` em um editor de texto. Copie todo o conteúdo para o JSON Editor, substituindo o modelo inicial.
10. Clique em **Save Model** e depois **Build Model** / **Build Skill**, conforme a interface. Espere o build terminar sem erros.
11. Copie o **Skill ID** completo. Ele começa com `amzn1.ask.skill.` e aparece na página da skill ou no endereço do console. Copie somente o ID, sem o restante da URL.

O nome de invocação configurado no JSON é **painel de trabalho**. O ZIP da etapa seguinte contém o backend; ele não configura automaticamente o idioma, o modelo de interação ou APL. Referência: [criação e importação de código Alexa-hosted](https://developer.amazon.com/en-US/docs/alexa/hosted-skills/alexa-hosted-skills-create.html).

## 7. Salvar sua configuração e gerar o ZIP da skill

No Mac, copie novamente o endereço do Teams Echo e execute:

```sh
node teams-echo/alexa-bridge/configure.cjs
```

Responda às quatro perguntas: endereço completo, serial da Echo, nome da Echo e Skill ID. O auxiliar valida o formato e salva também o caminho do Node usado neste momento. Se uma configuração já existir, ele pede `SIM` antes de substituí-la.

Gere o pacote privado:

```sh
node teams-echo/alexa-bridge/prepare-skill.cjs
open "$HOME/Library/Application Support/TeamsEcho/Alexa"
```

Nessa pasta estará **painel-de-trabalho-private.zip**. O ZIP contém `lambda/index.js`, `lambda/package.json` e `lambda/viewer-config.json`, com o seu endereço. **Não envie esse ZIP ao GitHub.** Ele é destinado somente à sua skill na conta Amazon.

## 8. Importar e ativar a skill

1. No console da skill, abra **Code**.
2. Use **Import Code** e selecione `painel-de-trabalho-private.zip`.
3. Revise os arquivos e confirme a substituição dos arquivos de exemplo da sua skill. Se a Amazon apresentar um acordo, leia e aceite pessoalmente caso concorde.
4. O projeto deve conter a pasta `lambda` e os três arquivos mencionados acima. O handler é `index.handler`; não é necessário instalar bibliotecas no backend.
5. Clique em **Save**, se disponível, e em **Deploy**. Espere a implantação terminar; salvar sozinho não implanta o código.
6. Abra **Test** e altere **Skill testing is enabled in** de **Off** para **Development**.
7. Na Echo, diga **“Alexa, abrir painel de trabalho”**. O Silk deve abrir a imagem do Mac.

A Echo precisa estar na mesma conta da skill e em um idioma compatível. A skill permanece privada em desenvolvimento; não precisa passar por certificação ou publicação na loja. Referência: [testar uma custom skill em dispositivo](https://developer.amazon.com/en-US/docs/alexa/custom-skills/test-and-debug-a-custom-skill.html).

A abertura usa o comando oficial [APL OpenURL](https://developer.amazon.com/en-US/docs/alexa/alexa-presentation-language/apl-open-url-command.html). O dispositivo precisa permitir esse comando (`environment.allowOpenURL`). Uma resposta do servidor não substitui a conferência da tela física.

## 9. Testar a automação pelo Mac

Com o Teams Echo transmitindo:

```sh
node teams-echo/alexa-bridge/open-teams.cjs --check
```

O resultado esperado contém `TEAMS_STREAM_READY`. Depois execute o acionamento real:

```sh
node teams-echo/alexa-bridge/open-teams.cjs
```

Confira na Echo se o Silk abriu o painel e se a imagem corresponde à lista atual. `ALEXA_OPEN_REQUEST_SENT` confirma o envio aceito pela ponte; não garante, sozinho, que a Echo exibiu a imagem.

Para esta integração, o worker espera o endereço IPv4 da interface `en0`. Se sua rede usar outra interface, a transmissão manual pode funcionar, mas o worker precisa ser adaptado. Se o IP do Mac mudar, repita **configure.cjs → prepare-skill.cjs → importação → Deploy** com o endereço atualizado. Uma reserva DHCP no seu roteador pode manter o endereço estável, se você souber configurá-la.

## 10. Opcional: instalar o botão desenvolvimento

Este aplicativo organiza **Google Chrome**, **ChatGPT/Codex** (`com.openai.codex`) e **Visual Studio Code**. Instale os três antes de testar. A ordem é Chrome 50%, Codex 25% e VS Code 25%, na tela mais larga. Use uma tela com largura suficiente para os tamanhos mínimos dessas janelas; o layout original foi criado para um Samsung Odyssey ultrawide de 49 polegadas.

A instalação das dependências da etapa 5 deve estar concluída **antes** deste build, para que a ponte seja incluída no aplicativo final:

```sh
./modo-desenvolvedor/build.sh
mkdir -p "$HOME/Applications"
ditto 'modo-desenvolvedor/build/Modo Desenvolvedor.app' "$HOME/Applications/Modo Desenvolvedor.app"
codesign --verify --deep --strict "$HOME/Applications/Modo Desenvolvedor.app"
open "$HOME/Applications/Modo Desenvolvedor.app"
```

Agora, sem recompilar:

1. Abra **Ajustes do Sistema → Privacidade e Segurança → Acessibilidade**.
2. Habilite a cópia instalada de **Modo Desenvolvedor**. O Teams Echo usa a permissão separada de captura de tela concedida anteriormente.
3. Encerre o Modo Desenvolvedor pelo clique direito no botão da barra → **Sair** e reabra a cópia instalada.
4. Clique com o botão esquerdo em **desenvolvimento**.

O clique habilita a ocultação automática do Dock antes de abrir os aplicativos, aguarda janelas utilizáveis, organiza e verifica o layout via Accessibility. Em seguida abre o Teams Echo se necessário, espera uma imagem válida e aciona a skill. O Dock continua com ocultação automática habilitada depois da execução. O ponteiro na borda pode fazê-lo reaparecer temporariamente.

O botão fica na barra superior e o aplicativo não aparece no Dock. O início automático é registrado por `SMAppService.mainApp`; confira **Ajustes do Sistema → Geral → Itens de Início** e permita o Modo Desenvolvedor se o macOS solicitar. **Sair** encerra a sessão atual, mas mantém o início no próximo login. O Teams Echo não tem registro de login próprio: pode ser aberto pelo botão quando necessário.

Sem `integration.json` habilitado, o botão executa somente o layout. Para desativar apenas a Alexa, altere `enabled` para `false` nesse arquivo privado. Não há alterações de mouse, teclado ou Rectangle nem atalhos ocultos.

## 11. Conferência final

- Abra o link no Silk e confira o recorte real, sem incluir a conversa por engano.
- Teste cada checkbox e confirme que a imagem muda e os ajustes persistem ao reabrir o painel.
- Acione a skill e depois o comando `open-teams.cjs`; confira a Echo em ambos os casos.
- Se instalou o botão, clique em **desenvolvimento** com os aplicativos abertos e repita com um deles fechado. Salve seu trabalho antes de fechar qualquer aplicativo para esse teste.
- Confirme as três janelas, o Dock oculto e o botão ainda visível na barra.
- Para verificar as medidas via AX, execute o comando abaixo. Ele pode exigir autorização do Terminal responsável e não substitui o teste do botão real:

```sh
"$HOME/Applications/Modo Desenvolvedor.app/Contents/MacOS/ModoDesenvolvedor" --verify
```

Consulte também `~/Library/Logs/ModoDesenvolvedor/ultima-execucao.json`, produzido pela própria instância que executa o layout. O código zero de `--verify` indica medidas aceitas pelo verificador. Nenhum teste de processo aberto comprova sozinho a exibição na Echo.

## 12. Atualizações e permissões antigas

Os scripts impedem recompilar se encontrarem uma cópia instalada. Para uma atualização deliberada, encerre o aplicativo, compile com `--allow-rebuild`, copie a nova versão e confira a assinatura **antes** de autorizar novamente. Guarde uma cópia da versão anterior se quiser poder retornar a ela.

Uma assinatura ad hoc muda após recompilar. É possível o macOS mostrar uma permissão ligada e ainda rejeitar o binário novo. Nesse caso, encerre o aplicativo e redefina **somente** a permissão dele:

```sh
# Apenas para corrigir a captura do Teams Echo após uma atualização:
tccutil reset ScreenCapture br.com.luizfilipe.teams-echo

# Apenas para corrigir Acessibilidade do Modo Desenvolvedor após uma atualização:
tccutil reset Accessibility br.com.luizfilipe.modo-desenvolvedor
```

Execute somente o comando correspondente ao problema, reabra a cópia instalada, conceda a permissão nos Ajustes e encerre/reabra mais uma vez. Não recompile depois. Não é necessário alterar permissões de outros aplicativos, editar o banco TCC ou desativar proteções do macOS.

Se mudar o caminho do Node, execute `configure.cjs` novamente. Se atualizar a ponte, reinstale suas dependências e faça um build final do Modo Desenvolvedor para incluir o worker novo, seguindo a sequência de autorização acima.

## 13. Solução de problemas

| Sintoma | O que conferir |
| --- | --- |
| Captura negada apesar da chave ligada | Cópia instalada e assinatura final; aplique somente a correção de captura da seção 12. |
| Nada aparece no navegador | Teams Echo em **Iniciar**, Teams aberto e não minimizado, endereço completo, mesma rede e porta 3132 disponível. Se o firewall perguntar, permita o aplicativo somente na rede em que pretende usá-lo. |
| Mostra outra área ou fica pequeno | Ajuste Esquerda/Topo/Largura; teste uma coluna, rotação e posição física da Echo. |
| Chats novos não aparecem | Só os indicadores dentro do recorte atual são visíveis. Confira o filtro, a rolagem e a lista aberta no Teams. |
| Login local falha | Use `http://localhost:3133/` enquanto `bridge.cjs login` estiver ativo. A porta não pode estar ocupada por outro processo. Não ignore avisos de certificado do navegador. |
| Sessão Amazon expirou | Execute `bridge.cjs login` novamente com a mesma conta. |
| `VIEWER_ADDRESS_CHANGED` | Copie o endereço atual e refaça configuração, ZIP e Deploy. |
| `TEAMS_STREAM_NOT_READY` | Abra o painel, conceda captura, clique em Iniciar e confira a imagem manualmente. |
| Skill não é encontrada | Mesma conta Amazon da Echo, português BR, nome “painel de trabalho”, build do modelo e Test em Development. |
| Skill abre mas não vai ao Silk | APL habilitado, Deploy concluído, dispositivo com OpenURL permitido. Confira a mensagem na Echo e teste o link manualmente. |
| Botão organiza mas Alexa falha | Leia o aviso e o log; confira Node, sessão, endereço e transmissão. O layout já aplicado é preservado. |
| Não inicia no login | Confira Itens de Início e a cópia instalada; `--refresh-login` do executável do Modo Desenvolvedor atualiza o registro da mesma instalação, se necessário. |

Logs sem conteúdo das conversas:

```text
~/Library/Logs/TeamsEcho/teams-echo.log
~/Library/Logs/ModoDesenvolvedor/modo-desenvolvedor.log
~/Library/Logs/ModoDesenvolvedor/ultima-execucao.json
```

Não publique logs sem revisar endereços e identificadores. Os arquivos privados da Alexa ficam em `~/Library/Application Support/TeamsEcho/Alexa/`, com pasta 0700 e arquivos 0600. Eles não devem entrar em issues, screenshots ou commits.

## 14. Desinstalar

Encerre os dois aplicativos pelos respectivos itens **Sair**. Desative o Modo Desenvolvedor nos Itens de Início e mova somente suas duas cópias de `~/Applications` para o Lixo. Você pode remover a skill privada no console Amazon e revogar a sessão/dispositivo de login correspondente na sua conta Amazon. Apagar a pasta privada local remove as credenciais deste Mac, mas não substitui a revogação na conta.

As preferências do recorte e o Dock com ocultação automática permanecem como configurados. Se quiser, desative a ocultação do Dock manualmente nos Ajustes do Sistema. Nenhuma etapa requer remover ou reconfigurar os seus outros aplicativos.
