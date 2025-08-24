#Requires AutoHotkey v2.0
#SingleInstance Force

; === Admin 提權 ===
if !A_IsAdmin {
    try Run('*RunAs "' A_ScriptFullPath '"')
    catch as e {
        MsgBox("需要系統管理員權限才能調整亮度。`n錯誤：" e.Message)
    }
    ExitApp
}

; === 顏色 / UI 常數 ===
BASE_BG   := "37393f"   ; 主底色（所有非按鈕區域）
ACCENT_BG := "2A2A2A"   ; 橫幅 / 按鈕底色
HOVER_BG  := "4856C0"   ; 按鈕 hover
DOWN_BG   := "3D49A6"   ; 按鈕按下
TXT_FG    := "FFFFFF"

BTN_W := 72, BTN_H := 24
EDIT_OPT := " +Background" BASE_BG " +E0x200 c" TXT_FG  ; 深灰 + 框線 + 白字

; === 狀態 ===
settingsFile := A_ScriptDir "\DimOnSite.ini"
global sites := []      ; {name, enabled}
siteKeys := []          ; 由 sites 生成（只含 enabled）
dim := 1, normal := 100, useZero := false, interval := 300
prevState := "", paused := false

; === 扁平按鈕（hover/press）===
global __BtnMap := Map()  ; hwnd -> {ctl, ox, oy}
global __BtnHover := 0
RegisterBtn(ctrl) {
    global __BtnMap, ACCENT_BG
    ctrl.Opt("Background" ACCENT_BG)
    ctrl.GetPos(&x,&y,,)
    __BtnMap[ctrl.Hwnd] := {ctl: ctrl, ox: x, oy: y}
}
__BtnSkin(hwnd, color, offset:=0) {
    global __BtnMap
    info := __BtnMap.Get(hwnd, 0)
    if !info
        return
    info.ctl.Opt("Background" color)
    info.ctl.Move(info.ox+offset, info.oy+offset)
}
InstallBtnMouseHooks() {
    static installed := false
    if installed
        return
    installed := true
    OnMessage(0x200, __BtnMsg)   ; MouseMove
    OnMessage(0x201, __BtnMsg)   ; LButtonDown
    OnMessage(0x202, __BtnMsg)   ; LButtonUp
}
__BtnMsg(wParam, lParam, msg, hwnd) {
    global __BtnMap, __BtnHover, ACCENT_BG, HOVER_BG, DOWN_BG
    if (msg = 0x200) { ; Move
        if __BtnMap.Has(hwnd) {
            if (__BtnHover != hwnd) {
                if (__BtnHover && __BtnMap.Has(__BtnHover))
                    __BtnSkin(__BtnHover, ACCENT_BG, 0)
                __BtnHover := hwnd
                __BtnSkin(hwnd, HOVER_BG, 0)
            }
        } else if __BtnHover {
            __BtnSkin(__BtnHover, ACCENT_BG, 0)
            __BtnHover := 0
        }
    } else if (msg = 0x201) { ; Down
        if __BtnMap.Has(hwnd)
            __BtnSkin(hwnd, DOWN_BG, 1)
    } else if (msg = 0x202) { ; Up
        if __BtnMap.Has(hwnd)
            __BtnSkin(hwnd, (__BtnHover=hwnd)?HOVER_BG:ACCENT_BG, 0)
    }
}

; === 工具 ===
TryParseInt(val) {
    v := Trim(val)
    return RegExMatch(v, "^\d+$") ? Integer(v) : ""
}
SetBrightness(pct) {
    pct := pct<0?0 : pct>100?100:pct
    RunWait Format(
        'powershell -NoProfile -ExecutionPolicy Bypass -Command "(Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods).WmiSetBrightness(1,{1})"', pct
    ), , "Hide"
}
RefreshSiteKeys() {
    global sites, siteKeys
    arr := []
    for s in sites
        if s.enabled
            arr.Push(s.name)
    siteKeys := arr
}

