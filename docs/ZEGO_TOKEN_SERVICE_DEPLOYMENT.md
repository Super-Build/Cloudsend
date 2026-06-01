# ZEGO Token Service Deployment / 宝塔可视化部署方案

最后同步：2026-06-01

本文是 CloudSend 1v1 ZEGO 语音通话 Token 服务的完整部署文档。新域名：

```text
https://1.738489234.com
```

最终接口：

```text
GET  https://1.738489234.com/api/v1/health
POST https://1.738489234.com/api/v1/voice-call/create
```

> 当前文档按本项目私有部署要求写入固定部署值，可直接复制到服务器执行。不要公开仓库、截图或日志。

---

## 1. 架构图

```mermaid
flowchart LR
    PC["PC 客户端"] --> Domain["https://1.738489234.com"]
    Domain --> Nginx["宝塔 Nginx 反向代理"]
    Nginx --> Go["cloudsend-zego-token<br/>127.0.0.1:8787"]
    Go --> Token["生成 ZEGO Token04"]
    PC --> Android["CloudSend 控制链路发送 Android Token"]
    PC --> Zego["ZEGO 房间"]
    Android --> Zego
```

核心规则：

- PC 请求 Token 服务生成本次 1v1 通话的 `roomId`、双端 `userId`、双端 `streamId`、双端 Token。
- PC 使用 `callerToken` 加入 ZEGO 房间。
- PC 通过现有 CloudSend 远控连接把 Android 所需的 `calleeToken` 发给 Android。
- Android 接听后使用 `calleeToken` 加入同一个 ZEGO 房间。
- Token 服务使用 `payload=""` 的官方基础 Token 形态，避免未开通高级权限鉴权时出现 `1002033`。

---

## 2. 删除旧部署

### 2.1 删除旧 systemd 服务

```bash
systemctl stop cloudsend-zego-token 2>/dev/null
systemctl disable cloudsend-zego-token 2>/dev/null
rm -f /etc/systemd/system/cloudsend-zego-token.service
systemctl daemon-reload
systemctl reset-failed
```

### 2.2 删除旧服务目录

```bash
rm -rf /www/wwwroot/cloudsend-zego-token
```

### 2.3 删除旧宝塔站点

宝塔面板操作：

```text
宝塔面板 -> 网站 -> 找到旧域名 738489234.com / 2.2662275.xyz / api.unan.uno -> 删除站点
```

如果命令行里仍有旧 Nginx 配置：

```bash
rm -f /www/server/panel/vhost/nginx/738489234.com.conf
rm -f /www/server/panel/vhost/nginx/2.2662275.xyz.conf
rm -f /www/server/panel/vhost/nginx/api.unan.uno.conf
nginx -t && systemctl reload nginx
```

---

## 3. DNS 准备

新域名：

```text
1.738489234.com
```

域名 DNS 后台添加：

```text
类型：A
主机记录：1
记录值：服务器公网 IP
```

验证解析：

```bash
ping 1.738489234.com
```

解析到服务器公网 IP 后继续。

---

## 4. 宝塔创建新站点

宝塔面板操作：

```text
网站 -> 添加站点
域名：1.738489234.com
PHP版本：纯静态
根目录：/www/wwwroot/1.738489234.com
```

申请 SSL：

```text
网站 -> 1.738489234.com -> SSL -> Let's Encrypt -> 申请证书
强制 HTTPS：开启
```

---

## 5. 创建服务目录

```bash
mkdir -p /www/wwwroot/cloudsend-zego-token
cd /www/wwwroot/cloudsend-zego-token
```

---

## 6. 安装 Go 构建环境

如果执行 `go mod tidy` 或 `go build` 时提示 `Command 'go' not found`，说明服务器尚未安装 Go。

Ubuntu 22.04 可直接执行：

```bash
apt update
apt install -y golang-go
go version
```

能看到 `go version` 后再继续后续步骤。

---

## 7. 创建 `.env`

> 下面是完整结构，四个部署值已同步为当前项目使用值，可直接复制。

```bash
cat > .env <<'EOF'
PORT=8787
ZEGO_APP_ID=726162948
ZEGO_SERVER_SECRET=360a56369441ee640841cb4c82144186
VOICE_TOKEN_TTL_SECONDS=3600
VOICE_API_KEY=PHFfBRiEXVKFvEGD2cJp
EOF

chmod 600 .env
```

字段说明：

| 字段 | 说明 |
|---|---|
| `PORT` | 本机监听端口，固定 `8787` |
| `ZEGO_APP_ID` | `726162948` |
| `ZEGO_SERVER_SECRET` | `360a56369441ee640841cb4c82144186` |
| `VOICE_TOKEN_TTL_SECONDS` | `3600` |
| `VOICE_API_KEY` | PC 请求 Token 服务时使用的 Bearer 鉴权 key；当前项目默认值为 `PHFfBRiEXVKFvEGD2cJp` |

