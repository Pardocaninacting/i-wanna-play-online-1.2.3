# iwannaplay.online 网站

I wanna play online 的网站：在线大厅、下载、皮肤库、游戏评分与项目介绍。
纯静态站点，没有构建步骤；实时数据由同源路径上的后端接口提供。

## 页面

| 页面 | 内容 | 数据 |
|---|---|---|
| `index.html` | 大厅：实时地球与在线房间表 | `POST /getGames` |
| `download.html` | 最新版与历史版本下载 | `POST /version`、`/files/` |
| `skins.html` | 皮肤库：浏览、预览、下载、上传 | `/skins` 系列 |
| `ratings.html` | 游戏评分：统计、筛选、按游戏汇总 | `GET /ratings/api` |
| `about.html` | 使用方法、功能、常见问题、项目历史、鸣谢 | — |
| `404.html` | 找不到页面 | — |

`version.txt` 是当前版本号，转换器每次转换结束后会读取它来提示更新。

## 后端接口

页面只请求同源路径。生产环境中由反向代理把它们转发到配套的 API 服务，
房间列表、评分与皮肤库数据来自游戏服务器（本仓库的 `server/`）。

| 方法 | 路径 | 返回 |
|---|---|---|
| POST | `/getGames` | `{ success, games: [{ name, players, hasPassword }] }` |
| POST | `/version` | `{ success, version }` |
| GET | `/ratings/api` | `{ ratings: [{ gameID, gameName, playerName, stars, cleared, timestamp }] }` |
| GET | `/ratings/api/<gameID>` | 同上，只含该游戏 |
| GET | `/skins` | `{ success, count, skins: [{ hash, name, maker, source, states }] }` |
| GET | `/skins/<hash>/file/<state>.png` | 皮肤某个动作的帧条 |
| GET | `/skins/<hash>.zip` | 整个皮肤包 |
| POST | `/skins/upload` | multipart：`name`、`maker`、`source` 与 `files`（散文件或一个 zip） |
| GET | `/files/<文件名>.zip` | 转换器安装包（静态目录） |

## 本地预览

```bash
node _dev/dev-server.cjs            # http://127.0.0.1:8199/
```

`_dev/dev-server.cjs` 是零依赖的 Node 服务，按上表的接口应答，并提供站点静态文件：

- 大厅页加 `?mock=1` 显示示例房间，`?mock=empty` 显示无人在线的状态；
  设置环境变量 `IWPO_LIVE=1` 后 `/getGames` 会改为请求 iwannaplay.online 的真实房间。
- 评分与皮肤读取可选的 `_dev/data/`（不纳入版本库），目录不存在时接口返回空列表：

  ```
  _dev/data/version.txt              当前版本号
  _dev/data/ratings/<gameID>.json    评分记录数组
  _dev/data/skins/<hash>/            info.ini + idle/run/jump/fall[/slide/bullet].png
  ```

- 地球与流体需要 WebGL；在没有 GPU 的无头浏览器里截图时请给 Chrome 加 `--enable-unsafe-swiftshader`。

## 实时图形

- **地球**（`assets/js/globe.js`，three.js）：枢纽是服务器；每位在线玩家是一个在轨道环上奔跑的光点，
  按 I wanna 引擎的物理起跳（起跳 8.5、二段跳 7、重力 0.4、松键 ×0.45），红色拖尾；
  进行中的房间是枢纽上的脉冲光柱；没人在线时枢纽为钢蓝色。
  数据由 `home.js` 通过 `window.IWPO_GLOBE.setState({ players, rooms })` 传入。
- **流体背景**（`assets/vendor/fluid.js`）：改编自 Pavel Dobryakov 的 WebGL-Fluid-Simulation，
  输出经 4×4 有序抖动量化为品牌蓝（`?fx=smooth` 查看未抖动的版本）；玩家每次起跳都会推动一股流体
  （地球派发 `iwpo:wake` 事件，流体监听）。
- **陆地点阵**取自 `assets/img/land-mask.png`，由 `node _dev/make-land-mask.cjs` 从 Natural Earth 1:50m 陆地数据生成。
- 开启「减少动态效果」（`prefers-reduced-motion`）时流体不启动、地球只渲染一帧；没有 WebGL 时地球降级为文字。

## 部署

把站点文件放到 Web 服务器的根目录（`_dev/` 不需要部署），然后在反向代理中：

1. 把上表的接口路径转发到 API 服务；
2. 提供 `/files/` 安装包目录；
3. 设置 `error_page 404 /404.html;` 使用站点自带的 404 页。

## 目录

```
*.html                 页面
version.txt            当前版本号（转换器的更新检查读取它）
assets/css/style.css   设计系统
assets/js/             页面脚本（site.js 为共享的请求与转义助手）
assets/vendor/         three.js 与流体模拟
assets/img/            站点图标与陆地遮罩
_dev/                  本地开发服务器与陆地遮罩生成脚本（不部署）
```

## 第三方组件

| 组件 | 位置 | 许可 |
|---|---|---|
| three.js r180 | `assets/vendor/three.module.min.js`、`three.core.min.js` | MIT |
| WebGL-Fluid-Simulation（Pavel Dobryakov，已改编） | `assets/vendor/fluid.js` | MIT，全文见文件头 |
| Natural Earth 陆地数据 | 生成 `assets/img/land-mask.png` | 公有领域 |

其余代码与仓库一起以 MIT 许可发布，见根目录的 `LICENSE`。
