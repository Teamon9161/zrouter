# zrouter 设计与实施计划

轻量 CLI + Skill 的混合方案，结合 [HAM](references/ham/) 的层级路由与 [OpenWolf](references/openwolf/) 的文件 anatomy，以最小代价为 Claude Code 节省 token。

---

## 1. 核心思路

- **HAM 的路由**：把单一 CLAUDE.md 切成「根 + 每个子目录」，按工作目录加载相应上下文。
- **OpenWolf 的 anatomy**：给每个文件配一行描述 + token 估算，让 Claude 在打开前就知道文件价值。
- **合体杀手锏**：把 anatomy 切到子目录粒度，**内嵌**到子目录 CLAUDE.md 末尾的标记块里。Claude 路由到 `src/api/` 时，一份文件同时拿到本地约定 + 本地文件索引。

---

## 2. 设计取舍（已定）

| # | 决定 | 备注 |
|---|---|---|
| 1 | 子目录 anatomy **内嵌**子目录 CLAUDE.md，用标记块界定 | 标记尽量短，例：`<!-- zr:files -->` / `<!-- /zr:files -->` |
| 2 | **不**单独造 cerebrum；Do-Not-Repeat 并入 `.memory/decisions.md` 的「反模式」段 | 沿用 HAM 三件套：decisions / patterns / inbox |
| 3 | Hook 设为**可选**（v3 再做），v1 靠 `zrouter scan --check` 在 session 开始自检 | 简化分发与跨平台 |
| 4 | 在 SKILL.md 中明示「想知道文件大致内容时**优先** `Bash("zrouter query <path> --json")`，再决定要不要 `Read`」 | AI 主动调用 CLI 是头等公民 |
| 5 | `src`/`lib`/`app` 等透明目录默认并入父节点；但已有 CLAUDE.md 优先 | 避免无意义中间跳转，同时不隐藏用户已经写好的 scoped context |
| 6 | 忽略规则使用 `exclude` / `allow` 两组 gitignore-ish pattern | 同一套语法覆盖目录、路径和文件扩展；`allow` 覆盖 `exclude` |
| 7 | 默认读取项目根 `.gitignore` 的支持子集 | 普通规则追加到 `exclude`，`!` 追加到 `allow`；不支持的复杂语法跳过 |
| 8 | 小子树默认内联到父级 `zr:files` | `inline_max_files` 默认 12；超过阈值才创建/保留子目录路由节点，减少 CLAUDE.md 中转读取 |
| 9 | `transparent_dirs` 支持 `!name` / `!*` 移除默认项 | 透明目录只把直属文件提升到父级；其子目录继续按 `inline_max_files` 判断，避免整棵源码树被吞进根索引 |
| 10 | 更新 `CLAUDE.md` 使用 atomic write | 先写同目录临时文件，再 rename 覆盖，避免刷新中断导致文件半写坏 |
| 11 | 命令输出过滤从极简起步，可渐进扩展 | v1 只做 `strip_lines_matching`，内嵌 anyzig 等自身工具链的降噪规则；长期可发展为一站式方案。**Hook 始终可关闭**：过滤 hook 默认不安装，用户手动启用；可随时卸载，不影响其他 hook |
| 12 | `desc` 支持 detail mode，但 `refresh` 只用 summary | 支持语言在 CLAUDE.md 中显式记录；`query --detail=outline` 输出「文件头说明注释 + 顶层结构骨架」，不包含函数级注释 |

---

## 3. Prompt vs Zig 职责切分

