# 多项目 Docker Compose

每个项目独立运行，通过 Nginx 按域名转发。项目容器不发布宿主机端口，页面和静态资源统一使用 Basic Auth 鉴权。

部署所需的项目 `.env`、`local/` 素材、证书、私钥及账号哈希统一随 Git 仓库交付，不需要单独上传。仓库包含私钥和个人素材，应使用受控的私有仓库。

| 域名 | 用途 |
| --- | --- |
| `https://choup.app` | 暂停导航页，所有路径返回 404 |
| `https://superlu.choup.app` | Happy Birthday Card，直接访问根路径 `/` |

HTTP 自动跳转 HTTPS，登录框只在 HTTPS 上出现。此前的 `/birthday/` 路径已改为独立子域名。

## 文件布局

所有自定义 Nginx 配置统一放在根目录 `nginx/`：

```text
compose.yaml
nginx/
  conf.d/
    default.conf              # HTTP 跳转、默认站点、内部健康检查
    choup.app.conf             # 主域名 HTTPS 占位，返回 404
    superlu.choup.app.conf     # 生日项目 HTTPS 反向代理
  snippets/
    tls.conf                  # 公共证书和 TLS 配置
    private-site.conf         # 公共鉴权和响应头
  projects/
    birthday.conf             # 生日容器内部静态服务配置
  html/index.html             # 已停用的导航页源码，未挂载到容器
  certs/
    choup.app.pem             # Cloudflare Origin CA 证书（随仓库交付）
    choup.app.key             # 私钥（随私有仓库交付）
.secrets/
  auth/.htpasswd              # bcrypt 账号文件（随私有仓库交付）
  credentials.txt             # 本地初始密码记录（不入 Git，部署不需要）
```

项目 Dockerfile 只构建网页；内部 Nginx 配置由 Compose 从 `nginx/projects/` 只读挂载。证书也以只读方式挂载，不写入镜像。

## 部署到服务器

需要 Docker、Docker Compose、Docker Buildx 和 OpenSSL。用 `docker buildx version` 检查构建组件；macOS Homebrew 用户缺少时可运行 `brew install docker-buildx`。

1. 首次在本机提交部署文件并推送到私有仓库：

   ```sh
   git add .gitignore README.md Happy-Birthday-Card/.gitignore \
     Happy-Birthday-Card/.env Happy-Birthday-Card/local \
     nginx/certs/.gitignore nginx/certs/choup.app.pem nginx/certs/choup.app.key \
     .secrets/auth/.htpasswd
   git commit -m "Include deployment configuration and assets"
   git push
   ```

   然后在服务器已有仓库中执行 `git pull`，或首次执行 `git clone https://github.com/Choupoo/birthday.git`。访问私有仓库需要使用有权限的 GitHub 凭据或 SSH 密钥。项目 `.env` 中的 `PIC` 是 `local/` 内的图片文件名。
2. 在服务器根目录设置监听地址和标准端口：

   ```sh
   cp .env.production.example .env
   chmod 700 nginx/certs .secrets
   chmod 600 nginx/certs/choup.app.key
   chmod 755 .secrets/auth
   chmod 644 .secrets/auth/.htpasswd
   docker compose config --quiet
   docker compose up -d --build --wait
   docker compose exec nginx nginx -t
   ```

   生产配置为 `0.0.0.0:80` 和 `0.0.0.0:443`。服务器这两个端口需要空闲，安全组/防火墙允许入口流量。若已有反向代理占用，需先规划统一入口，不能让两个容器绑定同一端口。
3. 在 Cloudflare 为 `choup.app` 和 `superlu.choup.app` 配置指向服务器公网地址的 DNS 记录，开启代理（橙云）。只配置实际可用的 A/AAAA 记录。
4. Cloudflare SSL/TLS 加密模式设为 **Full (strict)**。这张证书是 Origin CA，适合 Cloudflare 到源站；关闭代理后浏览器直连源站会提示不受信任。不要用 Flexible，它会与源站 HTTPS 跳转形成循环。
5. 打开 `https://superlu.choup.app` 并使用原有账号密码登录。服务器从 `.secrets/auth/.htpasswd` 读取账号哈希，无需明文密码文件。初始密码记录仍在本机 `.secrets/credentials.txt`；后续改过密码时以新密码为准。主域名 `choup.app` 暂时只返回 404。

