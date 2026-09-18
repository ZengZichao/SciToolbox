# Changelog

All notable changes are documented here. Format based on [Keep a Changelog](https://keepachangelog.com/); this project adheres to [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] — current（Mac App Store 首发）

面向 Mac App Store 的全新首发版本。聚合 15 个公开学术数据库，一站式检索生命科学文献与数据。

### 新增
- **15 个数据源**：UniProt、RCSB PDB、AlphaFold、PubMed、NCBI Taxonomy、NCBI Gene、Ensembl、KEGG、GO（QuickGO）、Pfam/InterPro、BacDive、MGnify、GBIF、Europe PMC、GTDB 官方分类。
- **三栏工作区**：侧边栏（按分类组织）→ 搜索与结果 → 详情；每栏可调宽。
- **全库搜索**：一个关键词并行检索全部数据库，结果按五大分类分组，单库失败不影响其他库。
- **Accession 智能识别**：粘贴 UniProt / PDB / 基因符号 / DOI / GO / Ensembl / Pfam / KEGG / TaxID 自动路由到对应数据库；歧义时弹窗选择。
- **跨库互链**：详情页在 UniProt ↔ PDB / Pfam / GO / PubMed / Ensembl / AlphaFold 之间双向跳转，⌘ 点击仅预览不离开当前列表。
- **检索护栏**：15s 超时、指数退避重试（尊重 429 Retry-After）、NCBI 3 秒节流、磁盘 TTL 缓存（异步 IO）、离线横幅提示。
- **项目集合**：把相关条目组织成课题，支持备注、批量核对 / 重新拉取、CSV / JSON 导出。
- **收藏与历史**：纯本地存储，支持导出（文本 / JSON）、批量操作、可撤销删除。
- **引用导出**：BibTeX / RIS / FASTA；CSV 遵循 RFC 4180 转义。
- **中英文双语**：设置内一键切换，即时生效；相对时间、无障碍标签同步本地化。
- **全新品牌视觉**：六边形科研网络 × DNA 双螺旋标志（App 图标 / 详情展示两套变体），遵循 macOS 图标规范（不透明、圆形安全区内）。

### 修复
- 修复 PDB 检索分页字段错误导致整个库 400 不可用的问题。
- 修复 GO 术语详情「名称 / 定义 / 祖先 / 子节点」全部为空的问题。
- 修复 UniProt 审核状态误标（所有条目被标为「未审核」）。
- 修复 Ensembl 染色体 / 位置 / 链 / 长度字段缺失、「链」恒显示 0。
- 修复「加载更多」翻页偏移错误导致的静默丢页。
- 修复结果高亮在命中位于串尾时重复整段文本。
- 修复 4 位纯数字（TaxID / PMID）被误路由到 PDB。
- 修复导出保存失败仍提示「已导出」的静默失败。
- 修复集合行悬停状态被全局共享、多选「全选 / 取消全选」标签相反等交互缺陷。
- 修复测试护栏失效（fixture 路径错误导致全部用例静默跳过），6 个用例恢复真实执行。

### 无障碍与视觉
- 对比度全面达标：焦点环、按钮、次级正文、分类色与语义色在浅 / 深色模式下均满足 WCAG AA。
- 卡片 / 侧边栏 / 分割线建立明确视觉层级；Reduce Motion、VoiceOver 选中态补齐。

---

## Archived —— App Store 之前的历史版本（仅存档，不对外呈现）

### [1.13.0]

#### Fixed
- **集合功能全量本地化**：项目集合（列表 / 详情 / 批量核对 / 加入集合弹窗，约 40 处文案）此前为硬编码中文，现全部接入 `L10n` 双语表，随界面语言切换。跨库对比的提示 Toast、表头字段（名称 / 来源库 / 分类 / 物种描述）与空态同样补齐。
- **语言切换即时生效**：主窗口现已观察 `AppLanguage`，在设置中切换语言后侧边栏、搜索、详情、收藏、集合等界面文本立即刷新，无需重启应用。
- **零散文案**：全库搜索命中数「N 条 / N hits」、结果内筛选清除、首页重新查询 / 打开收藏 / 分类浏览的 VoiceOver 标签、Toast 撤销提示等辅助功能文本一并本地化。

#### Changed
- **禁用态视觉反馈**：全局 `PressableButtonStyle` 增加禁用变暗（35% 不透明度），此前自定义样式的按钮在禁用时无任何视觉区分（如「创建并加入」「开始核对」）。
- **破坏性操作配色统一**：收藏夹 / 历史页「清空」按钮由临时 `.red.opacity(0.7)` 改为设计系统 `semanticError` 色。
- **集合行交互**：集合列表整行可点击打开（此前仅右侧小箭头），并新增与结果行一致的 hover 高亮。
- 版本号升至 1.13.0（`Info.plist`、设置页「关于」、`CITATION.cff`）。

### [1.12.0]

#### Added
- **Bilingual UI (Chinese / English)**: full app localization with a language switcher in Settings. All sidebar, search, detail, favorites, collections, and settings text are localized. Relative timestamps (e.g. "3 minutes ago" / "3小时前") follow the selected language. Preference is persisted via `UserDefaults`.
- `Localization.swift`: `AppLanguage` (ObservableObject) manages the current language and broadcasts changes via `NotificationCenter`; `L10n` enum provides a unified string-lookup table for all UI text.
- Non-MainActor-safe language access (`currentLang`, `currentLocale`) for use in model types like `SearchHistory`, `LocalFavorites`, `CollectionStore`, `RankName`, and `GTDBRank`.

### [1.11.0]

Highlights:
- Cross-database side-by-side comparison (max 4 entries).
- Cross-database field alignment in the `DetailModel` layer.
- Batch verification / re-fetch with per-item status and a progress bar.
- UI polish: NCBI gene/sequence icon fix, Home header adjustments, sidebar refinements.

> Version history before 1.11.0 was tracked informally.