# ZEGO Token Service Deployment / 宝塔部署文档

最后一次整理：2026-05-31

> 本文档用于部署 CloudSend 第三方 1v1 语音通话所需的 ZEGO Token 服务。
> 服务端负责生成短时 ZEGO Token；PC 和 Android 客户端不得保存 `ZEGO_SERVER_SECRET`。
>
> 代码路径、接口名、环境变量、服务名保留 English anchor，中文负责解释。

---

## 1. 目标架构

CloudSend 的语音通话入口仍复用现有 PC 工具栏与 Android 来电确认流程，但媒体链路改为 ZEGO RTC。

```text
PC 语音按钮
  -> HTTPS POST /api/v1/voice-call/create
  -> 宝塔 Nginx / reverse proxy
  -> cloudsend-zego-token service 127.0.0.1:8787
  -> 返回 roomId / callerToken / calleeToken
  -> PC 使用 callerToken 加入 ZEGO room
  -> PC 通过现有 CloudSend 远控连接把 calleeToken 发送给 Android
  -> Android 接听后使用 calleeToken 加入同一个 ZEGO room
```

核心隔离原则：

- 每次通话生成独立 `roomId`。
- PC 使用 `callerToken`，Android 使用 `calleeToken`。
- `ZEGO_SERVER_SECRET` 只存在宝塔服务器 `.env`，不能写入 PC / Android / Git 仓库。
- `roomId` 包含 `androidPeerId + pcPeerId + cloudsendSessionId + nonce`，避免不同 PC / Android 之间串房。

---

## 2. 服务器与域名准备

推荐环境：

```text
OS: Ubuntu 22.04 LTS
Panel: 宝塔面板
Web Server: Nginx / Tengine
Service Runtime: Go
Domain: api.unan.uno
Service Port: 127.0.0.1:8787
```

域名 DNS 需要添加：

```text
类型：A
主机记录：api
记录值：服务器公网 IP
```

验证：

```bash
ping api.unan.uno
```

返回的 IP 应等于服务器公网 IP。

---

## 3. 宝塔创建站点

在宝塔面板执行：

```text
网站 -> 添加站点
域名：api.unan.uno
PHP版本：纯静态
根目录：/www/wwwroot/api.unan.uno
```

然后配置 SSL：

```text
网站 -> api.unan.uno -> SSL -> Let's Encrypt -> 申请证书
```

建议开启：

```text
强制 HTTPS：开启
```

如果不使用宝塔 SSL，也可以用 `certbot` 手动申请证书。

---

## 4. 安装 Go

宝塔终端执行：

```bash
apt update -y
apt install -y golang-go
go version
```

确认输出类似：

```text
go version go1.18.x linux/amd64
```

---

## 5. 创建服务目录

```bash
mkdir -p /www/wwwroot/cloudsend-zego-token
cd /www/wwwroot/cloudsend-zego-token
```

---

## 6. 创建环境变量文件

创建 `.env`：

```bash
cat > .env <<'EOF'
PORT=8787
ZEGO_APP_ID=你的ZEGO_AppID
ZEGO_SERVER_SECRET=你的ZEGO_ServerSecret
VOICE_TOKEN_TTL_SECONDS=3600
VOICE_API_KEY=改成一串很长的随机API_KEY
EOF

chmod 600 .env
```

字段说明：

| 环境变量 | 说明 |
|---|---|
| `PORT` | 本地监听端口，默认 `8787` |
| `ZEGO_APP_ID` | ZEGO 控制台的 AppID |
| `ZEGO_SERVER_SECRET` | ZEGO 控制台服务端密钥，只能放服务端 |
| `VOICE_TOKEN_TTL_SECONDS` | Token 有效期，建议先用 `3600` 秒 |
| `VOICE_API_KEY` | CloudSend 请求 Token 服务时使用的内部鉴权密钥 |

生成随机 `VOICE_API_KEY` 的方式：

```bash
openssl rand -base64 32
```

---

## 7. 创建 Go Module

```bash
cat > go.mod <<'EOF'
module cloudsend-zego-token

go 1.18

require github.com/ZEGOCLOUD/zego_server_assistant/token/go/src v0.0.0-20231103072415-8c895c31df9d
EOF
```