当前证书覆盖 `choup.app` 和 `*.choup.app`，有效期至 2041-09-25；通配符仅覆盖一级子域名。本次只配置并验证本地容器，未更改 Cloudflare DNS 或部署到远程服务器。

## 本地验证

默认只监听本机 HTTP `8080`、HTTPS `8443`，避免与现有服务的 `443` 冲突。可复制 `.env.example` 为 `.env` 调整端口。

```sh
docker compose up -d --build --wait
docker compose ps

# 应返回 308，跳转到生产 HTTPS 域名。
curl -I -H 'Host: superlu.choup.app' http://127.0.0.1:8080/

# 应返回 401。--resolve 保持正确的 Host/SNI，并连接本机。
curl --noproxy '*' -kI --resolve superlu.choup.app:8443:127.0.0.1 https://superlu.choup.app:8443/

# 提示输入密码，正确后返回 200。
curl --noproxy '*' -kI --user admin --resolve superlu.choup.app:8443:127.0.0.1 https://superlu.choup.app:8443/
```

这里的 `-k` 仅用于本地直连 Origin CA 测试；线上经过 Cloudflare 的访问应正常验证证书。Nginx 按域名匹配，直接访问 `localhost` 或未知域名会被拒绝。HTTP 跳转指向标准生产 HTTPS 端口，本地验证请直接使用上述 `8443` 地址。

## 维护

```sh
docker compose logs -f --tail=100
docker compose restart birthday
docker compose down

# 修改源码或素材后重建。
docker compose up -d --build --wait birthday

# 修改 Nginx 站点、公共配置或替换证书后，检查并重载。
docker compose exec nginx nginx -t
docker compose exec nginx nginx -s reload

# 修改内部静态配置后，检查并重启以重新挂载文件。
docker compose restart birthday
docker compose exec birthday nginx -t
```

修改生日项目 `.env` 后需禁用构建缓存重建，BuildKit 不根据 secret 内容判断缓存是否失效：

```sh
docker compose build --no-cache birthday
docker compose up -d --wait
```

项目 `.env` 已纳入 Git，但仍被 `.dockerignore` 排除出普通构建上下文，只通过 BuildKit secret 挂载供构建使用。姓名、生日等前端使用的值仍会编译进网页，不能放入后端密钥。根目录的 `.env` 只控制当前机器的端口，仍被忽略，可由仓库内 `.env.production.example` 生成。

改密或添加用户（更换命令末尾用户名）：

```sh
htpasswd -B .secrets/auth/.htpasswd admin
```

没有本机 `htpasswd` 时：

```sh
docker run --rm -it --mount "type=bind,source=$PWD/.secrets/auth,target=/auth" httpd:2.4-alpine htpasswd -B /auth/.htpasswd admin
```

不要加 `-c`，以免覆盖账号文件。改密立即生效；`.secrets/credentials.txt` 仅记录初始密码，改密后自行更新或删除。浏览器可能缓存旧凭据，可用无痕窗口重新登录。

账号哈希现在纳入 Git。在本机增改账号后，提交并推送 `.secrets/auth/.htpasswd`，服务器 `git pull` 后生效；若直接在服务器改密，应同步该改动，避免后续拉取冲突。

## 新增项目

1. 给新项目添加适合其技术栈的 Dockerfile，在 `compose.yaml` 添加服务，加入 `projects` 网络，不配置宿主机 `ports`。服务监听容器内 `0.0.0.0`。
2. 复制 `nginx/conf.d/superlu.choup.app.conf`，修改 `server_name`、上游服务名及端口，继续引用公共 TLS/鉴权配置。前端资源和路由基路径使用 `/`。
3. 若项目使用内部 Nginx，将配置放在 `nginx/projects/`，在 Compose 中只读挂载到对应容器。
4. 把新子域名加入 `nginx/conf.d/default.conf` 的 HTTP 跳转 `server_name` 列表。导航页当前停用，直接通过新子域名访问。
5. 在 Cloudflare 添加相应 DNS 代理记录，然后执行 `docker compose up -d --build --wait`、`docker compose exec nginx nginx -t` 和 `docker compose exec nginx nginx -s reload`。需要 WebSocket 的项目另行配置 Upgrade 转发。

参考：[Cloudflare Origin CA](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)、[Nginx Basic Auth](https://nginx.org/en/docs/http/ngx_http_auth_basic_module.html)、[Docker Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/)。
