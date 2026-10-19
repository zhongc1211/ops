# futuredeepvision/ryze 为什么复刻得像（只读分析）

2026-10-18 SGT，Claude Code 在 iMac 上执行。没有 push、没有开 PR，两个仓库都没改；没花钱，没碰生产。

## 结论（5 行）

1. 两边复刻的对象不同：ryze 仓库复刻的是登录后的广告后台 reports.get-ryze.ai，不是官网 get-ryze.ai。仓库里没有官网首页和官网定价页，跟它真正可比的是 deepvision-ads，不是 deepvision-site。
2. 它像，主要是因为它没有"重写"：直接加载 Ryze 线上的两个 Tailwind CSS 包和字体，把原站 DOM 的 class 原样抄进模板，图片、图标、Next 缩放图都从原站下载到本地。
3. 每页都有硬性验收：同视口、关动画、等图片加载完以后，和登录后的原站逐屏截图做像素 diff，标准是整页差异 ≤ 0.01%。README 记录了每页的数字，多数页面是 0 px。
4. 我们做不到这么像，原因在设计取舍：官网 PR #85 是"Ryze 的布局 + 我们的配色 + 营销 r2 文案 + 自制素材"，还要求对比度 ≥ 4.5；deepvision-ads 的 AGENTS.md 明确规定不抄 Ryze 的文案、图片、logo 和代码。两边都没有和原站做像素对照。
5. 能直接照搬的是它的方法（DOM 导出、几何比对、像素 diff 脚本、比对前的 prep、≤0.01% 验收）。它的素材本身（Ryze 的 CSS、图片、广告样本）是 Ryze 和第三方品牌的东西，不能上我们的线上产品。

## 1. 仓库基本情况

- 位置：`~/orca/research/ryze-ref`（`--depth 50` 克隆，实际 38 个提交，全部可见），工作树约 214 MB，其中 `assets/competitor-ads` 80 MB、`assets/ad-templates` 24 MB。
- 提交者只有一个：`azero`，38 个提交。时间是 10-17 13:25 到 10-18 21:13（+0800）。
- 技术栈：零框架。`server.mjs` 是 Node 原生 HTTP 服务（端口 4173），前端是原生 JS 模板字符串（`src/observed.js` 1005 行，约 170 KB），用 `data-action` 做事件委托。样式直接用 Ryze 自己的 Tailwind v4 产物。依赖只有 4 个：`ai`、`@openrouter/ai-sdk-provider`、`playwright-core`、`zod`，供后加的 AI Marketer agent 使用。
- 覆盖范围：登录后的后台，30 个左右页面，包括 Home、AI Marketer（新聊天、聊天详情、历史、日程、模板、报告）、Integrations、Brand、Media、Web Analytics、Ads Performance 四个标签、Managed Campaigns、My Creatives、Ad Templates、Competitor Ads、工作区设置 4 个标签、组织设置 5 页（含 Billing）。**没有官网页面。**brief 里说的"定价页"，在这个仓库里最接近的是组织设置的 Billing 页（套餐和价格卡）。
- 附带内容：
  - `mcp-mock/`：用账号 API key 导出 Ryze MCP 工具 schema，再起一个本地 mock。
  - `optimized-skills/`：18 份 SKILL.md，是在 Ryze AI Marketer 聊天里让它自己吐出来的。
  - `tool-description-optimization/`：46 个工具描述，也是逐个在 Ryze 聊天里问出来的。
  - `agent/`：10-18 补的本地 agent，走 OpenRouter 生成文案和图片，并用 camoufox 读 Meta 广告库。

## 2. 它是怎么做出来的

### 节奏（git log）

| 时间（+0800） | 做了什么 |
|---|---|
| 10-17 13:25 | 一次提交 1271 个文件：手写的近似版（`observed.css`），加上原站截图、页面文字和接口清单、模板和广告样本 JSON、原站下载的图片 |
| 10-17 19:04 | 转折点：外壳和 `/chat` 改用"原站 Tailwind 产物"重建，`/chat` 差异 0.009%（147 px，全部是余额数字） |
| 10-17 19:05 | 写 `reference/HANDOFF-PROMPT.md`，交代给下一个 agent：一次只做一页，对到 ≤ 0.01% 才提交 |
| 10-17 19:20–20:52 | 约 1.5 小时连提 12 个提交，按顺序对齐了 20 多页，每页改动 40–180 行 |
| 10-18 01:14–02:52 | 加 agent 运行时（设计文档、工具、流式输出、修 bug） |
| 10-18 09:34–21:13 | 补齐 Competitor Ads、聊天详情，接真实网页抓取和 Meta 广告库 |