; === INI 存取 ===
SitesToString() {
    global sites
    s := ""
    for it in sites
        s .= (s ? ", " : "") it.name "|" (it.enabled ? "1" : "0")
    return s
}
StringToSites(str) {
    global sites
    sites := []
    for pair in StrSplit(str, ",") {
        t := Trim(pair)
        if (t = "")
            continue
        p := StrSplit(t, "|")
        nm := Trim(p[1]), en := (p.Length>=2 && p[2]="1")
        if (nm != "")
            sites.Push({name:nm, enabled:en})
    }
    ; 不再加入任何預設網站（保持空清單）
}
SaveSettings() {
    global settingsFile, dim, normal, useZero, interval
    IniWrite(SitesToString(), settingsFile, "DimOnSite", "siteList")
    IniWrite(dim,      settingsFile, "DimOnSite", "dim")
    IniWrite(normal,   settingsFile, "DimOnSite", "normal")
    IniWrite(useZero ? 1 : 0, settingsFile, "DimOnSite", "useZero")
    IniWrite(interval, settingsFile, "DimOnSite", "interval")
}
LoadSettings() {
    global settingsFile, dim, normal, useZero, interval, sites
    if FileExist(settingsFile) {
        sl := IniRead(settingsFile, "DimOnSite", "siteList", "")
        if (sl != "")
            StringToSites(sl)
        else
            sites := []   ; 無預設
        dim     := Integer(IniRead(settingsFile, "DimOnSite", "dim",     dim))
        normal  := Integer(IniRead(settingsFile, "DimOnSite", "normal",  normal))
        useZero := Integer(IniRead(settingsFile, "DimOnSite", "useZero", useZero)) ? true : false
        nInt    := Integer(IniRead(settingsFile, "DimOnSite", "interval", interval))
        if (nInt != interval)
            interval := nInt
    } else {
        sites := []       ; 無預設
    }
    RefreshSiteKeys()
}

; === 自啟動（最高權限） ===
TaskExists() => (RunWait('schtasks /Query /TN "DimOnSite"', , "Hide") = 0)
SetAutoStart(enable:=true) {
    if enable {
        exe := A_AhkPath, args := '"' A_ScriptFullPath '"'
        cmd := Format('schtasks /create /tn "DimOnSite" /tr "\"{1}\" {2}" /sc onlogon /rl HIGHEST /f /ru "{3}"'
                      , exe, args, A_UserName)
    } else {
        cmd := 'schtasks /delete /tn "DimOnSite" /f'
    }
    return RunWait(cmd, , "Hide")
}

; === 自動調亮度 ===
SetTimer(Check, interval)
Check() {
    global siteKeys, dim, normal, useZero, prevState
    h := WinExist("A")
    if !h
        return
    title := WinGetTitle("ahk_id " h)
    proc  := WinGetProcessName("ahk_id " h)

    match := false
    if (proc ~= "i)chrome.exe|msedge.exe|firefox.exe|brave.exe|opera.exe") {
        for key in siteKeys
            if InStr(title, key) {
                match := true
                break
            }
    }
    state := match ? "dim" : "normal"
    if (state != prevState) {
        SetBrightness(state="dim" ? (useZero ? 0 : dim) : normal)
        prevState := state
    }
}

; === 托盤 / 熱鍵 ===
^!Up::  SetBrightness(normal)
^!Down::SetBrightness(useZero ? 0 : dim)
^!P::  TogglePause()
F10::  TogglePanel()
OnExit(*) => (SetBrightness(normal))

A_TrayMenu.Add
A_TrayMenu.Add "控制面板…", (*) => TogglePanel()
A_TrayMenu.Default := "控制面板…"
try A_TrayMenu.ClickCount := 1
A_TrayMenu.Add "暫停/恢復", (*) => TogglePause()
A_TrayMenu.Add
A_TrayMenu.Add "退出", (*) => ExitApp()

TogglePause() {
    global paused, interval
    paused := !paused
    SetTimer(Check, paused ? 0 : interval)
    TrayTip("DimOnSite", paused ? "已暫停" : "已恢復", 1)
}

