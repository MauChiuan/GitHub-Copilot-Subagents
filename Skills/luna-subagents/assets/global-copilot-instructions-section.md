<!-- BEGIN luna-subagents managed section -->
## Luna subagent 委派

當執行型任務含至少一個可獨立執行、邊界明確且可驗收的子任務，或明確呼叫 `/luna-subagents`、`$luna-subagents` 時，主代理必須先完整載入並實際使用 `luna-subagents` Skill 的 GitHub Copilot subagent。

這是阻斷式 pre-spawn contract：在讀取、搜尋、測試、修改或以其他工具處理合格子任務前，主代理必須成功啟動 Skill 指定的 executor；否則立即回報 `BLOCKED`，不得由主代理 fallback 代做。
<!-- END luna-subagents managed section -->
