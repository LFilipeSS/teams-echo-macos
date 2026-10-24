# Skill privada Painel de Trabalho

Siga a [instalação da Alexa](../../INSTALACAO.md#6-criar-a-skill-privada-na-amazon). `pt-BR.json` é o modelo de interação. `lambda/index.js` implementa o backend sem dependências e abre um endereço IPv4 privado no Silk usando APL OpenURL.

A configuração real é gerada fora do repositório por `alexa-bridge/prepare-skill.cjs`, em um ZIP com `lambda/` na raiz. Ele inclui `viewer-config.json`; esse arquivo nunca deve ser publicado. Importar o ZIP não configura o modelo de interação nem habilita APL: faça essas etapas no console.

O backend aceita também `TEAMS_ECHO_VIEWER_URL` como variável de ambiente. A instalação pelo tutorial usa o arquivo privado, sem exigir configuração de ambiente.

Teste sem dispositivo ou credenciais: `node --test skill.test.cjs`.
