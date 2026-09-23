#Requires AutoHotkey v2.0
#SingleInstance Force
; MouseToggle.ahk - botoes extras do mouse funcionam como icone da taskbar:
;   aberto + em foco  -> minimiza
;   aberto sem foco   -> traz pra frente
;   sem janela mas processo vivo (bandeja) -> reexibe a janela escondida
;   realmente fechado -> abre o app
;
; Atalhos (configurados no software da Redragon em "Key combination"):
;   Ctrl+Alt+F9   -> Terminal / WSL2 Ubuntu
;   Ctrl+Alt+F10  -> Microsoft Teams
;   Ctrl+Alt+F11  -> Claude

Toggle(exeName, launchCmd) {
    win := "ahk_exe " exeName

    ; 1) janela visivel: alterna foco/minimiza
    if WinExist(win) {
        if WinActive(win)
            WinMinimize(win)
        else {
            if (WinGetMinMax(win) = -1)
                WinRestore(win)
            WinActivate(win)
        }
        return
    }

    ; 2) processo vivo sem janela visivel (app na bandeja / janela escondida):
    ;    NUNCA relancar - Electron recusa segunda instancia. Reexibe a janela.
    if ProcessExist(exeName) {
        DetectHiddenWindows(true)
        alvo := 0
        for h in WinGetList(win) {
            if (WinGetTitle(h) != "") {
                alvo := h
                break
            }
        }
        if alvo {
            WinShow(alvo)
            if (WinGetMinMax(alvo) = -1)
                WinRestore(alvo)
            WinActivate(alvo)
        }
        DetectHiddenWindows(false)
        return
    }

    ; 3) processo inexistente: ai sim abre
    Run(launchCmd)
}

; Sempre traz pra frente, nunca minimiza. Usado pela notificacao do Claude Code,
; onde "alternar" seria errado: se o toast rouba o foco do terminal, o Toggle()
; leria a janela como inativa e ate funcionaria, mas na borda oposta minimizaria
; exatamente a janela que voce pediu pra ver.
Focus(exeName, launchCmd) {
    win := "ahk_exe " exeName

    if WinExist(win) {
        if (WinGetMinMax(win) = -1)
            WinRestore(win)
        WinActivate(win)
        return
    }

    if ProcessExist(exeName) {
        DetectHiddenWindows(true)
        alvo := 0
        for h in WinGetList(win) {
            if (WinGetTitle(h) != "") {
                alvo := h
                break
            }
        }
        if alvo {
            WinShow(alvo)
            if (WinGetMinMax(alvo) = -1)
                WinRestore(alvo)
            WinActivate(alvo)
        }
        DetectHiddenWindows(false)
        return
    }

    Run(launchCmd)
}

; --- 1. Terminal / WSL2 Ubuntu ---
^!F9::Toggle("WindowsTerminal.exe", "shell:AppsFolder\Microsoft.WindowsTerminal_8wekyb3d8bbwe!App")

; --- 2. Microsoft Teams ---
^!F10::Toggle("ms-teams.exe", "shell:AppsFolder\MSTeams_8wekyb3d8bbwe!MSTeams")

; --- 3. Claude ---
^!F11::Toggle("claude.exe", "shell:AppsFolder\Claude_pzs8sxrjxfjjc!Claude")

; --- 4. So-focar, para a notificacao do Claude Code (sem botao no mouse) ---
^!F8::Focus("WindowsTerminal.exe", "shell:AppsFolder\Microsoft.WindowsTerminal_8wekyb3d8bbwe!App")