| 能力 | 实现 | 理由 |
|---|---|---|
| **命令输出过滤（`pipe`）** | **Zig** | 内嵌 TOML 规则；v1 支持 `strip_lines_matching`，渐进扩展；hook 可选安装 |
| 项目初始化、栈检测、模板生成 | Skill | 一次性、需 LLM 适配 |
| 子目录 / 根 CLAUDE.md 模板 | Skill | 内容写作 |
| 路由表 (Context Routing) | Zig 生成 + Skill 写入位置 | IO 由 Zig，插入由 prompt |
| **anatomy 扫描（描述 + token）** | **Zig** | 重 IO + 多语言模式匹配 |
| **`## Files` 标记块替换** | **Zig** | 解析 markdown、保留人写部分 |
| 增量更新（hook） | Zig（可选阶段） | 性能敏感 |
| `.memory/*.md` 写入 | Skill | LLM 写最自然 |
| 审计建议 | Skill 调 Zig 取数据 | 数据 Zig 出，判断 prompt 做 |
| 节省报告 | Zig (`savings --json`) | 纯算术，输出给 LLM 解读 |
| rtk read 类代码读取压缩 | 暂不进核心 | 这是即时内容压缩，不是持久目录路由；可在 `query` 增强后再评估 |
| Cerebrum / Dashboard / Bug log / Design QC / Reframe | **不做** | OpenWolf/omni 的延伸功能，先聚焦核心 |

---

## 4. 产物目录结构

```
project/
├── CLAUDE.md                         # 根 (~200 tok)：Stack / Rules / Operating Instructions / Routing
├── .zrouter/                         # Phase 1+ 才出现
│   └── config.toml                   # 项目级配置，格式同全局 config.toml
├── .memory/
│   ├── decisions.md                  # ADR + 反模式段（含 Do-Not-Repeat）
│   ├── patterns.md
│   └── inbox.md
├── CLAUDE.md                         # routing 可直接指向 src/api/，不必经过 src/
└── src/                              # 默认 transparent dir，不强制生成 CLAUDE.md
    └── api/
        ├── CLAUDE.md
        │   ├ Purpose / Conventions / Gotchas（自定义内容）
        │   └ <!-- zr:files -->
        │       - `foo.zig` — pub fn init,run (~180 tok)
        │       - `bar.zig` — Express router (~520 tok)
        │     <!-- /zr:files -->
```

Phase 0 不创建 `.zrouter/`，因为没有读它的代码。

**`<!-- zr:files -->` 块规则**：
- 标记之外的内容可自由编辑，工具不动。
- 标记之间的内容由 `zrouter refresh` 全权管理；用户编辑会被覆盖。
- 块内直接文件格式：`` - `<file>` — <desc> (~<n> tok) ``；内联子目录用 `` - `<dir>/` `` 分组，子项缩进两格。

---

## 5. Zig CLI 命令规划

**用户面：**

```
zrouter init                                 检测栈、问 user Rules、生成所有骨架文件
zrouter deinit                               移除 ./CLAUDE.md 中的 zr:files 和 zr:routing 块（init 的逆操作）
zrouter deinit -r                            递归处理所有子目录 CLAUDE.md
zrouter deinit -r --delete-file             根目录 CLAUDE.md 只移除 zr: 块；子目录 CLAUDE.md 整个删除
zrouter check [--json]                       read-only 健康报告：过期、超 budget、缺失、孤立
```

**Claude 内部调用（用户看不见，Bash 调）：**

```
zrouter refresh [<dir>] [--json]             刷新单个目录的 zr:files / zr:routing 块
zrouter refresh [<dir>] -r [--create] [--json]  递归刷新；--create 自动为有意义的非透明目录补 CLAUDE.md
zrouter query <path> [--json]                查询单文件描述+token，或目录的过滤后 files/routes/inline_dirs 索引，用于读前判断
zrouter query <path> --detail=outline        查询支持语言的文件头说明注释 + 代码骨架；不含函数级注释，Rust 额外输出 impl fn 签名
```

支持语言：
- Summary：Markdown、Zig、TypeScript/JavaScript、Python、Go、Rust、C/C++/Objective-C、Java、Ruby、Shell、JSON/TOML/YAML，以及通用头部注释回退。
- Outline：Zig、TypeScript/JavaScript、Python、Go、Rust、C/C++/Objective-C、Java、Ruby、Shell、JSON/TOML/YAML、Markdown heading。未知扩展只保证 token count / header comment，不保证结构。
- Init 时应把当前项目命中的支持情况写入根 CLAUDE.md：支持的语言建议 `query --outline` 作为读前步骤；不支持的语言不要鼓励 outline。

**Phase 3 hook（可选）：**

```
zrouter hook pre-read|post-write|...         Claude Code hook 入口
```

所有命令支持 `--json`。Phase 0 没二进制时，Claude 直接编辑 markdown 落地等价行为；Phase 1 后 Claude 改成 `Bash("zrouter refresh <dir>")` 提速。