; === GUI 輔助 ===
EnableDarkTitle(hwnd) {
    try {
        on := 1
        DllCall("dwmapi\DwmSetWindowAttribute","ptr",hwnd,"int",20,"int*",on,"int",4)
        DllCall("dwmapi\DwmSetWindowAttribute","ptr",hwnd,"int",19,"int*",on,"int",4)
    }
}
FixListViewDark(lv) {
    static BK := 0x003F3937, FG := 0x00FFFFFF
    static LVM_SETBKCOLOR:=0x1001, LVM_SETTEXTCOLOR:=0x1024, LVM_SETTEXTBKCOLOR:=0x1026, LVM_GETHEADER:=0x101F
    SendMessage(LVM_SETBKCOLOR,     0, BK, , "ahk_id " lv.Hwnd)
    SendMessage(LVM_SETTEXTCOLOR,   0, FG, , "ahk_id " lv.Hwnd)
    SendMessage(LVM_SETTEXTBKCOLOR, 0, BK, , "ahk_id " lv.Hwnd)
    try {
        hHdr := SendMessage(LVM_GETHEADER, 0, 0, , "ahk_id " lv.Hwnd)
        DllCall("uxtheme\SetWindowTheme", "ptr", hHdr, "str", "", "ptr", 0)
    }
}
MakeBtn(g, opts, label) => g.AddText(opts " Center Border c" TXT_FG " Background" ACCENT_BG " +0x100 +0x200", label)
InstallBtnMouseHooks()  ; 裝一次滑鼠訊息（全域）

; === GUI ===
global g := 0, lvSites := 0
TogglePanel() {
    global g
    if IsSet(g) && g && WinExist("ahk_id " g.Hwnd)
        g.Destroy(), g := 0
    else
        ShowPanel()
}
ShowPanel() {
    global g, lvSites, sites, dim, normal, useZero, interval
    if IsSet(g) && g && WinExist("ahk_id " g.Hwnd) {
        g.Opt("+OwnDialogs"), g.Show("AutoSize"), g.Activate()
        return
    }

    g := Gui("+AlwaysOnTop -Resize", "DimOnSite 控制面板") ; 不可縮放
    g.BackColor := BASE_BG
    g.SetFont("s9 c" TXT_FG, "Segoe UI")
    g.MarginX := 12, g.MarginY := 10
    EnableDarkTitle(g.Hwnd)

    ; 橫幅（維持按鈕色）
    g.AddText("xm ym w420 h22 Background" ACCENT_BG)
    g.AddText("xp+6 yp+3 c" TXT_FG " BackgroundTrans", "網站清單（勾選＝啟用）")

    ; 清單（無表頭）
    lvSites := g.AddListView("xm y+4 w420 r9 Checked -Multi -Hdr +Border vLVsites", ["網站"])
    FixListViewDark(lvSites), lvSites.ModifyCol(1, 390), RefreshLV()

    ; 新增 / 刪除
    editSite := g.AddEdit("xm y+6 w265 vENewSite" EDIT_OPT)
    btnAdd   := MakeBtn(g, Format("x+6 w{1} h{2}", BTN_W, BTN_H), "新增")
    btnDel   := MakeBtn(g, Format("x+6 w{1} h{2}", BTN_W, BTN_H), "刪除")
    btnAdd.OnEvent("Click", AddSite)
    btnDel.OnEvent("Click", DelSelectedSite)
    RegisterBtn(btnAdd), RegisterBtn(btnDel)

    ; 下方設定（與清單同左同寬）
    lvx := lvy := lvw := lvh := 0
    lvSites.GetPos(&lvx, &lvy, &lvw, &lvh)
    editSite.GetPos(&sx, &sy, &sw, &sh)
    RX := lvx, RW := lvw, y := sy + sh + 10

    ; ── 命中時亮度 ──
    g.AddText(Format("x{1} y{2}", RX, y), "命中時亮度")
    sDim := g.AddSlider(Format("x{1} w{2} Range0-100 vSDim ToolTip", RX, RW), dim)
    sDim.GetPos(&dx,&dy,&dw,&dh)
    tDim := g.AddText(Format("x{1} y{2} w48 Right +0x200 BackgroundTrans"
        , dx+dw-50, dy+dh+2), dim "%")

    ; ── 正常亮度 ──
    g.AddText(Format("x{1} y+8", RX), "正常亮度")
    sNorm := g.AddSlider(Format("x{1} w{2} Range0-100 vSNormal ToolTip", RX, RW), normal)
    sNorm.GetPos(&nx,&ny,&nw,&nh)
    tNorm := g.AddText(Format("x{1} y{2} w48 Right +0x200 BackgroundTrans"
        , nx+nw-50, ny+nh+2), normal "%")

    ; 勾選與自啟動
    g.AddText(Format("x{1} y+10 w{2} h52 Background{3}", RX, RW, BASE_BG), "")
    cbZero := g.AddCheckbox("xp+8 yp+8 c" TXT_FG " vCBZero", "允許 0%（可能如黑屏）")
    cbZero.Value := useZero
    cbAuto := g.AddCheckbox("xp yp+20 c" TXT_FG " vCBAuto", "開機自啟動")
    cbAuto.Value := TaskExists() ? 1 : 0
    cbAuto.OnEvent("Click", (*) => (
        SetAutoStart(cbAuto.Value=1)
        , TrayTip("DimOnSite", cbAuto.Value? "已啟用開機自啟動":"已取消開機自啟動", 1)
    ))

    ; 檢查間隔
    g.AddText(Format("x{1} y+10", RX), "檢查間隔（毫秒，≥50）")
    g.AddEdit("x+8 w165 vEInt" EDIT_OPT, interval)

    ; 還原 / 套用
    btnRestore := MakeBtn(g, Format("x{1} y+10 w{2} h{3}", RX, BTN_W, BTN_H), "還原")
    btnApply   := MakeBtn(g, Format("x+8 w{1} h{2}", BTN_W, BTN_H), "套用")
    btnRestore.OnEvent("Click", (*) => SetBrightness(normal))
    btnApply.OnEvent("Click", ApplyAndSave)
    RegisterBtn(btnRestore), RegisterBtn(btnApply)

    ; 右下角簽名：與「套用」同高、同一水平線（垂直置中）
    btnApply.GetPos(&ax, &ay, &aw, &ah)
    g.AddText(Format("x{1} y{2} w{3} h{4} Right cA0A0A0 +0x200 BackgroundTrans"
        , RX, ay, RW, BTN_H), "Written by yoru")

    ; 滑桿即時預覽
    sDim.OnEvent("Change", (c,*) => (tDim.Text := c.Value "%", SetBrightness(c.Value)))
    sNorm.OnEvent("Change", (c,*) => (tNorm.Text := c.Value "%", SetBrightness(c.Value)))

    g.OnEvent("Close", (*) => (g.Destroy(), g := 0))
    g.Show("AutoSize")
}

