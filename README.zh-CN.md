<p align="center">
  <img src="assets/logo.svg" width="120" alt="Claude Recall">
  <h1 align="center">Claude Recall</h1>
  <p align="center">
    <strong>自动发现你在 Claude Code 中的重复工作流，一键生成可复用的 Skills。</strong>
  </p>
  <p align="center">
    <a href="README.md">English</a> &bull; <a href="#快速开始">快速开始</a> &bull; <a href="#常见问题">常见问题</a>
  </p>
  <p align="center">
    <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue.svg" alt="License: MIT"></a>
    <a href="https://www.python.org/"><img src="https://img.shields.io/badge/Python-3.8%2B-3776AB.svg" alt="Python 3.8+"></a>
    <a href="https://docs.anthropic.com/en/docs/claude-code"><img src="https://img.shields.io/badge/Claude%20Code-hooks-blueviolet.svg" alt="Claude Code"></a>
  </p>
</p>

---

每天用 Claude Code，部署、调试、重启服务器的流程总是大同小异。**Claude Recall** 在后台默默记录每次工具调用，积累几次会话后自动分析出重复模式，帮你生成可以直接使用的 Skills。

## 工作原理

```
 正常使用 Claude Code
          │
          ▼
 [Hook] log-operations.py 静默记录每次工具调用
          │
          ▼
 积累几次会话后，运行 /analyze-patterns
          │
          ▼
 Python 预分析器压缩日志 → Claude 读取摘要（而非原始日志）
          │
          ▼
 你选择要保存的模式，生成对应的 /skills
          │
          ▼
 新 Skills 写入 ~/.claude/，即装即用
```

**三个组件，零配置负担：**

| 组件 | 功能 |
|------|------|
| `log-operations.py` | **PostToolUse Hook** — 每次工具调用后静默追加一行 JSON 摘要。10 MB 自动轮转。 |
| `pre-analyze.py` | **Python 脚本** — 将原始日志压缩为结构化摘要。相比直接读 JSONL 节省约 80% token。 |
| `analyze-patterns` | **Skill** — 读取预分析摘要，检测在 3+ 个会话中出现的命令/序列/工作流，生成可复用的技能文件。 |

## 快速开始

```bash
git clone https://github.com/zchdu/claude-recall.git
cd claude-recall
./install.sh
```

搞定。正常使用 Claude Code 几次后，运行：

```
/analyze-patterns
```

## 日志记录内容

每次工具调用生成一条紧凑的 JSONL 记录：

```json
{
  "ver": 2,
  "ts": "2026-03-02T09:50:10Z",
  "sid": "e0af7856-2df8-48",
  "tool": "Bash",
  "input": {"command": "npm test", "description": "Run tests"},
  "cwd": "/home/user/my-project",
  "tuid": "toolu_01ABcDeF12",
  "res": {"success": true, "exit_code": 0}
}
```

| 特性 | 说明 |
|------|------|
| **格式** | v2 — 包含工具响应摘要 (`res`) 和工具调用 ID (`tuid`) |
| **截断策略** | 超过 300 字符的字符串只保留首尾，响应摘要最多 500 字符 |
| **自动轮转** | 日志超过 10 MB 时自动保留较新的一半 |
| **存储位置** | `~/.claude/tool_logs/operations.jsonl` |

## `/analyze-patterns` 做了什么

| 步骤 | 说明 |
|------|------|
| **1. 预分析** | Python 脚本将日志压缩为统计数据 + 模式（约 10 KB 摘要） |
| **2. 统计概览** | 总记录数、会话数、工具使用频率 TOP 5、最常见命令和工作目录 |
| **3. 模式检测** | 在 3+ 个会话中寻找重复命令、命令序列（2–3 步）和工作流模式 |
| **4. 建议生成** | 对每个模式给出：名称、出现频率、具体步骤、可参数化部分、现成的 `.md` 技能文件 |
| **5. 一键创建** | 你选择要保存的模式 → 写入 `~/.claude/commands/` → 马上可用 |

## 输出示例

```
=== 预分析摘要 ===
记录: 853 | 会话: 12 | 跨度: 7 天
工具频率: Bash (321, 38%), Read (253, 30%), Edit (124, 15%)
已有技能: restart-dashboard, dashboard-logs

检测到的模式:
  重复命令: `ssh kubao "cd /opt/X && ..."` — 5 个会话
  命令序列: Edit(config) → Bash(cargo build) → Bash(deploy) — 4 个会话

=== 模式: 部署到生产环境 ===
- 重叠度: 无
- 建议操作: 创建新技能
- 频率: 4 个会话
- 步骤: rsync → ssh 重启服务 → tail 查看日志

要保存哪些模式？> 1

✓ 已创建 ~/.claude/commands/deploy-prod.md
  调用方式: /deploy-prod
```

## 手动安装

<details>
<summary>点击展开手动安装步骤</summary>

### 1. 复制文件

```bash
mkdir -p ~/.claude/{hooks,scripts,skills/analyze-patterns}
cp hooks/log-operations.py ~/.claude/hooks/
cp scripts/pre-analyze.py ~/.claude/scripts/
cp skills/analyze-patterns/SKILL.md ~/.claude/skills/analyze-patterns/
chmod +x ~/.claude/hooks/log-operations.py ~/.claude/scripts/pre-analyze.py
```

### 2. 注册 Hook

在 `~/.claude/settings.json` 中添加：

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "python3 $HOME/.claude/hooks/log-operations.py",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

> 如果已有 `hooks` 配置，将 `PostToolUse` 条目合并进去即可。

</details>

## 文件结构

```
~/.claude/
├── hooks/
│   └── log-operations.py       # PostToolUse Hook（v2 格式）
├── scripts/
│   └── pre-analyze.py          # 日志预分析器
├── skills/
│   └── analyze-patterns/
│       └── SKILL.md            # /analyze-patterns skill
├── commands/
│   └── analyze-patterns.md     # 旧版 skill（向后兼容）
├── tool_logs/
│   └── operations.jsonl        # 自动生成的日志
└── settings.json               # Hook 注册配置
```

## 常见问题

<details>
<summary><strong>会拖慢 Claude Code 吗？</strong></summary>

不会。Hook 设有 5 秒超时，实际执行通常在 10 毫秒以内，只是一次 JSON 追加写入。
</details>

<details>
<summary><strong>占多少磁盘空间？</strong></summary>

日志在 10 MB 时自动轮转。正常使用大约每周产生 1 MB。
</details>

<details>
<summary><strong>会记录敏感数据吗？</strong></summary>

文件内容和 diff 截断到 300 字符，工具响应摘要最多 500 字符（仅关键字段）。可以随时查看日志确认。
</details>

<details>
<summary><strong>能只记录特定工具吗？</strong></summary>

可以。修改 `settings.json` 中的 `matcher` 字段，例如 `"matcher": "Bash|Edit"` 只记录 Bash 和 Edit 调用。
</details>

<details>
<summary><strong>已经有 settings.json 怎么办？</strong></summary>

`install.sh` 会检测已有配置并安全合并，不会覆盖你的文件。
</details>

<details>
<summary><strong>如何卸载？</strong></summary>

运行 `./uninstall.sh`，移除所有组件，保留你的其他设置。
</details>

## 环境要求

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)（需支持 hooks 功能）
- Python 3.8+

## 参与贡献

欢迎贡献代码。请参阅 [CONTRIBUTING.md](CONTRIBUTING.md) 了解详情。

## 许可证

[MIT](LICENSE)