---

## 6. Zig 实现关键模块

| 文件 | 职责 |
|---|---|
| `walker.zig` | 文件遍历、目录 routing 发现、`refresh -r --create` 候选目录发现；`exclude`/`allow` gitignore-ish pattern 匹配，`transparent_dirs` 路由穿透；按 `inline_max_files` 内联小子树；跳过 >1 MiB |
| `desc.zig` | 描述提取入口与 mode 分发：`summary` 用于索引，`outline` 用于读前细看；`known_files` 兜底 |
| `desc/*.zig` | 分语言 parser：Zig/TS/JS/Python/Go/Rust/C-family/Java/Ruby/Shell/JSON/TOML/YAML；outline 输出文件头注释 + 代码骨架，不输出函数级注释；Rust 避免 `ABC_attr_xx` 式扁平名称 |
| `config.zig` | 三层配置合并：embedded `default.toml` → global → project；token 系数、透明目录、`inline_max_files`、`respect_gitignore`、exclude/allow 和 `.gitignore` 导入 |
| `claude_md.zig` | 解析 `<!-- zr:files -->` / `<!-- zr:routing -->` 标记，**只替换块内**，块外自定义内容不动 |
| `main.zig` | CLI 入口：`init` / `refresh` / `deinit` / `query` 命令调度 |
| hook runtime (v3) | 读 stdin JSON、查 anatomy、写 stderr 警告，目标 <50ms |

---

## 7. 实施阶段

### Phase 0 — Skill 先行 ✅ 完成
- `skill/SKILL.md`：用户命令 (init/check) + 自动行为规约 + 标记块所有权
- `skill/templates.md`：根/子目录 CLAUDE.md、`.memory/` 三件套
- 已 dogfood 落到本仓库（greenfield 模式，仅 root + `.memory/`）

### Phase 1 — Zig CLI MVP ✅ 完成
- `init` / `refresh` / `query` 三个命令，全部支持 `--json`
- `desc.zig` + `desc/*.zig`：Zig / TS/JS / Python / Go / Rust / C-family / Java / Ruby / Shell / JSON / TOML / YAML + 通用注释回退；支持 `summary` / `outline` 两档提取
- `query --detail=outline` / `--outline`：单文件详细模式；生成「文件头说明注释 + 顶层结构骨架」，不包含函数级注释；`refresh` 仍只写一行 summary，避免 files block 膨胀
- `init` 写根 CLAUDE.md 时增加 Supported Extraction 小节，按检测到的项目语言标注 summary/outline 是否支持；不支持的语言只提示 query 可给 token/header comment，不建议 outline。
- `claude_md.zig`：仅替换 `<!-- zr:files -->` / `<!-- zr:routing -->` 块内，块外自定义内容不动
- 三层配置合并：embedded `src/assets/default.toml` → 全局 config.toml → `.zrouter/config.toml`
- 配置字段：`exclude` / `allow` / `transparent_dirs` / `known_files` / `token_coefficient` / `max_content_size` / `inline_max_files` / `respect_gitignore`；尚未发布，不保留旧配置字段
- `refresh -r --create`：递归刷新全部已有 CLAUDE.md，并自动为超过 `inline_max_files` 的非透明目录创建 CLAUDE.md；小子树内联到父级 files block；`src` 等透明目录本身不创建，子目录提升到父级 routing
- 透明目录的直属文件可提升到父级，但透明目录的子目录不再随父透明目录整棵内联；如果透明目录直属文件让父索引过大，应为该透明目录创建 CLAUDE.md 或用 `transparent_dirs = ["!name"]` 取消透明。
- `deinit [<dir>] [-r] [--delete-file]`：移除 zr: 块，保留人工内容；`--delete-file` 使子目录 CLAUDE.md 整个删除（根目录始终只移除块）
- `known_files` 只收录内容不透明的文件（JSON / lock / TOML 等）；名字自说明的文件（Makefile、Dockerfile、README.md 等）靠自动提取或文件名本身

