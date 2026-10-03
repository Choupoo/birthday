# DecoTV

使用 [Decohererk/DecoTV 官方镜像](https://github.com/Decohererk/DecoTV)，由根目录 Compose 统一管理，无需克隆嵌套 Git 仓库或在服务器安装 Node.js。官方应用镜像和 Kvrocks 镜像固定到多架构摘要，由 Docker 自动选择 ARM64 或 AMD64。

## 本地运行

在仓库根目录执行：

```sh
docker compose -f compose.yaml -f compose.local.yaml up -d --build --wait
```

打开 <http://localhost:3001>，使用 `DecoTV/config.env` 中的 `USERNAME` 和 `PASSWORD` 登录。密码已随机生成，配置文件按当前仓库的交付方式允许提交到私有 Git 仓库。

`compose.local.yaml` 只给 DecoTV 添加 `127.0.0.1:3001` 端口，数据库不暴露端口。本地直连使用应用自身的登录，不需要浏览器信任 Cloudflare Origin CA，也不需要修改 hosts。修改本地端口可在根目录 `.env` 设置 `DECOTV_LOCAL_PORT`。

## 服务器运行

在服务器仓库根目录执行：

```sh
git pull
cp .env.production.example .env
docker compose up -d --build --wait
docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload
```

服务器启动时不添加 `compose.local.yaml`，应用端口 `3000/3001` 和数据库端口 `6666` 不对外发布。若曾用本地覆盖文件启动，以上命令会移除本地端口映射。

Cloudflare 增加 `video` 的 A 记录指向服务器，开启橙云代理，SSL/TLS 使用 Full (strict)。现有 `*.choup.app` 证书覆盖 `video.choup.app`。服务器需要可用的 80/443 端口。

打开 <https://video.choup.app>：先用原有 Nginx 账号通过浏览器鉴权，再用 `config.env` 中的 DecoTV 管理员登录。两个账号体系独立；应用中的其他用户可在 DecoTV 后台管理，同时仍需要一个 Nginx 账号。

本机也能用 `--resolve video.choup.app:8443:127.0.0.1` 检查相同的 HTTPS 站点配置；源站证书直连需要显式信任或测试时使用 `curl -k`。

## 配置、数据和升级

- `config.env`：管理员用户名/密码及可选环境配置。修改后执行 `docker compose up -d --wait decotv`；本地使用相同的两份 `-f` 参数以保留本地端口。应用会自动识别 HTTP/HTTPS 及域名，无需写死 `SITE_BASE`。
- `decotv-kvrocks-data`：命名卷，保存应用配置、用户、收藏和播放记录。
- `decotv-downloads`：命名卷，保存服务端下载缓存。
- `nginx/conf.d/video.choup.app.conf`：HTTPS、鉴权、WebSocket 和流式响应代理配置。

`docker compose down` 保留数据卷；`docker compose down -v` 会删除数据。Git 只同步配置文件，不同步数据库里的用户、收藏和播放记录。这里创建的是独立的新实例，不会导入、覆盖机器上原有 DecoTV 实例的数据。

镜像已固定版本。升级时先检查官方新镜像的多架构清单，更新根目录 `compose.yaml` 中的摘要，再执行：

```sh
docker compose pull decotv
docker compose up -d --wait decotv
```

单纯 `pull` 不会越过固定摘要升级。本地运行上述命令时也使用 `-f compose.yaml -f compose.local.yaml`。

官方项目默认不提供播放源。部署完成后，需要在 DecoTV 管理后台配置你要使用的资源源；没有资源源时无法验证实际视频播放。
