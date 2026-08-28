# GitHub Copilot Subagents

本儲存庫提供安裝到 GitHub Copilot CLI 個人環境的 subagent skills。目前僅支援 Windows。建議使用隨附的 `install.cmd`，它會優先使用 PowerShell 7，並在沒有合格版本時自動改用 Windows PowerShell 5.1。

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

既有的其他全域 instructions 會保留。`install.cmd` 是建議的安裝入口；請在 Windows 命令提示字元或 PowerShell 中，從儲存庫根目錄執行：

```bat
Skills\luna-subagents\scripts\install.cmd
Skills\luna-subagents\scripts\install.cmd -CopilotHome "D:\copilot home"
```

在 PowerShell 中也可以直接使用相同的 launcher：

```powershell
.\Skills\luna-subagents\scripts\install.cmd
.\Skills\luna-subagents\scripts\install.cmd -CopilotHome 'D:\copilot home'
```

安裝後在既有 CLI session 執行 `/skills reload`，並重新啟動 Copilot CLI 或開始新 session，讓 custom agent 與全域 instructions 生效。

### 驗證與更新

建議仍透過 `install.cmd` 執行 verify；它會解析並傳入支援的 `-Action`、`-CopilotHome`、`-WhatIf` 與 `-Confirm` 參數，拒絕重複、缺值或未知參數，並傳回子程序的 exit code：

```bat
Skills\luna-subagents\scripts\install.cmd -Action Verify
Skills\luna-subagents\scripts\install.cmd -Action Verify -CopilotHome "D:\copilot home"
```

launcher 會先尋找 PATH 中的 `pwsh.exe`，只有在版本 major 為 7 或更高時才使用它，並輸出 `LUNA_POWERSHELL_HOST=pwsh`。若找不到合格的 `pwsh`（例如只有 PowerShell 6 或沒有 `pwsh`），就使用 `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe`，並輸出 `LUNA_POWERSHELL_HOST=windows-powershell`。PowerShell 5.0 或更舊版本不受支援。安裝器成功時也會從實際執行環境輸出 `LUNA_POWERSHELL_VERSION=<version>` 與 `LUNA_POWERSHELL_EDITION=Core|Desktop`，方便確認真正使用的 host。

一般不成對的 `%`、`!`、`&`、括號、空白與尾端反斜線可安全傳入。由於 `.cmd` 啟動前會先經過 CMD 解析，形如 `%NAME%` 的文字可能先被當成環境變數展開；路徑若必須保留這類字面序列，請改為從 PowerShell 直接執行 `install.ps1`。

#### 進階／直接使用 `install.ps1`

需要直接控制 host 時，可以在 PowerShell 7 中執行 `install.ps1`：

```powershell
pwsh -NoLogo -NoProfile -File .\Skills\luna-subagents\scripts\install.ps1 -CopilotHome 'D:\copilot home'
```

`install.ps1` 也相容於 Windows PowerShell 5.1：

```powershell
powershell.exe -NoLogo -NoProfile -File .\Skills\luna-subagents\scripts\install.ps1 -Action Verify -CopilotHome 'D:\copilot home'
```

驗證會比對已安裝的 skill 與 executor，並確認全域 managed section 完整且未被修改。更新時拉取新版儲存庫後重新執行安裝命令；安裝流程可安全重複執行，不會重複加入 managed section，並會清除受管理目錄中的額外或過時檔案及舊 executor profiles。

### 使用

符合觸發條件時，skill 會依 `SKILL.md` 的 description 自動載入。也可以明確要求：

```text
使用 /luna-subagents，完成這個功能並驗證。
```

為兼容 Codex 原版提示，skill 也辨識 `$luna-subagents`。

若 executor、`gpt-5.6-luna` 或 `max` 在目前 Copilot runtime 不可用，skill 會回報 `BLOCKED`，不會改用其他模型、effort、agent 或由主代理 fallback 代做。

executor 的設定不指定 `service-tier` 或其他 quota-based routing；安裝器不會選擇或切換配額方案。

### 安裝器安全邊界

- 不讀取或修改 GitHub／Copilot 認證。
- 不修改 permissions、MCP、模型預設值或其他 Copilot settings。
- 只安裝 `luna-subagents` skill、對應 executor，以及有明確 begin/end markers 的全域 instructions 區塊。
- 不會沿著受管理路徑中的 junction 或其他 reparse point 寫入。
- 若 markers 破損、重複、巢狀或順序錯誤，安裝會停止並要求人工處理，不猜測覆寫。