### Phase 2 — 硬化与健康检查
- 为 `walker.zig`、`claude_md.zig`、`desc.zig` 增加实际单元测试，覆盖 ignore/allow、路径规范化、标记块替换、描述提取。
- `refresh` / `init` / `deinit` 写 `CLAUDE.md` 时改为 atomic write：同目录临时文件写完整后 rename 覆盖。
- `check`：read-only 健康报告，支持文本和 `--json`。
  - 缺失：没有 `CLAUDE.md`、没有 `zr:files` / `zr:routing` 标记块。
  - 孤立：routing 指向不存在的子目录 `CLAUDE.md`。
  - 过期：索引中的文件不存在，或新增文件未出现在当前目录索引。
  - 噪音：索引里出现明显缓存、生成物、fixtures、大文件、references 等路径。
  - 预算：块外人工内容估算 token 超过建议值；只提示，不自动删内容。
- 不自带 `--fix`；用户看完报告自行决定要不要让 Claude 修。

### Phase 3 — Hook 集成（可选）
- `hook post-write`：写后增量更新对应 `<!-- zr:files -->` 块，这是最贴近 zrouter 核心的 hook。
- `hook pre-read`：只做轻提示，例如提醒先看当前 `zr:files` 或运行 `zrouter query`；不拦截、不改写 Read。
- 借鉴 rtk 的 hook 安装经验：幂等、可卸载、保留第三方 hook、备份设置文件、失败时不阻断宿主工具。
- 提供 `claude/settings.json` 注册示例；Codex/其他 agent 先文档化，不急着做完整安装器。

### Phase 4 — 选配
- 多语言扩展（更多 `desc_extractor` case）
- CI 友好：`check` 在过期时非零退出
- benchmark 命令

---

## 8. SKILL.md 关键指令

具体内容以 `skill/SKILL.md` 为准。核心点：
1. 用户面只有 `init` 和 `check` 两个命令；其他都是 Claude 编辑代码时的自动行为。
2. 读陌生文件前先看已加载/当前目录的 `<!-- zr:files -->` 块；只有周围 CLAUDE.md 未加载或文件在当前路由上下文外时，才用 `zrouter query <path> --json`。
3. 编辑后自动刷新对应目录的 files/routing 块；需要重建层级时用 `zrouter refresh <dir> -r --create`。
4. bootstrap 后先审生成的 `zr:files` 是否合理；若出现生成物、fixtures、缓存、大数据等噪音，先建议补 `.gitignore` 或 zrouter `exclude`/`allow`，刷新后再写 Purpose/Conventions。
5. 体积 budget：根 ≤250 tok（不含 routing），子目录 ≤300 tok（不含 files 块）。
6. 标记块（`<!-- zr:files -->` / `<!-- zr:routing -->`）由工具管，块外自定义内容不动。
7. routing 遇到 `transparent_dirs`（默认 `src`/`lib`/`app`/`pkg`/`cmd`/`internal`）时穿透，直接链接子目录 CLAUDE.md；小子树按 `inline_max_files` 内联。

---

## 9. 配置设计（已定）

配置三层合并：embedded `default.toml` → 全局 config.toml → `.zrouter/config.toml`。

全局 config.toml 查找顺序：Linux/BSD 优先 `$XDG_CONFIG_HOME/zrouter/config.toml`，Windows 优先 `%APPDATA%\\zrouter\\config.toml`，macOS 支持 `~/Library/Application Support/zrouter/config.toml`，最后回退 `~/.config/zrouter/config.toml`。
列表字段跨层累加（exclude 取并集，known_files 高优先层 prepend），标量字段后层覆盖。`transparent_dirs` 额外支持 `!name` 删除默认项、`!*` 清空后重设。

| 字段 | 类型 | 语义 |
|------|------|------|
| `token_coefficient` | f64 | chars / coefficient ≈ token 数 |
| `max_content_size` | u32 | 每文件最大读取字节数 |
| `inline_max_files` | u32 | 小子树内联阈值；过滤后递归文件数不超过该值则内联到父级 |
| `respect_gitignore` | bool | 是否读取项目根 `.gitignore` 支持子集并追加到 `exclude`/`allow` |
| `exclude` | []string | gitignore-ish 忽略规则：目录、路径、文件扩展统一匹配 |
| `allow` | []string | gitignore-ish 允许规则；命中后覆盖 `exclude` |
| `transparent_dirs` | []string | routing 透明目录名；没有 CLAUDE.md 时文件内联到父级、子目录提升到父级；支持 `!name`/`!*` 移除默认项 |
| `known_files` | [{name,desc}] | 已知文件描述，同名后层覆盖前层 |