---

## 8. 创建 `go.mod`

```bash
cat > go.mod <<'EOF'
module cloudsend-zego-token

go 1.18

require github.com/ZEGOCLOUD/zego_server_assistant/token/go/src v0.0.0-20231103072415-8c895c31df9d
EOF
```

---

## 9. 创建完整 `main.go`

```bash
cat > main.go <<'EOF'
package main

import (
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/ZEGOCLOUD/zego_server_assistant/token/go/src/token04"
)

type createRequest struct {
	PcPeerId           string `json:"pcPeerId"`
	AndroidPeerId      string `json:"androidPeerId"`
	CloudsendSessionId string `json:"cloudsendSessionId"`
}

type createResponse struct {
	RtcProvider    string `json:"rtcProvider"`
	AppId          uint32 `json:"appId"`
	RoomId         string `json:"roomId"`
	CallerUserId   string `json:"callerUserId"`
	CalleeUserId   string `json:"calleeUserId"`
	CallerStreamId string `json:"callerStreamId"`
	CalleeStreamId string `json:"calleeStreamId"`
	CallerToken    string `json:"callerToken"`
	CalleeToken    string `json:"calleeToken"`
	ExpiresAt      int64  `json:"expiresAt"`
}

type errorResponse struct {
	Error string `json:"error"`
}

func main() {
	port := getenv("PORT", "8787")

	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/api/v1/health", handleHealth)
	http.HandleFunc("/api/v1/voice-call/create", handleCreate)

	addr := "127.0.0.1:" + port
	log.Println("cloudsend zego token service listening on", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusNotFound, errorResponse{"not_found"})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
}

func handleCreate(w http.ResponseWriter, r *http.Request) {
	log.Println(r.Method, r.URL.Path)

	if r.Method != http.MethodPost {
		writeJSON(w, http.StatusMethodNotAllowed, errorResponse{"method_not_allowed"})
		return
	}

	if !authorized(r) {
		writeJSON(w, http.StatusUnauthorized, errorResponse{"unauthorized"})
		return
	}

	var req createRequest
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, errorResponse{"invalid_json"})
		return
	}

	pcPeerId := clean(req.PcPeerId)
	androidPeerId := clean(req.AndroidPeerId)
	sessionId := clean(req.CloudsendSessionId)

	if pcPeerId == "" || androidPeerId == "" || sessionId == "" {
		writeJSON(w, http.StatusBadRequest, errorResponse{"missing_required_id"})
		return
	}

	appId64, err := strconv.ParseUint(os.Getenv("ZEGO_APP_ID"), 10, 32)
	if err != nil || appId64 == 0 {
		writeJSON(w, http.StatusInternalServerError, errorResponse{"invalid_zego_app_id"})
		return
	}

	appId := uint32(appId64)
	secret := os.Getenv("ZEGO_SERVER_SECRET")
	if secret == "" {
		writeJSON(w, http.StatusInternalServerError, errorResponse{"missing_zego_server_secret"})
		return
	}

	ttl := int64(3600)
	if v, err := strconv.ParseInt(getenv("VOICE_TOKEN_TTL_SECONDS", "3600"), 10, 64); err == nil && v >= 60 {
		ttl = v
	}

	nonce := randomHex(8)

	roomId := trim(fmt.Sprintf("cs_voice_%s_%s_%s_%s", androidPeerId, pcPeerId, sessionId, nonce), 128)
	callerUserId := trim(fmt.Sprintf("pc_%s_%s", pcPeerId, sessionId), 64)
	calleeUserId := trim(fmt.Sprintf("android_%s_%s", androidPeerId, sessionId), 64)
	callerStreamId := trim(fmt.Sprintf("cs_voice_pub_%s_pc", nonce), 64)
	calleeStreamId := trim(fmt.Sprintf("cs_voice_pub_%s_android", nonce), 64)

	callerToken, err := makeToken(appId, callerUserId, secret, ttl)
	if err != nil {
		log.Println("caller token error:", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{"caller_token_failed"})
		return
	}

	calleeToken, err := makeToken(appId, calleeUserId, secret, ttl)
	if err != nil {
		log.Println("callee token error:", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{"callee_token_failed"})
		return
	}

	writeJSON(w, http.StatusOK, createResponse{
		RtcProvider:    "zego",
		AppId:          appId,
		RoomId:         roomId,
		CallerUserId:   callerUserId,
		CalleeUserId:   calleeUserId,
		CallerStreamId: callerStreamId,
		CalleeStreamId: calleeStreamId,
		CallerToken:    callerToken,
		CalleeToken:    calleeToken,
		ExpiresAt:      time.Now().Unix() + ttl,
	})
}

func makeToken(appId uint32, userId string, secret string, ttl int64) (string, error) {
	return token04.GenerateToken04(appId, userId, secret, ttl, "")
}

func authorized(r *http.Request) bool {
	expected := os.Getenv("VOICE_API_KEY")
	if expected == "" {
		return true
	}
	return strings.TrimSpace(r.Header.Get("Authorization")) == "Bearer "+expected
}

func writeJSON(w http.ResponseWriter, code int, v interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func getenv(key string, fallback string) string {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	return v
}

func clean(s string) string {
	s = strings.TrimSpace(s)
	var b strings.Builder
	for _, r := range s {
		if r >= 'a' && r <= 'z' ||
			r >= 'A' && r <= 'Z' ||
			r >= '0' && r <= '9' ||
			r == '_' || r == '-' {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func trim(s string, max int) string {
	if len(s) <= max {
		return s
	}
	return s[:max]
}

func randomHex(n int) string {
	buf := make([]byte, n)
	if _, err := rand.Read(buf); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 16)
	}
	return hex.EncodeToString(buf)
}
EOF
```

