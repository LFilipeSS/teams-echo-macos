# Ponte Alexa local

Veja o [tutorial completo](../../INSTALACAO.md) antes de executar. Esta ponte usa interfaces comunitárias da Amazon; a transmissão local também funciona sem ela, abrindo o link manualmente no Silk.

```sh
npm ci --ignore-scripts --registry=https://registry.npmjs.org
node bridge.cjs login
node bridge.cjs devices
node configure.cjs
node prepare-skill.cjs
node open-teams.cjs --check
node open-teams.cjs
```

O login abre um proxy somente em `http://localhost:3133/`; a autenticação é feita pelo próprio usuário. `configure.cjs` pede os identificadores e grava a configuração privada fora do projeto. `prepare-skill.cjs` cria o ZIP privado para importar na Alexa. Não publique esse ZIP.

Sessão, registro e integração ficam em `~/Library/Application Support/TeamsEcho/Alexa/`, pasta 0700 e arquivos 0600. A sessão contém credenciais renováveis: não a compartilhe. O worker confere o endereço e espera um quadro válido antes de acionar a skill. Uma resposta de comando aceito pela Amazon não comprova que a imagem apareceu na Echo: confira o dispositivo.

Testes sem conta real: `node --test bridge.test.cjs setup.test.cjs`.