`exclude` / `allow` 支持的子集：
- `foo/`：任意层级名为 `foo` 的目录
- `/foo/`：refresh root 下的 `foo` 目录
- `a/b/`：任意层级的 `a/b` 路径片段
- `*.py[co]`：`*` / `?` / `[abc]` / `[a-z]` / `[!a-z]` 字符类
- `**`：跨路径段匹配；zrouter config 与 root `.gitignore` 导入都支持

```toml
# 默认读取 .gitignore；可关闭
respect_gitignore = true

# 小子树内联阈值
inline_max_files = 12

# 跳过目录、路径和文件扩展
exclude = ["generated/", "fixtures/", "*.dat", "*.py[co]"]

# 允许特定路径或文件（覆盖 exclude）
allow = ["fixtures/keep.json", "schema.db"]

# 透明穿透 source/；可用 !src 移除默认 src，或 !* 清空默认集合
transparent_dirs = ["!src", "source"]
```

## 10. 开放问题

- `--json` 输出 schema：要不要稳定化（加版本号）？倾向加。
- `deinit` 后父目录 routing 块仍含已删除子目录的条目，需手动运行 `zrouter refresh <parent>`；是否加 `--refresh-parent` 选项待定。
- Windows 路径：路径分隔符规范化（`\` → `/`）已在 v1 修复；`--json` 输出路径统一用 `/`。
- 是否增加 `zrouter read`：先不做。rtk read 的核心是语言感知代码压缩（去注释、保留签名、截断窗口），实现不算难，但语义上会把 zrouter 从“地图”扩成“读取代理”。若未来做，应作为独立可选命令，不改变 `refresh/query` 的核心模型。
- 是否增加 `--detail=docs` / `--detail=full-outline`：待定。函数级 doc comment 不进入默认 `outline`，否则 token 容易膨胀且注释质量不稳定；若做，只提取 public/top-level symbol 的紧邻 doc comment。
- 是否做一站式集成 rtk/omni：倾向不内置。更合理的是在 `doctor/check` 中检测到 rtk/omni 时给出协作建议；zrouter 自己只保证代码地图稳定。

---

## 11. rtk / omni 探索结论

- rtk 的强项是命令重写、输出过滤、token 节省统计、hook 安装安全性。可借鉴：atomic write、幂等安装、权限/exit-code contract、missed-savings 报告。
- omni 的强项是 PostToolUse 后处理、RewindStore、session hot files、doctor。可借鉴：健康诊断、可恢复原始信息、session 上下文提示。
- `zrouter pipe --cmd <cmd>` 做行过滤：内嵌规则 (`src/assets/filters.toml`) 处理自身工具链噪声，用户可扩展到 `.zrouter/filters.toml`。v1 仅支持 `strip_lines_matching`；后续可渐进加入 replace、max_lines、keep_lines 等，逐步向一站式方案演进。
- 与 rtk/omni 的关系：短期可并用（zrouter 管代码库地图，rtk/omni 管命令降噪）；长期若 `zrouter pipe` 功能足够，用户可单独使用 zrouter。
- **Hook 可选**：过滤 hook 默认不安装，用户手动 `zrouter hook install` 启用；`zrouter hook uninstall` 随时卸载；不干扰其他已有 hook。

---

## 12. 参考

- HAM SKILL：`references/ham/SKILL.md`
- HAM templates：`references/ham/templates.md`
- OpenWolf anatomy scanner：`references/openwolf/src/scanner/anatomy-scanner.ts`
- OpenWolf description extractor：`references/openwolf/src/scanner/description-extractor.ts`
- OpenWolf hooks：`references/openwolf/src/hooks/`
- rtk command filtering / hook：`references/rtk/src/cmds/system/read.rs`、`references/rtk/src/hooks/`
- omni pipeline / doctor：`references/omni/src/pipeline/`、`references/omni/src/cli/doctor.rs`
