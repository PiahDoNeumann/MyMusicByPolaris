# Deploy no Dokploy (só Dockerfile)

Um único `Dockerfile` na raiz do repositório compila o servidor (Rust), baixa o
cliente web (`agersant/polaris-web`) e gera a imagem final. Sem docker-compose.

## 1. Criar a aplicação

No projeto do Dokploy: **Create Service → Application**.

**Provider:** GitHub/Git apontando para este repositório, branch `master`.

**Build Type:** `Dockerfile`

| Campo           | Valor        |
|-----------------|--------------|
| Docker File     | `Dockerfile` |
| Docker Context Path | `.`      |
| Docker Build Stage  | (vazio)  |

Opcional — fixar versão do cliente web em vez de `latest`, em **Build-time Arguments**:

```
POLARIS_WEB_URL=https://github.com/agersant/polaris-web/releases/download/<tag>/web.zip
```

## 2. Volumes (Advanced → Volumes / Mounts)

| Tipo          | Origem (host)            | Destino no container | Obs.                                  |
|---------------|--------------------------|----------------------|---------------------------------------|
| Volume Mount  | `polaris-data`           | `/data`              | config, banco, auth secret, cache     |
| Bind Mount    | `/caminho/das/musicas`   | `/music`             | coleção de músicas, marcar read-only  |

`/data` precisa persistir: sem ele cada deploy perde usuários, playlists e índice.

O container roda como UID 1000. Se o bind mount de músicas não for legível por
esse UID, ajuste as permissões no host.

## 3. Domínio (Domains)

| Campo          | Valor             |
|----------------|-------------------|
| Host           | `musica.seudominio.com` |
| Container Port | `5050`            |
| HTTPS          | ligado (Let's Encrypt) |

## 4. Variáveis de ambiente

Nenhuma obrigatória. `TZ` já vem `America/Sao_Paulo`; sobrescreva se quiser.

## 5. Deploy e primeiro acesso

1. **Deploy**. O primeiro build demora (compilação Rust completa); os seguintes
   reaproveitam o cache do cargo.
2. Abra o domínio. O Polaris mostra o setup inicial: crie o usuário admin e
   adicione o mount dir com source `/music`.
3. A configuração fica em `/data/polaris.toml` e pode ser editada pela UI.

Healthcheck da imagem: `GET /api/version` na porta 5050.

## Teste local

```bash
docker build -t polaris .
```

```bash
docker run --rm -p 5050:5050 -v polaris-data:/data -v /caminho/das/musicas:/music:ro polaris
```

## Músicas no SeaweedFS (S3)

O Polaris não recebe upload de música: só lê `/music`. Os arquivos ficam num
bucket S3 do SeaweedFS, montado no host via FUSE.

```
upload S3 ──► SeaweedFS (bucket music) ──► weed mount ──► /srv/mymusic/music (host) ──► /music (Polaris)
```

No projeto do Dokploy, serviço **Compose** `SeaweedFS` (raw), com o conteúdo de
[`deploy/seaweedfs.compose.yml`](../deploy/seaweedfs.compose.yml):

- `seaweedfs`: master + volume + filer, dados no volume `seaweedfs-data`. Fica só
  na rede interna `storage`: essas portas não têm autenticação.
- `s3`: gateway S3 autenticado, único serviço na `dokploy-network`.
  Domínio `s3-mymusic.patobragado.com.br` → serviço `s3`, porta `8333`.
- `mount`: `weed mount` do bucket `music` em `/srv/mymusic/music` no host
  (propagação `rshared`, precisa de `privileged` e `/dev/fuse`).
- Environment do compose: `S3_ACCESS_KEY` e `S3_SECRET_KEY`.

Na aplicação Polaris: **Bind Mount** `/srv/mymusic/music` → `/music`.

Também na aplicação Polaris, **Swarm Settings → Update Config** com `Order` =
`stop-first`. O banco embutido aceita um processo só; com `start-first` o
container novo morre com `Could not initialize database`.

### Enviar músicas

Qualquer cliente S3 (rclone, Cyberduck, WinSCP, `aws s3`), com:

| Campo      | Valor                                   |
|------------|-----------------------------------------|
| Endpoint   | `https://s3-mymusic.patobragado.com.br` |
| Região     | `us-east-1`                             |
| Bucket     | `music`                                 |
| Path style | ligado                                  |

Organize como pastas `Artista/Álbum/faixa.flac`, com a capa `Folder.jpg` ao lado.

Exemplo com rclone (remote `mymusic` do tipo S3, provider `SeaweedFS`):

```bash
rclone copy "D:/Musicas/Artista" mymusic:music/Artista --progress
```

Depois do upload, dispare o scan da coleção nas configurações da UI do Polaris
(ou `POST /api/trigger_index`). Não há rescan periódico, e o watcher de
arquivos não enxerga mudanças feitas pelo FUSE.

### Cuidados

- Não ponha domínio no serviço `seaweedfs`: o Dokploy o ligaria à
  `dokploy-network` e qualquer app do servidor leria o filer sem senha.
- Se o serviço `SeaweedFS` reiniciar, o mount FUSE é refeito; reinicie a
  aplicação Polaris em seguida para ela enxergar o mount novo.
- `/music` é só leitura na prática: apagar e renomear se faz no bucket.
