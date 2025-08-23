#Requires AutoHotkey v2.0
#SingleInstance Force

; === 自動提權（永遠以系統管理員執行） ===
if !A_IsAdmin {
    try {
        Run '*RunAs "' A_ScriptFullPath '"'
    } catch as e {
        MsgBox "需要系統管理員權限才能調整亮度喵~`n請改用「以系統管理員身分執行」。`n`n錯誤：" e.Message
    }
    ExitApp
}

; === 可調區 ===
siteKeys := ["Netflix", "動畫瘋"] ; 目標網站標題片段(可自行修改)
dim      := 1                     ; 命中時亮度（%）
normal   := 100                   ; 其他情況亮度（%）
useZero  := false                 ; true=允許 0%，false=最小用 dim(部分筆電不支援)
interval := 300                   ; 檢查間隔（毫秒）

prevState := ""
paused    := false
SetTimer(Check, interval)

Check() {
    global siteKeys, dim, normal, useZero, prevState
    h := WinExist("A")
    if !h
        return
    title := WinGetTitle("ahk_id " h)
    proc  := WinGetProcessName("ahk_id " h)

    match := false
    if (proc ~= "i)msedge.exe") {
        for key in siteKeys {
            if InStr(title, key) {
                match := true
                break
            }
        }
    }

    state := match ? "dim" : "normal"
    if (state != prevState) {
        SetBrightness(state = "dim" ? (useZero ? 0 : dim) : normal)
        prevState := state
    }
}

SetBrightness(pct) {
    pct := pct<0?0 : pct>100?100:pct
    RunWait Format(
        'powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1,{1})"', pct
    ), , "Hide"
}

; === 熱鍵 ===
^!Up::{      ; Ctrl+Alt+↑：恢復 normal
    global normal
    SetBrightness(normal)
}
^!Down::{    ; Ctrl+Alt+↓：最暗（依 useZero）
    global dim, useZero
    SetBrightness(useZero ? 0 : dim)
}
^!P::{       ; Ctrl+Alt+P：暫停/恢復
    global paused, interval
    paused := !paused
    SetTimer(Check, paused ? 0 : interval)
    TrayTip "DimOnSite", paused ? "已暫停" : "已恢復", 1
}

OnExit(*) => (SetBrightness(normal))