---

## 8. 创建 main.go

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

	http.HandleFunc("/api/v1/health", func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]bool{"ok": true})
	})

	http.HandleFunc("/api/v1/voice-call/create", handleCreate)

	addr := "127.0.0.1:" + port
	log.Println("cloudsend zego token service listening on", addr)
	log.Fatal(http.ListenAndServe(addr, nil))
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

	callerToken, err := makeToken(appId, callerUserId, secret, ttl, roomId, callerStreamId)
	if err != nil {
		log.Println("caller token error:", err)
		writeJSON(w, http.StatusInternalServerError, errorResponse{"caller_token_failed"})
		return
	}

	calleeToken, err := makeToken(appId, calleeUserId, secret, ttl, roomId, calleeStreamId)
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

func makeToken(appId uint32, userId string, secret string, ttl int64, roomId string, streamId string) (string, error) {
	payload := map[string]interface{}{
		"room_id": roomId,
		"privilege": map[string]int{
			"1": 1,
			"2": 1,
		},
		"stream_id_list": []string{streamId},
	}

	b, err := json.Marshal(payload)
	if err != nil {
		return "", err
	}

	return token04.GenerateToken04(appId, userId, secret, ttl, string(b))
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
		if r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_' || r == '-' {
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
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return strconv.FormatInt(time.Now().UnixNano(), 36)
	}
	return hex.EncodeToString(b)
}
EOF
```

---

## 9. 构建服务

```bash
cd /www/wwwroot/cloudsend-zego-token
GOPROXY=https://goproxy.cn,direct go mod tidy
GOPROXY=https://goproxy.cn,direct go build -o cloudsend-zego-token main.go
chmod +x cloudsend-zego-token
```

确认二进制存在：

```bash
ls -lh /www/wwwroot/cloudsend-zego-token/cloudsend-zego-token
```

---

## 10. 创建 systemd 服务

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

成功状态：

```text
Active: active (running)
```

如果看到 `status=203/EXEC`，通常表示 `cloudsend-zego-token` 文件不存在或没有执行权限，重新执行第 9 步。

---

## 11. 宝塔反向代理

在宝塔面板执行：

```text
网站 -> api.unan.uno -> 反向代理 -> 添加反向代理
```

填写：

```text
代理名称：zego-token
目标URL：http://127.0.0.1:8787
发送域名：$host
```

如果宝塔有“代理目录”，建议填：

```text
/
```

如果只想代理接口路径，也可以填：

```text
/api/v1/
```

---

## 12. Nginx 手动配置参考

如果不使用宝塔反向代理，可以手动写 Nginx 配置：

```nginx
server {
    listen 80;
    server_name api.unan.uno;

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name api.unan.uno;

    ssl_certificate /etc/letsencrypt/live/api.unan.uno/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.unan.uno/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location /api/v1/health {
        proxy_pass http://127.0.0.1:8787/api/v1/health;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location /api/v1/voice-call/ {
        proxy_pass http://127.0.0.1:8787/api/v1/voice-call/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    location / {
        return 404;
    }
}
```

检查并重载：

```bash
/www/server/nginx/sbin/nginx -t
/www/server/nginx/sbin/nginx -s reload
```

---

## 13. 接口测试

本机健康检查：

```bash
curl http://127.0.0.1:8787/api/v1/health
```

期望返回：

```json
{"ok":true}
```

外网健康检查：

```bash
curl https://api.unan.uno/api/v1/health
```

期望返回：

```json
{"ok":true}
```

创建通话 Token：

```bash
curl -X POST https://api.unan.uno/api/v1/voice-call/create \
  -H "Authorization: Bearer 你的VOICE_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"pcPeerId":"pc_test","androidPeerId":"android_test","cloudsendSessionId":"sess_test"}'