能做这么快，是因为方法定死了：每页都是"导出原站 DOM → 抄 class → 比几何 → 比像素"，靠脚本流水线执行，不靠设计判断。

### 方法（`reference/PIXEL-ALIGNMENT.md` 写得很完整）

1. 抓结构：在登录后的原站页面上导出 `main` 的 `outerHTML`（`reference/playwright/dump.sh`），再用 `skel.py` 压成骨架阅读，用 `html2tpl.py` 把原站片段转成本地模板字符串（svg 换成 lucide 图标调用，去掉 base-ui 生成的 id）。
2. 抓行为：静态 DOM 看不出来的东西（随机短语、条件 class、动画触发、Masonry 排布、recharts 柱宽），把原站 `_next/static/chunks/*.js` 下载下来 grep 字面量，找到原实现再照抄（`chunks.sh`）。
3. 样式不手写：`index.html` 直接加载 Ryze 的两个 CSS bundle（`assets/ryze/css/`）和 Plus Jakarta Sans 字体。旧的手写样式放进 `@layer legacy`，位置排在 `base` 之后、`utilities` 之前。
4. 素材从原站下载：图标、集成 logo、`/_next/image` 的重编码 webp（连缩放后的抗锯齿都一致）、模板预览、广告样本图、竞品 favicon。`server.mjs` 把原站的绝对路径映射到本地，所以原站标记可以原样贴。
5. 先比几何，再比像素：两边对同一组选择器比 `getBoundingClientRect`。几何对平以后，用 `reference/playwright/mk.sh` 加 `harness.tpl.js` 逐屏截图（最多 12 屏），再用 `diff.sh` / `pixel-diff.py` 出差异，可以传遮罩矩形。
6. 比对前的 prep：清残留 tooltip、滚动归零、图片改 eager、关掉全部动画和过渡、去焦点、等图片 pending 归零、鼠标移开、设好视口以后重载原站。不做这一步会有 3–10% 的假差异。
7. 账号里的实时数据（余额、聊天记录、用量）不改 mock，比对时用 `page.route()` 临时灌入原站当时的数值，或者遮掉。
8. 原站必须是用户真实的登录会话。红线是：不注入合成鼠标事件、不点会写数据的按钮、只读和截图。

### 素材来源

| 素材 | 来源 |
|---|---|
| CSS、字体 | 原站下载（Ryze 的 Tailwind 产物；Plus Jakarta Sans 本身是 OFL 开源字体） |
| 图标 | 37 个 lucide 图标，从原站页面导出（lucide 是 ISC 许可） |
| 集成 logo、模板预览、讲解视频封面、侧栏纹理 | 原站下载 |
| Ad Templates（823 张卡片）、Competitor Ads 样本（约 100 条） | 原站列表数据和图片，图片内容是第三方品牌的真实广告（例如 Wealthfront、Monzo、Klarna） |
| AI 生成 | 只用在后加的 agent 里（OpenRouter 生成广告图），复刻界面本身没有用生成素材 |

## 3. 本地运行和截图

- 已完成：在 `~/orca/research/ryze-ref` 跑 `npm ci`（成功，13 个包），再跑 `node server.mjs`，`/deepvision-2/default` 返回 200。截完图已经关掉服务。
- 截图方式：用 playwright-core 驱动本机 Chrome 无头模式，1440 宽、DPR 1。页面靠内部容器滚动，所以每页截两张：首屏 1440×900，以及把视口拉到内容高度的整页图。

截图路径：

- Ryze 复刻（本仓库）
  - `~/orca/research/ryze-ref-shots/home-1440x900.png`、`home-1440-full.png`：首页
  - `~/orca/research/ryze-ref-shots/billing-pricing-1440x900.png`、`billing-pricing-1440-full.png`：组织 Billing 页，即仓库里的"定价"
  - `~/orca/research/ryze-ref-shots/chat-1440x900.png`、`chat-1440-full.png`：AI Marketer 新聊天
- 对照组（额外截的）
  - `~/orca/research/ryze-ref-shots/ours-pr85-3e050d2/home-*.png`、`pricing-*.png`：deepvision-site PR #85 的 head 3e050d2（PR 里的"Ryze 复刻 4/6"，叠在 3/6 定价页之上），本地 `next dev` 的 `/en` 和 `/en/pricing`
  - `~/orca/research/ryze-ref-shots/get-ryze-public/home-1440-full.png`、`pricing-*.png`：Ryze 公开官网。首页首屏是视频，无头浏览器没有播放，所以首页顶部是纯色背景

还有 Ryze 作者自己留的原站和本地对照图：`~/orca/research/ryze-ref/reference/pixel/original-*.png` 和 `local-*.png`。

## 4. 跟我们的对比：差距的根本原因