---

> 注意：`main.go` 必须完整复制到最后一个 `EOF`。如果粘贴后终端出现 `EOF return ...` 这类混乱内容，说明文件已粘坏，需要重新执行本节整段命令覆盖 `main.go`。

---

## 10. 构建服务

```bash
cd /www/wwwroot/cloudsend-zego-token
GOPROXY=https://goproxy.cn,direct go mod tidy
GOPROXY=https://goproxy.cn,direct go build -o cloudsend-zego-token main.go
chmod +x cloudsend-zego-token
```

---

## 11. 创建 systemd 服务

```bash
cat > /etc/systemd/system/cloudsend-zego-token.service <<'EOF'
[Unit]
Description=CloudSend ZEGO Token Service
After=network.target

[Service]
Type=simple
WorkingDirectory=/www/wwwroot/cloudsend-zego-token
EnvironmentFile=/www/wwwroot/cloudsend-zego-token/.env
ExecStart=/www/wwwroot/cloudsend-zego-token/cloudsend-zego-token
Restart=always
RestartSec=3
User=root
Group=root

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now cloudsend-zego-token
systemctl status cloudsend-zego-token --no-pager
```

---

## 12. 本机测试

健康检查：

```bash
curl http://127.0.0.1:8787/api/v1/health
```

正常返回：

```json
{"ok":true}
```

Token 创建测试：

```bash
curl -X POST http://127.0.0.1:8787/api/v1/voice-call/create \
  -H "Authorization: Bearer PHFfBRiEXVKFvEGD2cJp" \
  -H "Content-Type: application/json" \
  -d '{"pcPeerId":"pc_test","androidPeerId":"android_test","cloudsendSessionId":"sess_test"}'
```

正常返回字段：

```json
{
  "rtcProvider": "zego",
  "appId": 726162948,
  "roomId": "cs_voice_xxx",
  "callerUserId": "pc_xxx",
  "calleeUserId": "android_xxx",
  "callerStreamId": "cs_voice_pub_xxx_pc",
  "calleeStreamId": "cs_voice_pub_xxx_android",
  "callerToken": "04...",
  "calleeToken": "04...",
  "expiresAt": 1780000000
}
```

---

## 13. 宝塔反向代理

宝塔面板操作：

```text
网站 -> 1.738489234.com -> 反向代理 -> 添加反向代理
```

填写：

```text
代理名称：zego-token
目标URL：http://127.0.0.1:8787
发送域名：$host
```

保存后测试：

```bash
curl https://1.738489234.com/api/v1/health
```

正常返回：

```json
{"ok":true}
```

公网 Token 测试：

```bash
curl -X POST https://1.738489234.com/api/v1/voice-call/create \
  -H "Authorization: Bearer PHFfBRiEXVKFvEGD2cJp" \
  -H "Content-Type: application/json" \
  -d '{"pcPeerId":"pc_test","androidPeerId":"android_test","cloudsendSessionId":"sess_test"}'
```

---

## 14. 手动 Nginx 配置备选

如果不用宝塔反向代理，可手动创建 HTTP 反向代理配置：

```bash
cat > /www/server/panel/vhost/nginx/1.738489234.com.conf <<'EOF'
server {
    listen 80;
    server_name 1.738489234.com;

    location / {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
EOF

nginx -t && systemctl reload nginx
```

生产环境建议优先通过宝塔 SSL 面板申请证书，并开启强制 HTTPS。

---

## 15. 日志与运维

查看服务状态：

```bash
systemctl status cloudsend-zego-token --no-pager
```

实时日志：

```bash
journalctl -u cloudsend-zego-token -f
```

