# Backend para outros sites

Este servico ainda precisa ser hospedado: publicar o codigo no GitHub nao o
coloca em execucao. O servidor original continua atendendo apenas YouTube.

Instale Python 3.10+, FFmpeg com encoder DFPWM e yt-dlp:

```sh
python -m pip install -U yt-dlp
export MUSIC_TOKEN="substitua-por-um-segredo-longo-aleatorio"
export MUSIC_ALLOWED_HOSTS="www.youtube.com,youtu.be,vimeo.com,www.twitch.tv"
python backend/server.py
```

No PowerShell, use `$env:MUSIC_TOKEN="..."` e `$env:MUSIC_ALLOWED_HOSTS="..."`.
Adicione explicitamente o hostname de cada site desejado a MUSIC_ALLOWED_HOSTS.

O servico escuta em 0.0.0.0 e usa a porta da variavel `PORT` (10000 por padrao).
O endpoint publico `/health` pode ser usado pela hospedagem para verificar o
processo. Publique-o atras de HTTPS com autenticacao preservada, limites de
requisicoes e timeout de conversao.
Execute em container/host isolado, sem credenciais de nuvem, bloqueando saidas
para redes privadas e endpoints de metadata: extratores podem seguir redirects
e requisitar outros hosts. Nao abra este conversor como proxy publico.

No terminal Lua do ComputerCraft, configure:

```lua
settings.set("music.media_backend", "https://SEU-SERVIDOR")
settings.set("music.media_token", "SEU-SEGREDO")
settings.save()
```

Reabra music e cole o link na busca. O cliente envia o token apenas para esse
backend. A primeira reproducao espera o download e a conversao; o servico limita
concorrencia a 2 conversoes, videos a 30 minutos e downloads a 100 MB quando o
tamanho e conhecido pelo extrator. Ajuste os limites HTTP do CC se necessario.

Sites suportados dependem da versao do yt-dlp. Conteudo privado, com DRM,
restricoes regionais ou exigencia de login pode falhar. Nao ha suporte universal.
Spotify continua sendo uma busca por metadados, nao extracao do audio Spotify.
