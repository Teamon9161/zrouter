# zrouter 设计与实施计划

零依赖 CLI + Skill 的混合方案，结合 [HAM](references/ham/) 的层级路由与 [OpenWolf](references/openwolf/) 的文件 anatomy，以最小代价为 Claude Code 节省 token。

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
│   └── config.json                   # 项目级 exclude_patterns、token 系数（v1 引入）
├── .memory/
│   ├── decisions.md                  # ADR + 反模式段（含 Do-Not-Repeat）
│   ├── patterns.md
│   └── inbox.md
└── src/
    ├── CLAUDE.md
    │   ├ Purpose / Conventions / Gotchas（人类编辑）
    │   └ <!-- zr:files -->
    │       - `foo.zig` — pub fn init,run (~180 tok)
    │       - `bar.zig` — Express router (~520 tok)
    │     <!-- /zr:files -->
    └── api/
        └── CLAUDE.md
```

Phase 0 不创建 `.zrouter/`，因为没有读它的代码。

**`<!-- zr:files -->` 块规则**：
- 标记之外的内容由人类（或 Claude）自由编辑，工具不动。
- 标记之间的内容由 `zrouter refresh` 全权管理；用户编辑会被覆盖。
- 块内每行格式：`` - `<file>` — <desc> (~<n> tok) ``。

---

## 5. Zig CLI 命令规划

**用户面（只有这两个）：**

```
zrouter init                                 检测栈、问 user Rules、生成所有骨架文件
zrouter check [--json]                       read-only 健康报告：过期、超 budget、缺失、孤立
```

**Claude 内部调用（用户看不见，Bash 调）：**

```
zrouter refresh [<dir>] [--json]             刷新一个或全部 zr:files / zr:routing 块
zrouter query <file> [--json]                查询单文件描述+token，用于读前判断
```

**Phase 3 hook（可选）：**

```
zrouter hook pre-read|post-write|...         Claude Code hook 入口
```

所有命令支持 `--json`。Phase 0 没二进制时，Claude 直接编辑 markdown 落地等价行为；Phase 1 后 Claude 改成 `Bash("zrouter refresh <dir>")` 提速。

---

## 6. Zig 实现关键模块

| 模块 | 职责 |
|---|---|
| `fs_walker` | 递归遍历，gitignore 风格排除，跳过二进制/>1MB |
| `desc_extractor` | 移植 OpenWolf `description-extractor.ts` 的语言特化逻辑；优先 Zig/TS/JS/Python/Go/Rust，其他语言通用回退（首条有意义注释 / 导出符号） |
| `token_estimator` | 单一系数 chars/4；可在 `.zrouter/config.json` 调 |
| `claude_md_parser` | 解析 `<!-- zr:files -->` 标记，**只替换块内**，保留人类内容 |
| `routing_builder` | 扫所有 `**/CLAUDE.md`（不含根），生成路由表 |
| `hook_runtime` (v3) | 读 stdin JSON、查 anatomy、写 stderr 警告，目标 <50ms |

---

## 7. 实施阶段

### Phase 0 — Skill 先行 ✅ 完成
- `skill/SKILL.md`：用户命令 (init/check) + 自动行为规约 + 标记块所有权
- `skill/templates.md`：根/子目录 CLAUDE.md、`.memory/` 三件套
- 已 dogfood 落到本仓库（greenfield 模式，仅 root + `.memory/`）

### Phase 1 — Zig CLI MVP
- `init` / `refresh` / `query` 三个命令
- `desc_extractor` 先支持 Zig + TS/JS + Python + Go + Rust + 通用回退
- `claude_md_parser`：仅替换 `<!-- zr:files -->` / `<!-- zr:routing -->` 块内
- `.zrouter/config.json` 引入（项目级 exclude_patterns）
- 所有命令支持 `--json`

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
2. 读陌生文件前先看周围 `<!-- zr:files -->` 块（Phase 1 后改 `Bash zrouter query`）。
3. 编辑后自动刷新对应目录的 files 块；增删 CLAUDE.md 自动刷新根 routing 块。
4. 体积 budget：根 ≤250 tok（不含 routing），子目录 ≤300 tok（不含 files 块）。
5. 标记块（`<!-- zr:files -->` / `<!-- zr:routing -->`）由工具管，块外人类管。

---

## 9. 开放问题（实现时再决定）

- `--json` 输出 schema：要不要稳定化（加版本号）？倾向加。
- 项目级排除目录：v1 通过 `.zrouter/config.json` 的 `exclude_patterns`；标准 ignores 已含 `vendor/third_party/external/references` 等通用名。
- Windows 路径：v1 不做，v2 处理。

---

## 10. 参考

- HAM SKILL：`references/ham/SKILL.md`
- HAM templates：`references/ham/templates.md`
- OpenWolf anatomy scanner：`references/openwolf/src/scanner/anatomy-scanner.ts`
- OpenWolf description extractor：`references/openwolf/src/scanner/description-extractor.ts`
- OpenWolf hooks：`references/openwolf/src/hooks/`
