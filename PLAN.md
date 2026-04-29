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
| 9 | `transparent_dirs` 支持 `!name` / `!*` 移除默认项 | 保持列表 append 语义，同时允许项目覆盖默认透明目录集合 |

---

## 3. Prompt vs Zig 职责切分

| 能力 | 实现 | 理由 |
|---|---|---|
| 项目初始化、栈检测、模板生成 | Skill | 一次性、需 LLM 适配 |
| 子目录 / 根 CLAUDE.md 模板 | Skill | 内容写作 |
| 路由表 (Context Routing) | Zig 生成 + Skill 写入位置 | IO 由 Zig，插入由 prompt |
| **anatomy 扫描（描述 + token）** | **Zig** | 重 IO + 多语言模式匹配 |
| **`## Files` 标记块替换** | **Zig** | 解析 markdown、保留人写部分 |
| 增量更新（hook） | Zig（可选阶段） | 性能敏感 |
| `.memory/*.md` 写入 | Skill | LLM 写最自然 |
| 审计建议 | Skill 调 Zig 取数据 | 数据 Zig 出，判断 prompt 做 |
| 节省报告 | Zig (`savings --json`) | 纯算术，输出给 LLM 解读 |
| Cerebrum / Dashboard / Bug log / Design QC / Reframe | **不做** | OpenWolf 的延伸功能，先聚焦核心 |

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
```

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
| `desc.zig` | 语言特化描述提取：Zig/TS/JS/Python/Go/Rust + 通用注释回退；Rust 支持 `impl`/`pub use`，Python 支持模块级 FFI 赋值；`known_files` 兜底 |
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
- `desc.zig`：Zig / TS/JS / Python / Go / Rust + 通用注释回退
- `claude_md.zig`：仅替换 `<!-- zr:files -->` / `<!-- zr:routing -->` 块内，块外自定义内容不动
- 三层配置合并：embedded `src/assets/default.toml` → 全局 config.toml → `.zrouter/config.toml`
- 配置字段：`exclude` / `allow` / `transparent_dirs` / `known_files` / `token_coefficient` / `max_content_size` / `inline_max_files` / `respect_gitignore`；尚未发布，不保留旧配置字段
- `refresh -r --create`：递归刷新全部已有 CLAUDE.md，并自动为超过 `inline_max_files` 的非透明目录创建 CLAUDE.md；小子树内联到父级 files block；`src` 等透明目录本身不创建，子目录提升到父级 routing
- `deinit [<dir>] [-r] [--delete-file]`：移除 zr: 块，保留人工内容；`--delete-file` 使子目录 CLAUDE.md 整个删除（根目录始终只移除块）
- `known_files` 只收录内容不透明的文件（JSON / lock / TOML 等）；名字自说明的文件（Makefile、Dockerfile、README.md 等）靠自动提取或文件名本身

### Phase 2 — 健康检查
- `check`：过期 / 超 budget / 缺失 / 孤立，read-only JSON 输出
- 不自带 `--fix`；用户看完报告自行决定要不要让 Claude 修

### Phase 3 — Hook 集成（可选）
- `hook pre-read`：重复读警告 + 块查询提示
- `hook post-write`：写后增量更新对应 `<!-- zr:files -->` 块
- 提供 `claude/settings.json` 注册示例

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

---

## 10. 参考

- HAM SKILL：`references/ham/SKILL.md`
- HAM templates：`references/ham/templates.md`
- OpenWolf anatomy scanner：`references/openwolf/src/scanner/anatomy-scanner.ts`
- OpenWolf description extractor：`references/openwolf/src/scanner/description-extractor.ts`
- OpenWolf hooks：`references/openwolf/src/hooks/`