```

成功返回示例：

```json
{
  "rtcProvider": "zego",
  "appId": 726162948,
  "roomId": "cs_voice_android_test_pc_test_sess_test_xxxxxxxx",
  "callerUserId": "pc_pc_test_sess_test",
  "calleeUserId": "android_android_test_sess_test",
  "callerStreamId": "cs_voice_pub_xxxxxxxx_pc",
  "calleeStreamId": "cs_voice_pub_xxxxxxxx_android",
  "callerToken": "04...",
  "calleeToken": "04...",
  "expiresAt": 1780169977
}
```

---

## 14. CloudSend 客户端后续对接信息

CloudSend 后续代码改造需要配置：

```text
ZEGO Token API:
https://api.unan.uno/api/v1/voice-call/create

Authorization:
Bearer <VOICE_API_KEY>
```

请求体：

```json
{
  "pcPeerId": "当前PC ID",
  "androidPeerId": "当前Android ID",
  "cloudsendSessionId": "当前远控会话ID"
}
```

PC 使用返回的：

```text
callerUserId
callerStreamId
callerToken
roomId
```

Android 使用返回的：

```text
calleeUserId
calleeStreamId
calleeToken
roomId
```

PC 通过 CloudSend 现有远控连接把 Android 所需字段发送给 Android。

---

## 15. 运维命令

查看服务状态：

```bash
systemctl status cloudsend-zego-token --no-pager
```

重启服务：

```bash
systemctl restart cloudsend-zego-token
```

查看日志：

```bash
journalctl -u cloudsend-zego-token -f
```

修改配置后生效：

```bash
cd /www/wwwroot/cloudsend-zego-token
vim .env
systemctl restart cloudsend-zego-token
```

重新构建：

```bash
cd /www/wwwroot/cloudsend-zego-token
GOPROXY=https://goproxy.cn,direct go build -o cloudsend-zego-token main.go
chmod +x cloudsend-zego-token
systemctl restart cloudsend-zego-token
```

---

## 16. 安全要求

必须遵守：

- 不要把 `ZEGO_SERVER_SECRET` 写入 PC 客户端。
- 不要把 `ZEGO_SERVER_SECRET` 写入 Android 客户端。
- 不要把 `.env` 提交到 Git。
- 不要在日志里打印 `callerToken` / `calleeToken`。
- 宝塔、SSH、ZEGO 密钥如果曾经暴露，应立即轮换。
- 正式环境必须走 HTTPS。
- `VOICE_API_KEY` 应使用强随机字符串，长度建议 32 字节以上。

建议后续增强：

- 使用 CloudSend 登录态替代固定 `VOICE_API_KEY`。
- 服务端校验 PC 用户是否有权限控制目标 Android。
- 加入忙线逻辑：同一 Android 同一时间只允许一个 ZEGO voice call。
- 加入 `/api/v1/voice-call/end` 记录挂断状态。
- 加入 Redis / SQLite 保存短时 active room。

---

## 17. 常见问题

### `curl 127.0.0.1:8787/api/v1/health` 连接失败

检查服务：

```bash
systemctl status cloudsend-zego-token --no-pager
journalctl -u cloudsend-zego-token -n 80 --no-pager
```

### `status=203/EXEC`

通常是二进制不存在或不可执行：

```bash
cd /www/wwwroot/cloudsend-zego-token
GOPROXY=https://goproxy.cn,direct go build -o cloudsend-zego-token main.go
chmod +x cloudsend-zego-token
systemctl restart cloudsend-zego-token
```

### 返回 `unauthorized`

请求头缺少：

```text
Authorization: Bearer <VOICE_API_KEY>
```

### 返回 `caller_token_failed` 或 `callee_token_failed`

检查：

```bash
cat /www/wwwroot/cloudsend-zego-token/.env
```

重点确认：

```text
ZEGO_APP_ID
ZEGO_SERVER_SECRET
```

### 外网 HTTPS 不通，本机 127.0.0.1 正常

检查：

```bash
curl http://127.0.0.1:8787/api/v1/health
curl https://api.unan.uno/api/v1/health
```

如果本机正常、外网不正常，重点检查：

- DNS 是否指向服务器公网 IP。
- 宝塔站点是否绑定 `api.unan.uno`。
- SSL 是否申请成功。
- 反向代理目标是否是 `http://127.0.0.1:8787`。
- Nginx 是否已重载。

