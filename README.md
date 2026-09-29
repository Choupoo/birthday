# 多项目 Docker Compose

每个项目独立运行，通过 Nginx 按域名转发。项目容器不发布宿主机端口，页面和静态资源统一使用 Basic Auth 鉴权。

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
    choup.app.pem             # Cloudflare Origin CA 证书（不入 Git）
    choup.app.key             # 私钥（不入 Git）
.secrets/
  auth/.htpasswd              # bcrypt 账号文件（不入 Git）
  credentials.txt             # 初始账号密码（不入 Git、不挂载容器）
```

项目 Dockerfile 只构建网页；内部 Nginx 配置由 Compose 从 `nginx/projects/` 只读挂载。证书也以只读方式挂载，不写入镜像。

## 部署到服务器

需要 Docker、Docker Compose、Docker Buildx 和 OpenSSL。用 `docker buildx version` 检查构建组件；macOS Homebrew 用户缺少时可运行 `brew install docker-buildx`。

1. 上传整个目录，并确认以下不入 Git 的文件已安全传到服务器：
   - `Happy-Birthday-Card/.env` 和 `Happy-Birthday-Card/local/` 素材；`PIC` 是 `local/` 内的图片文件名。
   - `nginx/certs/choup.app.pem` 和 `nginx/certs/choup.app.key`。PEM 首尾行不要保留聊天粘贴时的前导反斜杠。
   - `.secrets/auth/.htpasswd`，用于沿用当前账号；如果不复制，在服务器执行 `sh scripts/init-auth.sh admin` 生成新账号。已有账号时不用再次初始化。
2. 在服务器根目录设置监听地址和标准端口：

   ```sh
   cp .env.production.example .env
   chmod 700 nginx/certs
   chmod 600 nginx/certs/choup.app.key
   docker compose config --quiet
   docker compose up -d --build --wait
   docker compose exec nginx nginx -t
   ```

   生产配置为 `0.0.0.0:80` 和 `0.0.0.0:443`。服务器这两个端口需要空闲，安全组/防火墙允许入口流量。若已有反向代理占用，需先规划统一入口，不能让两个容器绑定同一端口。
3. 在 Cloudflare 为 `choup.app` 和 `superlu.choup.app` 配置指向服务器公网地址的 DNS 记录，开启代理（橙云）。只配置实际可用的 A/AAAA 记录。
4. Cloudflare SSL/TLS 加密模式设为 **Full (strict)**。这张证书是 Origin CA，适合 Cloudflare 到源站；关闭代理后浏览器直连源站会提示不受信任。不要用 Flexible，它会与源站 HTTPS 跳转形成循环。
5. 打开 `https://superlu.choup.app` 并登录。当前账号在本地 `.secrets/credentials.txt`；初始化脚本生成随机密码，不会覆盖已有账号。主域名 `choup.app` 暂时只返回 404。

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

项目 `.env` 仅作为构建 secret 挂载。姓名、生日等前端使用的值仍会编译进网页，不能放入后端密钥。

改密或添加用户（更换命令末尾用户名）：

```sh
htpasswd -B .secrets/auth/.htpasswd admin
```

没有本机 `htpasswd` 时：

```sh
docker run --rm -it --mount "type=bind,source=$PWD/.secrets/auth,target=/auth" httpd:2.4-alpine htpasswd -B /auth/.htpasswd admin
```

不要加 `-c`，以免覆盖账号文件。改密立即生效；`.secrets/credentials.txt` 仅记录初始密码，改密后自行更新或删除。浏览器可能缓存旧凭据，可用无痕窗口重新登录。

## 新增项目

1. 给新项目添加适合其技术栈的 Dockerfile，在 `compose.yaml` 添加服务，加入 `projects` 网络，不配置宿主机 `ports`。服务监听容器内 `0.0.0.0`。
2. 复制 `nginx/conf.d/superlu.choup.app.conf`，修改 `server_name`、上游服务名及端口，继续引用公共 TLS/鉴权配置。前端资源和路由基路径使用 `/`。
3. 若项目使用内部 Nginx，将配置放在 `nginx/projects/`，在 Compose 中只读挂载到对应容器。
4. 把新子域名加入 `nginx/conf.d/default.conf` 的 HTTP 跳转 `server_name` 列表。导航页当前停用，直接通过新子域名访问。
5. 在 Cloudflare 添加相应 DNS 代理记录，然后执行 `docker compose up -d --build --wait`、`docker compose exec nginx nginx -t` 和 `docker compose exec nginx nginx -s reload`。需要 WebSocket 的项目另行配置 Upgrade 转发。

参考：[Cloudflare Origin CA](https://developers.cloudflare.com/ssl/origin-configuration/origin-ca/)、[Nginx Basic Auth](https://nginx.org/en/docs/http/ngx_http_auth_basic_module.html)、[Docker Compose secrets](https://docs.docker.com/compose/how-tos/use-secrets/)。