| 维度 | ryze 仓库 | deepvision-site（PR #85，3e050d2） | deepvision-ads |
|---|---|---|---|
| 复刻对象 | Ryze 后台 | Ryze 官网 | Ryze 后台 |
| 目标 | 视觉逐像素一致 | 布局、结构、动效像 Ryze，配色、文案、素材换成我们的 | 功能、流程、信息结构一致，外观自己做 |
| 样式来源 | 直接用 Ryze 的 CSS bundle 和原 class | `app/ryze.css`（1119 行手写）。尺寸按 `ryze-clone/TOKENS.md` 量出来的 computed style 填，颜色全部替换（橙色 #FF4801 换成蓝色 #1D4ED8，米色换成浅蓝） | Tailwind 手写，自己的配色（`app/globals.css`），系统字体 |
| 结构来源 | 导出原站 DOM，逐字照抄 | 按 `STRUCTURE.md` 的区块顺序重写 React 组件 | 按截图和 `.txt` 控件清单（`ryze-screens/` 共 293 个文件）重写 |
| 素材 | 原站下载，94 MB 以上 | 营销自制的 SVG 像素街景、HTML 画的窗口、格式记号（缩略图还没交付），`public/` 一共 1.7 MB | 自绘图标或首字母，规则禁止用对方图片 |
| 文案 | 原文 | 营销 r2 | 自写英文 |
| 验收 | 和原站逐屏像素 diff ≤ 0.01%，每页记录数字 | e2e 断言文字、hash、对比度 ≥ 4.5、元素不重叠，不和原站做像素对照 | features.md 的功能验收，不对照视觉 |
| 刻意偏离 | 只有实时数据 | PR #83 里列了 13 条（对比度、WhatsApp 按钮位置、FAQ、横幅等） | 品牌、文案、审批默认档位等，记在 compare.md |

根本原因（按影响从大到小）：

1. 目标不同。我们两条线都把"不像 Ryze"写进了规则：官网换配色、换文案、加对比度约束；后台不许抄外观。它把"和原站一致"当作唯一目标。差距主要是这个选择带来的，不是执行得好坏。
2. 样式来源不同。手写 CSS 就算尺寸照 TOKENS.md 填，行高、字距、阴影、过渡、`tailwind-merge` 的结果都会累积出偏差。直接用原产物就没有这些偏差。
3. 素材差距最显眼。Ryze 官网的观感很大程度靠大幅精绘像素风插画、真实产品截图、媒体 logo 条和 6 平台真彩 logo。我们的首屏是纯色蓝底加 SVG 简笔街景和 HTML 窗口，墙上的缩略图还是占位记号。看 `ours-pr85-3e050d2/home-1440x900.png` 和 `get-ryze-public/pricing-1440x900.png`，差距一眼可见。
4. 没有像素对照闭环。我们的 e2e 只能证明"我们自己定的规则成立"，证明不了"看起来像"。它每页都有原站截图和本地截图对照，差异落到具体像素，所以偏差没法混过去。
5. 节奏不同。它一次只做一页，对齐了才提交，下一页沿用同一套构件（`uiCard`、`uiButton` 等原 class 的封装）。我们的官网复刻拆成 6 个叠加 PR（#81–#89），每个 PR 都同时处理文案、对比度、i18n、e2e 和营销审稿，视觉对照只是其中一项。

## 5. 我们能照搬的做法

### 立刻能用（不涉及版权，不改变已定方向）

| 做法 | 用在哪里 | 说明 |
|---|---|---|
| 像素对照流水线：`mk.sh` + `harness.tpl.js` + `diff.sh` / `pixel-diff.py`，加 prep 片段（关动画、eager 图片、等 pending、遮罩） | 官网和 ads 的视觉验收 | 脚本是 azero 写的，不是 Ryze 的东西；抄到 ops 或各仓库的 `scripts/` 前问一下 azero 即可 |
| "先比几何、再比像素"的两步法 | 同上 | 对同一组选择器比 `getBoundingClientRect`，能直接定位哪个块偏了多少 px |
| 跟自己的设计稿做像素回归，不跟 Ryze 比 | 官网 PR #81–#89 | 把营销确认过的稿或上一版截图当基准，每页差异落到数字，写进 PR 的 E2E 结果 |
| 布局对照时只比几何，不比颜色 | 官网（我们换了配色） | 关掉颜色差异，只比各区块的 x/y/w/h 是否和 Ryze 一致。这样能量化"布局像不像"，又不需要用它的素材 |
| 比对前 prep 和"原站标签必须在前台、设视口后重载"这些坑 | 所有截图类 e2e | 能避免 3–10% 的假差异，以及 framer-motion 入场动画停在 opacity:0 导致的空白截图 |
| 一页一提交、交接 prompt 写清顺序和红线 | 后续复刻任务的派活 | `reference/HANDOFF-PROMPT.md` 可以直接当派活模板 |
| 从 JS chunk grep 原实现来理解交互（动画曲线、Masonry、分页窗口算法） | 理解行为 | 只看算法和参数，自己写实现，不复制代码 |

