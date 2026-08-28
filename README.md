# GitHub Copilot Subagents

本儲存庫提供安裝到 GitHub Copilot CLI 個人環境的 subagent skills。目前僅支援 Windows，安裝與驗證必須使用 PowerShell 7 或更新版本。

## Luna Subagents

`luna-subagents` 會在執行型任務含有至少一個可獨立執行、邊界明確且可驗收的子任務時啟用，要求主代理先把至少一個合格子任務交給獨立 executor，再繼續處理或整合結果。

executor 固定使用：

- Model：`gpt-5.6-luna`
- Reasoning effort：`max`
- Agent：`luna-subagents-executor`

每個 executor 只處理一個有界任務，不得再委派，並以 `COMPLETE` 或 `BLOCKED` 回報交付物、變更、驗證、阻擋與範圍外事項。


### 安裝

預設安裝位置位於 `$HOME\.copilot`：

- skill：`$HOME\.copilot\skills\luna-subagents`
- executor：`$HOME\.copilot\agents\luna-subagents-executor.agent.md`
- 全域 instructions：在 `$HOME\.copilot\copilot-instructions.md` 維護有明確 markers 的 managed section

既有的其他全域 instructions 會保留。請在 PowerShell 7 或更新版本，從儲存庫根目錄執行：

```powershell
.\Skills\luna-subagents\scripts\install.ps1
```

若要使用自訂 Copilot home：

```powershell
.\Skills\luna-subagents\scripts\install.ps1 -CopilotHome 'D:\copilot-home'
```

安裝後在既有 CLI session 執行 `/skills reload`，並重新啟動 Copilot CLI 或開始新 session，讓 custom agent 與全域 instructions 生效。

### 驗證與更新

在 PowerShell 7 或更新版本執行：

```powershell
.\Skills\luna-subagents\scripts\install.ps1 -Action Verify
```

自訂 Copilot home 的驗證方式：

```powershell
.\Skills\luna-subagents\scripts\install.ps1 -Action Verify -CopilotHome 'D:\copilot-home'
```

驗證會比對已安裝的 skill 與 executor，並確認全域 managed section 完整且未被修改。更新時拉取新版儲存庫後重新執行安裝命令；安裝流程可安全重複執行，不會重複加入 managed section，並會清除受管理目錄中的額外或過時檔案及舊 executor profiles。

### 使用

符合觸發條件時，skill 會依 `SKILL.md` 的 description 自動載入。也可以明確要求：

```text
使用 /luna-subagents，完成這個功能並驗證。
```

為兼容 Codex 原版提示，skill 也辨識 `$luna-subagents`。

若 executor、`gpt-5.6-luna` 或 `max` 在目前 Copilot runtime 不可用，skill 會回報 `BLOCKED`，不會改用其他模型、effort、agent 或由主代理 fallback 代做。

### 安裝器安全邊界

- 不讀取或修改 GitHub／Copilot 認證。
- 不修改 permissions、MCP、模型預設值或其他 Copilot settings。
- 只安裝 `luna-subagents` skill、對應 executor，以及有明確 begin/end markers 的全域 instructions 區塊。
- 不會沿著受管理路徑中的 junction 或其他 reparse point 寫入。
- 若 markers 破損、重複、巢狀或順序錯誤，安裝會停止並要求人工處理，不猜測覆寫。
