# Teams na Echo

Transmissor local em Swift/AppKit para mostrar **a lista de chats do Microsoft Teams ampliada**, com seus indicadores originais de mensagens não lidas, no navegador da Echo Show. Sem assinatura, conta no serviço, marca d'água ou limites artificiais de duração e clientes. A imagem não usa serviços de nuvem. O código e o aplicativo ficam sob controle do usuário.

A captura usa ScreenCaptureKit. A versão 1.3.0 recorta a coluna de chats na resolução de origem, antes de reduzir e codificar JPEG. Os checkboxes **Exibir em duas colunas** e **Girar imagem 90° para a direita** são independentes, ficam salvos e atualizam a imagem imediatamente. A configuração inicial mantém uma coluna com rotação. Com a rotação ligada, coloque a Echo de lado, girada para a esquerda. Isso amplia nomes, negritos e indicadores sem transmitir a conversa selecionada. O Mac continua responsável pelo áudio e pelo controle do Teams. A saída tem até 1280 × 800 e 5 atualizações por segundo. A compatibilidade final deve ser verificada na Echo física.

No painel do Mac, **Esquerda**, **Topo** e **Largura** ajustam o recorte em pontos da janela. Os valores iniciais foram medidos na coluna de chats deste Mac. Use **Aplicar recorte** caso altere o tamanho da barra lateral; os ajustes ficam salvos. A opção **Exibir em duas colunas** divide a lista antes da rotação, com sobreposição de uma linha na continuação para evitar cortes. Você pode ativar ou desativar cada checkbox sem recompilar. O aplicativo não abre chats nem marca mensagens como lidas. É necessário manter a lista de chats visível no Teams; o recorte acompanha o que estiver nessa área.

## Uso

1. Compile com `./build.sh` e copie `build/Teams Echo.app` para `~/Applications`.
2. Abra a cópia instalada e conceda Gravação de Tela ao **Teams Echo**.
3. Encerre e reabra o aplicativo para aplicar a permissão.
4. Deixe o Teams aberto, sem minimizar, e use **Iniciar**.
5. Abra o endereço exibido no navegador Silk da Echo, na mesma rede local.

O endereço contém uma chave aleatória privada, salva nas preferências locais. Compartilhe esse endereço apenas com os dispositivos desejados: quem tem o link e acesso à rede pode ver a imagem. Nenhuma imagem é salva em disco; o último quadro de origem e a imagem recortada ficam apenas em memória. **Parar** ou **Sair** encerra o servidor e limpa o quadro. Uma janela sem mudanças mantém a última imagem, sem expiração por tempo.

O aplicativo escolhe a maior janela padrão do Teams encontrada por ScreenCaptureKit; a rede recebe apenas a área recortada. Ele não captura o monitor inteiro ou outros aplicativos. Não altera mouse, teclado ou Rectangle, e não registra atalhos. O Modo Desenvolvedor pode iniciar este aplicativo pela integração opcional com a Alexa.

Log sem conteúdo das mensagens: `~/Library/Logs/TeamsEcho/teams-echo.log`.

## Verificação local

Antes de autorizar ou capturar telas, execute:

```sh
'build/Teams Echo.app/Contents/MacOS/TeamsEcho' --self-test
```

Esse teste usa uma imagem sintética, abre um servidor HTTP real, confere as quatro combinações de colunas/rotação, JPEG, rejeição de links inválidos, clientes simultâneos e limpeza do quadro. A captura real e a exibição no dispositivo precisam ser validadas separadamente após a permissão.