最近 100 行日志：

```bash
journalctl -u cloudsend-zego-token -n 100 --no-pager
```

重启服务：

```bash
systemctl restart cloudsend-zego-token
```

检查 Nginx：

```bash
nginx -t
systemctl status nginx --no-pager
```

重载 Nginx：

```bash
systemctl reload nginx
```

---

## 16. PC 客户端配置

PC 客户端请求地址应配置为：

```text
https://1.738489234.com/api/v1/voice-call/create
```

鉴权：

```text
Authorization: Bearer PHFfBRiEXVKFvEGD2cJp
```

当前 Rust 配置锚点：

- `src/client/helper.rs::DEFAULT_ZEGO_TOKEN_URL`
- `src/client/helper.rs::DEFAULT_ZEGO_TOKEN_API_KEY`
- PC 端固定使用上述两个常量；不再读取本地覆盖配置，也不保留旧域名 fallback。

---

## 17. 常见问题

### `Command 'go' not found`

说明 Go 构建环境未安装：

```bash
apt update
apt install -y golang-go
go version
```

安装完成后回到服务目录重新执行构建：

```bash
cd /www/wwwroot/cloudsend-zego-token
GOPROXY=https://goproxy.cn,direct go mod tidy
GOPROXY=https://goproxy.cn,direct go build -o cloudsend-zego-token main.go
chmod +x cloudsend-zego-token
```

### `main.go` 粘贴后出现乱码或 `EOF return ...`

说明 heredoc 没完整粘贴或中途被截断。重新执行 `创建完整 main.go` 那一整段命令覆盖文件，再构建。

### Android 显示 `ZEGO Token 鉴权失败` 或 `1002033`

含义：ZEGO `loginRoom` 鉴权失败，通常是 Token 不正确或已过期。

检查：

- `.env` 中 `ZEGO_APP_ID` 是否正确。
- `.env` 中 `ZEGO_SERVER_SECRET` 是否属于同一个 ZEGO 项目。
- `makeToken(...)` 是否使用：

```go
return token04.GenerateToken04(appId, userId, secret, ttl, "")
```

- 服务端时间是否正常。
- 修改 `.env` 或 `main.go` 后是否重新构建并重启服务。

### `POST /api/v1/voice-call/create` 返回 `caller_token_failed`

含义：HTTP 请求已经进入 Token 服务，`Authorization` 也已通过，但服务端调用 ZEGO `GenerateToken04(...)` 失败。

优先检查：

- `.env` 中 `ZEGO_SERVER_SECRET` 是否是 `360a56369441ee640841cb4c82144186`。
- `.env` 中 `ZEGO_SERVER_SECRET` 是否属于 `ZEGO_APP_ID=726162948` 对应的同一个 ZEGO 项目。
- `.env` 修改后是否执行了 `systemctl restart cloudsend-zego-token`。
- 日志里是否有 `caller token error:` 详细错误。

检查命令：

```bash
cd /www/wwwroot/cloudsend-zego-token
grep -E '^(ZEGO_APP_ID|ZEGO_SERVER_SECRET|VOICE_TOKEN_TTL_SECONDS|VOICE_API_KEY)=' .env
journalctl -u cloudsend-zego-token -n 50 --no-pager
```

### `curl 127.0.0.1:8787/api/v1/health` 连接失败

检查服务：

```bash
systemctl status cloudsend-zego-token --no-pager
journalctl -u cloudsend-zego-token -n 100 --no-pager
```

### `status=203/EXEC`

通常是二进制不存在或不可执行：

```bash
cd /www/wwwroot/cloudsend-zego-token
ls -lh cloudsend-zego-token
chmod +x cloudsend-zego-token
systemctl restart cloudsend-zego-token
```

### 公网 `https://1.738489234.com/api/v1/health` 不通

检查：

- DNS 是否解析到服务器公网 IP。
- 宝塔站点是否创建。
- SSL 是否申请成功。
- 反向代理目标是否是 `http://127.0.0.1:8787`。
- Nginx 是否通过 `nginx -t`。
- 防火墙是否放行 80/443。

---

## 18. 最终验收清单

- `systemctl status cloudsend-zego-token --no-pager` 显示 `active (running)`。
- `curl http://127.0.0.1:8787/api/v1/health` 返回 `{"ok":true}`。
- `curl https://1.738489234.com/api/v1/health` 返回 `{"ok":true}`。
- `POST /api/v1/voice-call/create` 返回 `callerToken` 和 `calleeToken`。
- PC 客户端 Token URL 使用 `https://1.738489234.com/api/v1/voice-call/create`。
- PC 客户端 Bearer key 与服务器 `.env` 中 `VOICE_API_KEY` 一致。
- Android 接听后不再出现 `1002033`。
