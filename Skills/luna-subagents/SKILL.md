---
name: luna-subagents
description: 執行型任務含至少一個可獨立執行、邊界明確且可驗收的子任務時自動使用本 Skill；主代理必須真正使用 GitHub Copilot subagents，固定使用 GPT-5.6-Luna／max；也可明確呼叫 /luna-subagents 或 $luna-subagents。
license: MIT
---

# Luna Subagents

使用固定為 `gpt-5.6-luna`／`max` 的 executor。本 Skill 只管理有界委派與執行紀律，不繼承其他技能的工作流、記憶、references、代理 IDs 或設定。

## 啟用與必要委派

符合自動啟用條件，或明確呼叫 `/luna-subagents`、`$luna-subagents` 後，主代理必須實際呼叫 Copilot 的 custom-agent/task delegation tool，至少把一個合格子任務交給 `luna-subagents-executor`；只載入 Skill、規劃委派或口頭聲稱已委派都不算使用。主代理保留需求釐清、邊界、排程、整合、最終驗收及確實不可委派的工作。

這是阻斷式 pre-spawn contract：在讀取、搜尋、測試、修改或以其他工具處理任何合格子任務的目標前，主代理必須先載入本 Skill，並成功啟動指定的 Luna executor。此前只可讀取本 Skill、適用的 instructions、使用者要求，以及界定邊界所需且不代做子任務的最小資訊。平行 shell command、一般 tool call 或聲稱已委派都不是 subagent delegation。無法完成 contract 或啟動 executor 時立即回報 `BLOCKED`，不得由主代理 fallback 代做。

## 固定 executor 設定

唯一合法 executor 是 `luna-subagents-executor`。每次呼叫 delegation tool 時都必須明確指定：

```text
agent: luna-subagents-executor
model: gpt-5.6-luna
reasoning_effort: max
```

若目前 Copilot runtime 使用 `agent_type` 作為欄位名稱，將 `luna-subagents-executor` 放入該欄位；若 runtime 將 custom agent 暴露為獨立工具，直接呼叫該工具。無論介面形態為何，完整任務說明必須直接放入該次呼叫，且 `model` 與 `reasoning_effort` 都必須是該次 invocation 的明確參數，不能只依賴 session default、使用者設定或 profile default。

選定的 executor 未安裝、未載入，或 runtime 不接受 `gpt-5.6-luna`／`max` 時回報 `BLOCKED`；不得改用其他 agent、模型、推理強度或主代理直接執行。不得建立 Fast／Standard 分支、quota routing 或 fallback 鏈。

## 主代理職責

1. 讀取適用的 instructions、使用者要求與必要工作區資訊，界定子任務的依賴、所有權、排程與停止條件；只啟動 ready 的子任務，範圍不重疊才可並行。
2. 每個 executor 只接收一個有界任務。派發訊息必須包含目標與交付物、可讀／寫範圍、排除範圍、驗收與驗證、依賴、所有權及必要外部動作；不得要求 executor 再拆分或委派。
3. 每次都使用獨立 subagent context。所有必要上下文放入派發訊息，不得帶入或依賴目前對話歷史，也不得要求 executor 自行尋找對話中未提供的決策。
4. 將完整自然語言任務說明直接放入 tool call，不另行解釋 profile、context 或 task packet。不得自行建立固定 DAG、風險分數、verifier、模型路由或 fallback 鏈。
5. 主代理追蹤所有已啟動 executor，彙整回報、處理跨任務整合，並依全部必要交付物與驗證結果判斷整體任務是否完成。

## Coordinator lifecycle / final sweep

使用同步 delegation 時，等待 executor 回傳 terminal report。只有確有彼此獨立的工作可同時進行時才使用背景 executor；啟動後由主代理繼續其他獨立工作，等待完成通知，再以 runtime 提供的 agent-result tool 讀取完整結果，不以輪詢取代等待。

wait timeout、長時間執行或暫無事件只代表未完成，不得據此宣稱 `BLOCKED`、重複啟動相同任務或由主代理接手。取消、重新規劃、錯誤退出及主 final response 前都執行 final sweep；確認每個 executor 已回傳 terminal report，且沒有仍在 running 的本回合 executor。若 runtime 缺少清理或中斷 API，不得虛構已 teardown；等待可觀察的乾淨終態，或以具體狀態證據回報整體 `BLOCKED`。

## Executor 與結果契約

executor profile 負責強制執行：單一有界任務、較高優先序指示與適用 instructions、最小必要讀取、禁止越界與額外副作用、保留既有修改、禁止 spawn／轉交、實際驗證，以及無法安全完成時回報 `BLOCKED` 且不 fallback。主代理的 task packet 不需重複這些固定規則，但必須提供前述任務邊界。

每個 executor 最終回報：

- `status`: `COMPLETE` 或 `BLOCKED`。
- `completed`: 已完成的交付物。
- `changes`: 修改的檔案、資源或外部目標；沒有變更時明確填寫 `none`。
- `validation`: 實際執行的命令或檢查及其結果；沒有可執行的驗證時說明原因。
- `blockers`: 未完成事項與可重現證據；完成時填寫 `none`。
- `out_of_scope`: 已辨識但未執行的範圍外工作；沒有時填寫 `none`。

只有全部必要交付物與驗證完成時使用 `COMPLETE`；任何必要部分未完成時使用 `BLOCKED`，由主代理決定後續安排。送出 terminal report 後 executor 立即停止所有工具操作與等待。