### 要 Zack 拍板

| 事项 | 选项 | 风险 |
|---|---|---|
| 官网的方向：继续"Ryze 布局 + 我们的配色"，还是更贴近 Ryze 的视觉 | A. 维持现状，补像素级几何对照（推荐）；B. 连配色和插画风格也贴近 | B 会让品牌和 Ryze 混淆，商业外观（trade dress）有风险 |
| 素材投入：Ryze 观感的大头是精绘插画和真实产品截图 | 让营销按我们的品牌生成一套同等精度的大幅插画；首屏、定价页用真实产品截图（deepvision-ads 实际界面）取代 HTML 画的窗口 | 需要营销排期；AI 生成图要确认模型条款并留生成记录 |
| deepvision-ads 是否放宽"不抄外观" | A. 维持规则，只借构件层的通用做法（shadcn 风格 Button/Card 的 variant）；B. 结构贴近 Ryze，class 自己写 | 不能用 Ryze 的 CSS bundle、图片、文案（见下方红线） |
| 对比度规则和"像 Ryze"冲突时听谁的 | 现在是对比度优先（PR #83 有 3 条偏离出自这里） | 降低对比度会影响可访问性 |
| ryze 仓库本身的处置 | 仓库在 futuredeepvision 组织下（私有），里面有 Ryze 的 CSS、字体包、原图、第三方广告图、用 Ryze 账号导出的 skill 和工具描述 | 只能内部参考，不能部署，也不能把文件拷进我们的产品仓库；是否需要限制访问或清理由 Zack 决定 |

### 版权和品牌红线（ryze 仓库里不能照搬的东西）

- **Ryze 的 CSS bundle**（`assets/ryze/css/`，`reference/observed-css/`）：Ryze 的代码产物，不能用。
- **Ryze 原图和图标**：侧栏纹理 `sidebar-bg.webp`、模板预览、讲解视频封面、集成卡片图（`assets/observed/`、`assets/reference/`）、Billing 页的插画（`assets/billing/`）、Ryze 太阳 logo（`ryze-sun`），都是 Ryze 的素材。
- **第三方广告图**：`assets/ad-templates/`（823 张）、`assets/competitor-ads/`、`assets/inspiration/`，是 Wealthfront、Monzo、Klarna 等品牌的真实广告，版权属于这些品牌。
- **Ryze 原文**：页面文案、模板标题和提示词（`reference/templates.json`、`playbooks.json` 等）、Billing 页的套餐文字（`src/billing.js`）。
- **从 Ryze 聊天导出的内容**：`optimized-skills/`、`tool-description-optimization/`，以及用账号 API key 导出的 MCP schema。这些可能违反 Ryze 服务条款，只能当参考，不能当我们产品的 prompt 直接用。
- 能用的：Plus Jakarta Sans（OFL）、lucide 图标（ISC）、平台官方 logo（按各平台品牌规范使用，官网已有的做法）。

## 6. 执行记录

- 已完成：克隆 ryze 仓库；读 README、PIXEL-ALIGNMENT、HANDOFF-PROMPT、COMPARISON、比对脚本和 git log；`npm ci` 和 `node server.mjs` 跑通；截 3 页 × 2 张。
- 已完成：浅克隆 deepvision-site 的 PR #85 分支到 `~/orca/research/dv-site-pr85`（head 3e050d2），`npm ci` 后用 `next dev -p 3300` 截了首页和定价页；读了 PR #83 的描述和 `app/ryze.css`。
- 已完成：读了 deepvision-ads 的 AGENTS.md、docs/features.md、research.md，以及 origin/main 的提交记录（bdd50b1）。deepvision-ads 没有跑起来，因为它需要登录和 D1，这次也用不上。
- 关于 brief 里的"PR4 head 3e050d2"：3e050d2 是 futuredeepvision/deepvision-site 的 PR #85（标题"Ryze 复刻 4/6"）的 head，不是 4 号 PR。origin/staging 是 1f16546，还不包含 #81–#89。
- 没做：没有登录 reports.get-ryze.ai 做原站对照（这一步需要账号会话，brief 也没要求）；get-ryze.ai 首页的首屏视频没有播放。
- 后台进程：4173 和 3300 两个服务都已关闭。两个克隆的工作树都没有改动（next dev 自动改写的 AGENTS.md 已还原）。