; === GUI 事件 ===
RefreshLV() {
    global lvSites, sites
    if !lvSites
        return
    lvSites.Delete()
    for s in sites
        lvSites.Add(s.enabled ? "Check" : "", s.name)
}
AddSite(*) {
    global g, lvSites, sites
    name := Trim(g["ENewSite"].Value)
    if (name = "")
        return
    for i, s in sites
        if (StrLower(s.name)=StrLower(name)) {
            sites[i].enabled := true
            RefreshLV(), RefreshSiteKeys(), g["ENewSite"].Value := ""
            return
        }
    sites.Push({name:name, enabled:true})
    RefreshLV(), RefreshSiteKeys(), g["ENewSite"].Value := ""
}
DelSelectedSite(*) {
    global lvSites, sites
    rows := []
    r := 0
    while (r := lvSites.GetNext(r))
        rows.Push(r)
    if !rows.Length
        return
    i := rows.Length
    while (i >= 1) {
        sites.RemoveAt(rows[i])
        i -= 1
    }
    RefreshLV(), RefreshSiteKeys()
}
ApplyAndSave(*) {
    global g, lvSites, sites, siteKeys, dim, normal, useZero, interval
    ; 勾選同步
    for i, _ in sites
        sites[i].enabled := false
    r := 0
    while (r := lvSites.GetNext(r, "C"))
        sites[r].enabled := true
    RefreshSiteKeys()

    tmp := TryParseInt(g["SDim"].Value)     , (tmp!="") ? (dim:=tmp)    : 0
    tmp := TryParseInt(g["SNormal"].Value)  , (tmp!="") ? (normal:=tmp) : 0
    useZero := g["CBZero"].Value = 1

    v := TryParseInt(g["EInt"].Value)
    if (v = "") {
        g["EInt"].Value := interval
    } else {
        interval := v<50 ? 50 : v>60000 ? 60000 : v
        SetTimer(Check, 0), SetTimer(Check, interval)
        g["EInt"].Value := interval
    }
    SaveSettings()
    TrayTip("DimOnSite", "已套用並儲存設定", 1)
}

; === 啟動載入 ===
InstallBtnMouseHooks()
LoadSettings()
SetTimer(Check, 0), SetTimer(Check, interval)  ; 以載入後的間隔重新啟動定時器



