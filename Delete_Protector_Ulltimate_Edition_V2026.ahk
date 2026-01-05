; Author: AndrianAngel(Github) - Enhanced by Community Request
; Version: 6.1 - DPAPI encryption + SafeList apps + Dialog exclusion
; License: Open-Source MIT

#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%

; Configuration file
ConfigFile := A_ScriptDir . "\DeleteProtector.ini"

; Load settings from config file
IniRead, EncryptedPassword, %ConfigFile%, Settings, EncryptedPassword, %A_Space%
IniRead, KeyboardGracePeriod, %ConfigFile%, Settings, KeyboardGracePeriod, 3
IniRead, ContextMenuGracePeriod, %ConfigFile%, Settings, ContextMenuGracePeriod, 3
IniRead, ExclusionList, %ConfigFile%, Settings, ExclusionList, Stack|Opus|DOpus
IniRead, SafeListApps, %ConfigFile%, Settings, SafeListApps, %A_Space%

; If no encrypted password exists, set default and encrypt it
if (EncryptedPassword = "" || EncryptedPassword = "ERROR") {
    SavedPassword := "admin123"
    EncryptedPassword := DPAPI_Encrypt(SavedPassword)
    IniWrite, %EncryptedPassword%, %ConfigFile%, Settings, EncryptedPassword
} else {
    SavedPassword := DPAPI_Decrypt(EncryptedPassword)
}

; Global flags
DisableDialogDetection := false
DisableKeyboardProtection := false
ScriptPaused := false

; Create system tray menu
Menu, Tray, NoStandard
Menu, Tray, Add, Settings, ShowSettings
Menu, Tray, Add, Pause/Resume Protection, TogglePause
Menu, Tray, Add, Exit, ExitApp
Menu, Tray, Tip, Delete Protector - Active
Menu, Tray, Icon, shell32.dll, 47

; Lets Context Menu Remember The Delete Prompt
ShowPasswordPrompt("delete")
Send !{F4}
return

; =========================
; DPAPI ENCRYPTION FUNCTIONS
; =========================

DPAPI_Encrypt(plainText) {
    ; Convert plain text to binary
    VarSetCapacity(binaryData, StrPut(plainText, "UTF-8"))
    dataSize := StrPut(plainText, &binaryData, "UTF-8") - 1
    
    ; Prepare DATA_BLOB structures
    VarSetCapacity(dataIn, 16, 0)
    NumPut(dataSize, dataIn, 0, "UInt")
    NumPut(&binaryData, dataIn, 8, "Ptr")
    
    VarSetCapacity(dataOut, 16, 0)
    
    ; Call CryptProtectData
    result := DllCall("Crypt32\CryptProtectData"
        , "Ptr", &dataIn
        , "Ptr", 0
        , "Ptr", 0
        , "Ptr", 0
        , "Ptr", 0
        , "UInt", 0
        , "Ptr", &dataOut)
    
    if (!result) {
        MsgBox, 16, Error, Failed to encrypt password!
        return ""
    }
    
    ; Get encrypted data
    encSize := NumGet(dataOut, 0, "UInt")
    encPtr := NumGet(dataOut, 8, "Ptr")
    
    ; Convert to base64 for storage
    encBase64 := BinaryToBase64(encPtr, encSize)
    
    ; Free the encrypted data
    DllCall("LocalFree", "Ptr", encPtr)
    
    return encBase64
}

DPAPI_Decrypt(encBase64) {
    ; Convert base64 back to binary
    encSize := Base64ToBinary(encBase64, encData)
    
    if (encSize = 0) {
        return ""
    }
    
    ; Prepare DATA_BLOB structures
    VarSetCapacity(dataIn, 16, 0)
    NumPut(encSize, dataIn, 0, "UInt")
    NumPut(&encData, dataIn, 8, "Ptr")
    
    VarSetCapacity(dataOut, 16, 0)
    
    ; Call CryptUnprotectData
    result := DllCall("Crypt32\CryptUnprotectData"
        , "Ptr", &dataIn
        , "Ptr", 0
        , "Ptr", 0
        , "Ptr", 0
        , "Ptr", 0
        , "UInt", 0
        , "Ptr", &dataOut)
    
    if (!result) {
        return ""
    }
    
    ; Get decrypted data
    decSize := NumGet(dataOut, 0, "UInt")
    decPtr := NumGet(dataOut, 8, "Ptr")
    
    ; Convert back to string
    plainText := StrGet(decPtr, decSize, "UTF-8")
    
    ; Free the decrypted data
    DllCall("LocalFree", "Ptr", decPtr)
    
    return plainText
}

BinaryToBase64(ptr, size) {
    ; Calculate required buffer size
    VarSetCapacity(base64, size * 2)
    flags := 0x40000001  ; CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF
    
    reqSize := 0
    DllCall("Crypt32\CryptBinaryToString"
        , "Ptr", ptr
        , "UInt", size
        , "UInt", flags
        , "Ptr", 0
        , "UIntP", reqSize)
    
    VarSetCapacity(base64, reqSize * 2)
    
    DllCall("Crypt32\CryptBinaryToString"
        , "Ptr", ptr
        , "UInt", size
        , "UInt", flags
        , "Str", base64
        , "UIntP", reqSize)
    
    return base64
}

Base64ToBinary(base64, ByRef binary) {
    flags := 0x00000001  ; CRYPT_STRING_BASE64
    
    reqSize := 0
    DllCall("Crypt32\CryptStringToBinary"
        , "Str", base64
        , "UInt", 0
        , "UInt", flags
        , "Ptr", 0
        , "UIntP", reqSize
        , "Ptr", 0
        , "Ptr", 0)
    
    VarSetCapacity(binary, reqSize)
    
    DllCall("Crypt32\CryptStringToBinary"
        , "Str", base64
        , "UInt", 0
        , "UInt", flags
        , "Ptr", &binary
        , "UIntP", reqSize
        , "Ptr", 0
        , "Ptr", 0)
    
    return reqSize
}

; ===================================
; CHECK IF ACTIVE APP IS IN SAFELIST
; ===================================

IsAppInSafeList() {
    global SafeListApps
    
    if (SafeListApps = "" || SafeListApps = "ERROR") {
        return false
    }
    
    ; Get active window process path
    WinGet, activeProcess, ProcessPath, A
    
    if (activeProcess = "") {
        return false
    }
    
    ; Normalize path to lowercase for comparison
    StringLower, activeProcess, activeProcess
    
    ; Split SafeList by pipe (|) and check each path
    Loop, Parse, SafeListApps, |
    {
        safePath := A_LoopField
        safePath := Trim(safePath)
        
        if (safePath = "") {
            continue
        }
        
        ; Normalize safelist path to lowercase
        StringLower, safePath, safePath
        
        ; Check if active process matches
        if (InStr(activeProcess, safePath)) {
            return true
        }
    }
    
    return false
}

; Alt+P hotkey to pause/resume protection and ask for a password

!p::
TogglePause:
{
    ShowPausePasswordPrompt()
    return
}

; Pause/Resume Toggle

{
    global ScriptPaused
    ScriptPaused := !ScriptPaused
    
    if (ScriptPaused) {
        Menu, Tray, Icon, shell32.dll, 110
        Menu, Tray, Tip, Delete Protector - PAUSED
        SetTimer, MonitorDeleteDialog, Off
        TrayTip, Delete Protector, Protection PAUSED - Files can be deleted without password, 3, 2
    } else {
        Menu, Tray, Icon, shell32.dll, 47
        Menu, Tray, Tip, Delete Protector - Active
        SetTimer, MonitorDeleteDialog, 50
        TrayTip, Delete Protector, Protection RESUMED - Password required for deletion, 3, 1
    }
    return
}

; Intercept Shift+Delete
+Del::
{
    global ScriptPaused, DisableKeyboardProtection
    
    ; Check if app is in SafeList
    if (IsAppInSafeList()) {
        Send +{Delete}
        return
    }
    
    if (ScriptPaused || DisableKeyboardProtection) {
        Send +{Delete}
        return
    }
    ShowPasswordPrompt("shift_delete")
    return
}

; Intercept Delete key
Del::
{
    global ScriptPaused, DisableKeyboardProtection
    
    ; Check if app is in SafeList
    if (IsAppInSafeList()) {
        Send {Delete}
        return
    }
    
    if (ScriptPaused || DisableKeyboardProtection) {
        Send {Delete}
        return
    }
    ShowPasswordPrompt("delete")
    return
}

; Function to check if window title should be excluded
IsWindowExcluded(windowTitle) {
    global ExclusionList
    
    if (ExclusionList = "" || ExclusionList = "ERROR") {
        return false
    }
    
    Loop, Parse, ExclusionList, |
    {
        keyword := A_LoopField
        keyword := Trim(keyword)
        
        if (keyword = "") {
            continue
        }
        
        if (InStr(windowTitle, keyword)) {
            return true
        }
    }
    
    return false
}

CheckWindowExclusion(winTitle) {
    WinGetTitle, ActualTitle, %winTitle%
    return IsWindowExcluded(ActualTitle)
}

; === MONITOR FOR DELETE CONFIRMATION DIALOGS ===
SetTimer, MonitorDeleteDialog, 50

MonitorDeleteDialog:
{
    global ScriptPaused
    
    if (ScriptPaused || DisableDialogDetection) {
        return
    }
    
    ; Check if current app is in SafeList - skip dialog detection if true
    if (IsAppInSafeList()) {
        return
    }
    
    ; Check for Windows delete confirmation dialogs
    IfWinExist, Delete File ahk_class #32770
    {
        if (CheckWindowExclusion("Delete File ahk_class #32770")) {
            return
        }
        DetectedWindow := "Delete File"
        goto HandleDeleteDialog
    }
    
    IfWinExist, Delete Folder ahk_class #32770
    {
        if (CheckWindowExclusion("Delete Folder ahk_class #32770")) {
            return
        }
        DetectedWindow := "Delete Folder"
        goto HandleDeleteDialog
    }
    
    IfWinExist, Delete Multiple Items ahk_class #32770
    {
        if (CheckWindowExclusion("Delete Multiple Items ahk_class #32770")) {
            return
        }
        DetectedWindow := "Delete Multiple Items"
        goto HandleDeleteDialog
    }
    
    IfWinExist, Confirm File Delete ahk_class #32770
    {
        if (CheckWindowExclusion("Confirm File Delete ahk_class #32770")) {
            return
        }
        DetectedWindow := "Confirm File Delete"
        goto HandleDeleteDialog
    }
    
    ; French versions
    IfWinExist, Supprimer le fichier ahk_class #32770
    {
        if (CheckWindowExclusion("Supprimer le fichier ahk_class #32770")) {
            return
        }
        DetectedWindow := "Supprimer le fichier"
        goto HandleDeleteDialog
    }
    
    IfWinExist, Supprimer le dossier ahk_class #32770
    {
        if (CheckWindowExclusion("Supprimer le dossier ahk_class #32770")) {
            return
        }
        DetectedWindow := "Supprimer le dossier"
        goto HandleDeleteDialog
    }
    
    IfWinExist, Supprimer plusieurs éléments ahk_class #32770
    {
        if (CheckWindowExclusion("Supprimer plusieurs éléments ahk_class #32770")) {
            return
        }
        DetectedWindow := "Supprimer plusieurs éléments"
        goto HandleDeleteDialog
    }
    
    ; Additional variants
    IfWinExist, ahk_class #32770
    {
        WinGetTitle, Title, ahk_class #32770
        
        if (IsWindowExcluded(Title)) {
            return
        }
        
        if (InStr(Title, "Delete") || InStr(Title, "Confirm") || InStr(Title, "Supprimer") || InStr(Title, "Confirmer")) {
            DetectedWindow := Title
            goto HandleDeleteDialog
        }
    }
    
    return
    
    HandleDeleteDialog:
    {
        SetTimer, MonitorDeleteDialog, Off
        
        WinGet, DeleteDialogHwnd, ID, %DetectedWindow% ahk_class #32770
        WinSet, Disable, , ahk_id %DeleteDialogHwnd%
        
        ShowPasswordPrompt("delete_dialog", DeleteDialogHwnd)
        return
    }
}

; Function to show password prompt with dark theme
ShowPasswordPrompt(deleteType, dialogHwnd := 0) {
    global SavedPassword, PwdPrompt_DeleteType, PwdPrompt_DialogHwnd
    
    PwdPrompt_DeleteType := deleteType
    PwdPrompt_DialogHwnd := dialogHwnd
    
    Gui, PwdPrompt:Destroy
    
    Gui, PwdPrompt:New, +AlwaysOnTop, Delete Protector
    Gui, PwdPrompt:Color, 202020, 2d2d2d
    Gui, PwdPrompt:Font, cWhite s10, Segoe UI
    
    Gui, PwdPrompt:Add, Text, w250 cWhite Background202020, Enter password to delete files:
    Gui, PwdPrompt:Add, Edit, vPasswordInput Password w250 Background2d2d2d cWhite
    
    Gui, PwdPrompt:Font, cWhite s9 Bold, Segoe UI
    Gui, PwdPrompt:Add, Button, Default w120 gCheckPassword HwndHBtn1 Background404040, OK
    Gui, PwdPrompt:Add, Button, x+10 w120 gCancelDelete HwndHBtn2 Background404040, Cancel
    
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn1, "Str", "DarkMode_Explorer", "Ptr", 0)
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn2, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    Gui, PwdPrompt:Show
}

CheckPassword:
{
    global SavedPassword, PwdPrompt_DeleteType, PasswordInput, PwdPrompt_DialogHwnd, DisableDialogDetection, KeyboardGracePeriod, ContextMenuGracePeriod, DisableKeyboardProtection
    Gui, PwdPrompt:Submit, NoHide
    
    if (PasswordInput = SavedPassword) {
        Gui, PwdPrompt:Destroy
        
        if (PwdPrompt_DeleteType = "shift_delete") {
            DisableDialogDetection := true
            SetTimer, MonitorDeleteDialog, Off
            Send +{Delete}
            SetTimer, ReEnableDialogDetection, % -KeyboardGracePeriod * 1000
        } else if (PwdPrompt_DeleteType = "delete") {
            DisableDialogDetection := true
            SetTimer, MonitorDeleteDialog, Off
            Send {Delete}
            SetTimer, ReEnableDialogDetection, % -KeyboardGracePeriod * 1000
        } else if (PwdPrompt_DeleteType = "delete_dialog") {
            DisableDialogDetection := true
            SetTimer, MonitorDeleteDialog, Off
            
            WinSet, Enable, , ahk_id %PwdPrompt_DialogHwnd%
            WinActivate, ahk_id %PwdPrompt_DialogHwnd%
            Sleep, 100
            
            SetTimer, ReEnableDialogDetection, % -ContextMenuGracePeriod * 1000
        }
    } else {
        MsgBox, 16, Error, Incorrect password!
        Gui, PwdPrompt:Destroy
        
        if (PwdPrompt_DeleteType = "delete_dialog" && PwdPrompt_DialogHwnd != 0) {
            WinSet, Enable, , ahk_id %PwdPrompt_DialogHwnd%
            WinClose, ahk_id %PwdPrompt_DialogHwnd%
        }
        
        SetTimer, MonitorDeleteDialog, 50
    }
    return
}

ReEnableDialogDetection:
{
    global DisableDialogDetection
    DisableDialogDetection := false
    SetTimer, MonitorDeleteDialog, 50
    return
}

CancelDelete:
PwdPromptGuiClose:
{
    global PwdPrompt_DeleteType, PwdPrompt_DialogHwnd
    
    if (PwdPrompt_DeleteType = "delete_dialog" && PwdPrompt_DialogHwnd != 0) {
        WinSet, Enable, , ahk_id %PwdPrompt_DialogHwnd%
        WinClose, ahk_id %PwdPrompt_DialogHwnd%
    }
    
    Gui, PwdPrompt:Destroy
    SetTimer, MonitorDeleteDialog, 50
    return
}

; Show Password Before Exit

ShowExitPasswordPrompt() {
    global SavedPassword, ExitPrompt_Validated
    
    ExitPrompt_Validated := false
    
    Gui, ExitPrompt:Destroy
    Gui, ExitPrompt:New, +AlwaysOnTop, Delete Protector - Exit
    Gui, ExitPrompt:Color, 202020, 2d2d2d
    Gui, ExitPrompt:Font, cWhite s10, Segoe UI
    
    Gui, ExitPrompt:Add, Text, w250 cWhite Background202020, Enter password to exit Delete Protector:
    Gui, ExitPrompt:Add, Edit, vExitPasswordInput Password w250 Background2d2d2d cWhite
    
    Gui, ExitPrompt:Font, cWhite s9 Bold, Segoe UI
    Gui, ExitPrompt:Add, Button, Default w120 gCheckExitPassword HwndHBtn1 Background404040, OK
    Gui, ExitPrompt:Add, Button, x+10 w120 gCancelExit HwndHBtn2 Background404040, Cancel
    
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn1, "Str", "DarkMode_Explorer", "Ptr", 0)
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn2, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    Gui, ExitPrompt:Show
}

; Check Exit Password Process

CheckExitPassword:
{
    global SavedPassword, ExitPasswordInput
    Gui, ExitPrompt:Submit, NoHide
    
    if (ExitPasswordInput = SavedPassword) {
        Gui, ExitPrompt:Destroy
        ExitApp
    } else {
        MsgBox, 16, Error, Incorrect password!
        Gui, ExitPrompt:Destroy
    }
    return
}

CancelExit:
ExitPromptGuiClose:
{
    Gui, ExitPrompt:Destroy
    return
}

; Ask for a password before giving access to settings

ShowSettingsPasswordPrompt() {
    global SavedPassword
    
    Gui, SettingsPrompt:Destroy
    Gui, SettingsPrompt:New, +AlwaysOnTop, Delete Protector - Settings Access
    Gui, SettingsPrompt:Color, 202020, 2d2d2d
    Gui, SettingsPrompt:Font, cWhite s10, Segoe UI
    
    Gui, SettingsPrompt:Add, Text, w250 cWhite Background202020, Enter password to access settings:
    Gui, SettingsPrompt:Add, Edit, vSettingsPasswordInput Password w250 Background2d2d2d cWhite
    
    Gui, SettingsPrompt:Font, cWhite s9 Bold, Segoe UI
    Gui, SettingsPrompt:Add, Button, Default w120 gCheckSettingsPassword HwndHBtn1 Background404040, OK
    Gui, SettingsPrompt:Add, Button, x+10 w120 gCancelSettingsAccess HwndHBtn2 Background404040, Cancel
    
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn1, "Str", "DarkMode_Explorer", "Ptr", 0)
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn2, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    Gui, SettingsPrompt:Show
}

CheckSettingsPassword:
{
    global SavedPassword, SettingsPasswordInput, ConfigFile, KeyboardGracePeriod, ContextMenuGracePeriod, ExclusionList, SafeListApps
    Gui, SettingsPrompt:Submit, NoHide
    
    if (SettingsPasswordInput = SavedPassword) {
        Gui, SettingsPrompt:Destroy
        
        ; Open the actual settings window
        Gui, Settings:New, , Delete Protector - Settings
        Gui, Settings:Color, 202020, 2d2d2d
        Gui, Settings:Font, cWhite s9, Segoe UI
        
        ; Password Settings
        Gui, Settings:Add, GroupBox, w300 h130 cWhite, Password Settings (DPAPI Encrypted)
        Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Current Password:
        Gui, Settings:Add, Edit, vOldPassword Password w270 Background2d2d2d cWhite
        Gui, Settings:Add, Text, xp y+10 cWhite, New Password:
        Gui, Settings:Add, Edit, vNewPassword Password w270 Background2d2d2d cWhite
        Gui, Settings:Add, Text, xp y+10 cWhite, Confirm Password:
        Gui, Settings:Add, Edit, vConfirmPassword Password w270 Background2d2d2d cWhite
        
        ; SafeList Apps Settings
        Gui, Settings:Add, GroupBox, xm y+20 w300 h130 cWhite, SafeList Applications
        Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Apps that bypass password protection:
        Gui, Settings:Add, Text, xp y+5 cGray, (Separate exe names or paths with | symbol)
        
        DisplaySafeListApps := (SafeListApps = "ERROR") ? "" : SafeListApps
        
        Gui, Settings:Add, Edit, vSafeListAppsInput w270 h60 Background2d2d2d cWhite HwndHEdit1, %DisplaySafeListApps%
        DllCall("UxTheme\SetWindowTheme", "Ptr", hEdit1, "Str", "DarkMode_Explorer", "Ptr", 0)
        
        Gui, Settings:Add, Text, xp y+5 cGray, Example: explorer.exe|dopus.exe
        
        ; Exclusion List Settings
        Gui, Settings:Add, GroupBox, xm y+20 w300 h110 cWhite, Dialog Window Exclusion List
        Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Exclude dialogs with these keywords:
        Gui, Settings:Add, Text, xp y+5 cGray, (Separate multiple keywords with | symbol)
        
        DisplayExclusionList := (ExclusionList = "ERROR") ? "" : ExclusionList
        
        Gui, Settings:Add, Edit, vExclusionListInput w270 h50 Background2d2d2d cWhite HwndHEdit2, %DisplayExclusionList%
        DllCall("UxTheme\SetWindowTheme", "Ptr", hEdit2, "Str", "DarkMode_Explorer", "Ptr", 0)
        
        Gui, Settings:Add, Text, xp y+5 cGray, Example: Stack|Opus|DOpus
        
        ; Grace Period Settings
        Gui, Settings:Add, GroupBox, xm y+20 w300 h90 cWhite, Keyboard Grace Period (Delete/Shift+Delete)
        Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Wait time before re-protection:
        
        KeyboardGraceChoice := (KeyboardGracePeriod = 2) ? 1 : (KeyboardGracePeriod = 3) ? 2 : (KeyboardGracePeriod = 4) ? 3 : (KeyboardGracePeriod = 5) ? 4 : (KeyboardGracePeriod = 6) ? 5 : 6 
        
        Gui, Settings:Add, ListBox, vKeyboardGracePeriodChoice w280 h90 Background2d2d2d cWhite Choose%KeyboardGraceChoice% HwndHList1 AltSubmit, 2 seconds|3 seconds|4 seconds|5 seconds|6 seconds|7 seconds
        DllCall("UxTheme\SetWindowTheme", "Ptr", hList1, "Str", "DarkMode_Explorer", "Ptr", 0)
        
        Gui, Settings:Add, GroupBox, xm y+20 w300 h90 cWhite, Context Menu Grace Period (Right-click Delete)
        Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Wait time before re-protection:
        
        ContextGraceChoice := (ContextMenuGracePeriod = 2) ? 1 : (ContextMenuGracePeriod = 3) ? 2 : (ContextMenuGracePeriod = 4) ? 3 : (ContextMenuGracePeriod = 5) ? 4 : (ContextMenuGracePeriod = 6) ? 5 : 6
        
        Gui, Settings:Add, ListBox, vContextMenuGracePeriodChoice w280 h90 Background2d2d2d cWhite Choose%ContextGraceChoice% HwndHList2 AltSubmit, 2 seconds|3 seconds|4 seconds|5 seconds|6 seconds|7 seconds
        DllCall("UxTheme\SetWindowTheme", "Ptr", hList2, "Str", "DarkMode_Explorer", "Ptr", 0)
        
        ; Info text
        Gui, Settings:Add, Text, xm y+15 w300 cGray Center, Press Alt+P to pause/resume protection
        Gui, Settings:Add, Text, xm y+5 w300 cGray Center, Press Alt+S to open settings
        Gui, Settings:Add, Text, xm y+5 w300 cGray Center, Press Alt+X to exit script
        Gui, Settings:Add, Text, xm y+5 w300 cLime Center, Password is encrypted with Windows DPAPI
        
        ; Buttons
        Gui, Settings:Font, cWhite s9 Bold, Segoe UI
        Gui, Settings:Add, Button, Default w140 xm+2 y+10 gSaveSettings HwndHBtn1 Background404040, Save
        Gui, Settings:Add, Button, x+14 w140 gCancelSettings HwndHBtn2 Background404040, Cancel
        
        DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn1, "Str", "DarkMode_Explorer", "Ptr", 0)
        DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn2, "Str", "DarkMode_Explorer", "Ptr", 0)
        
        Gui, Settings:Show, w320
    } else {
        MsgBox, 16, Error, Incorrect password!
        Gui, SettingsPrompt:Destroy
    }
    return
}

CancelSettingsAccess:
SettingsPromptGuiClose:
{
    Gui, SettingsPrompt:Destroy
    return
}

; Password Prompt for PAUSE Function

ShowPausePasswordPrompt() {
    global SavedPassword
    
    Gui, PausePrompt:Destroy
    Gui, PausePrompt:New, +AlwaysOnTop, Delete Protector - Pause/Resume
    Gui, PausePrompt:Color, 202020, 2d2d2d
    Gui, PausePrompt:Font, cWhite s10, Segoe UI
    
    Gui, PausePrompt:Add, Text, w250 cWhite Background202020, Enter password to pause/resume protection:
    Gui, PausePrompt:Add, Edit, vPausePasswordInput Password w250 Background2d2d2d cWhite
    
    Gui, PausePrompt:Font, cWhite s9 Bold, Segoe UI
    Gui, PausePrompt:Add, Button, Default w120 gCheckPausePassword HwndHBtn1 Background404040, OK
    Gui, PausePrompt:Add, Button, x+10 w120 gCancelPause HwndHBtn2 Background404040, Cancel
    
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn1, "Str", "DarkMode_Explorer", "Ptr", 0)
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn2, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    Gui, PausePrompt:Show
}

CheckPausePassword:
{
    global SavedPassword, PausePasswordInput, ScriptPaused
    Gui, PausePrompt:Submit, NoHide
    
    if (PausePasswordInput = SavedPassword) {
        Gui, PausePrompt:Destroy
        
        ; Toggle the pause state
        ScriptPaused := !ScriptPaused
        
        if (ScriptPaused) {
            Menu, Tray, Icon, shell32.dll, 110
            Menu, Tray, Tip, Delete Protector - PAUSED
            SetTimer, MonitorDeleteDialog, Off
            TrayTip, Delete Protector, Protection PAUSED - Files can be deleted without password, 3, 2
        } else {
            Menu, Tray, Icon, shell32.dll, 47
            Menu, Tray, Tip, Delete Protector - Active
            SetTimer, MonitorDeleteDialog, 50
            TrayTip, Delete Protector, Protection RESUMED - Password required for deletion, 3, 1
        }
    } else {
        MsgBox, 16, Error, Incorrect password!
        Gui, PausePrompt:Destroy
    }
    return
}

CancelPause:
PausePromptGuiClose:
{
    Gui, PausePrompt:Destroy
    return
} 


; Ask For A password before entering SETTING

!s::
ShowSettings:
{
    ShowSettingsPasswordPrompt()
    return
}

; SETTING GUI AND CONFIG

{
    global SavedPassword, ConfigFile, KeyboardGracePeriod, ContextMenuGracePeriod, ExclusionList, SafeListApps
    
    Gui, Settings:New, , Delete Protector - Settings
    Gui, Settings:Color, 202020, 2d2d2d
    Gui, Settings:Font, cWhite s9, Segoe UI
    
    ; Password Settings
    Gui, Settings:Add, GroupBox, w300 h130 cWhite, Password Settings (DPAPI Encrypted)
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Current Password:
    Gui, Settings:Add, Edit, vOldPassword Password w270 Background2d2d2d cWhite
    Gui, Settings:Add, Text, xp y+10 cWhite, New Password:
    Gui, Settings:Add, Edit, vNewPassword Password w270 Background2d2d2d cWhite
    Gui, Settings:Add, Text, xp y+10 cWhite, Confirm Password:
    Gui, Settings:Add, Edit, vConfirmPassword Password w270 Background2d2d2d cWhite
    
    ; SafeList Apps Settings
    Gui, Settings:Add, GroupBox, xm y+20 w300 h130 cWhite, SafeList Applications
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Apps that bypass password protection:
    Gui, Settings:Add, Text, xp y+5 cGray, (Separate exe names or paths with | symbol)
    
    DisplaySafeListApps := (SafeListApps = "ERROR") ? "" : SafeListApps
    
    Gui, Settings:Add, Edit, vSafeListAppsInput w270 h60 Background2d2d2d cWhite HwndHEdit1, %DisplaySafeListApps%
    DllCall("UxTheme\SetWindowTheme", "Ptr", hEdit1, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    Gui, Settings:Add, Text, xp y+5 cGray, Example: explorer.exe|dopus.exe
    
    ; Exclusion List Settings
    Gui, Settings:Add, GroupBox, xm y+20 w300 h110 cWhite, Dialog Window Exclusion List
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Exclude dialogs with these keywords:
    Gui, Settings:Add, Text, xp y+5 cGray, (Separate multiple keywords with | symbol)
    
    DisplayExclusionList := (ExclusionList = "ERROR") ? "" : ExclusionList
    
    Gui, Settings:Add, Edit, vExclusionListInput w270 h50 Background2d2d2d cWhite HwndHEdit2, %DisplayExclusionList%
    DllCall("UxTheme\SetWindowTheme", "Ptr", hEdit2, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    Gui, Settings:Add, Text, xp y+5 cGray, Example: Stack|Opus|DOpus
    
    ; Grace Period Settings
    Gui, Settings:Add, GroupBox, xm y+20 w300 h90 cWhite, Keyboard Grace Period (Delete/Shift+Delete)
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Wait time before re-protection:
    
    KeyboardGraceChoice := (KeyboardGracePeriod = 2) ? 1 : (KeyboardGracePeriod = 3) ? 2 : (KeyboardGracePeriod = 4) ? 3 : (KeyboardGracePeriod = 5) ? 4 : (KeyboardGracePeriod = 6) ? 5 : 6 
    
    Gui, Settings:Add, ListBox, vKeyboardGracePeriodChoice w280 h90 Background2d2d2d cWhite Choose%KeyboardGraceChoice% HwndHList1 AltSubmit, 2 seconds|3 seconds|4 seconds|5 seconds|6 seconds|7 seconds
    DllCall("UxTheme\SetWindowTheme", "Ptr", hList1, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    Gui, Settings:Add, GroupBox, xm y+20 w300 h90 cWhite, Context Menu Grace Period (Right-click Delete)
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Wait time before re-protection:
    
    ContextGraceChoice := (ContextMenuGracePeriod = 2) ? 1 : (ContextMenuGracePeriod = 3) ? 2 : (ContextMenuGracePeriod = 4) ? 3 : (ContextMenuGracePeriod = 5) ? 4 : (ContextMenuGracePeriod = 6) ? 5 : 6
    
    Gui, Settings:Add, ListBox, vContextMenuGracePeriodChoice w280 h90 Background2d2d2d cWhite Choose%ContextGraceChoice% HwndHList2 AltSubmit, 2 seconds|3 seconds|4 seconds|5 seconds|6 seconds|7 seconds
    DllCall("UxTheme\SetWindowTheme", "Ptr", hList2, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    ; Info text
    Gui, Settings:Add, Text, xm y+15 w300 cGray Center, Press Alt+P to pause/resume protection
    Gui, Settings:Add, Text, xm y+5 w300 cGray Center, Press Alt+S to open settings
    Gui, Settings:Add, Text, xm y+5 w300 cGray Center, Press Alt+X to exit script
    Gui, Settings:Add, Text, xm y+5 w300 cLime Center, Password is encrypted with Windows DPAPI
    
    ; Buttons
    Gui, Settings:Font, cWhite s9 Bold, Segoe UI
    Gui, Settings:Add, Button, Default w140 xm+2 y+10 gSaveSettings HwndHBtn1 Background404040, Save
    Gui, Settings:Add, Button, x+14 w140 gCancelSettings HwndHBtn2 Background404040, Cancel
    
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn1, "Str", "DarkMode_Explorer", "Ptr", 0)
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn2, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    Gui, Settings:Show, w320
    return
}

SaveSettings:
{
    global SavedPassword, ConfigFile, KeyboardGracePeriod, ContextMenuGracePeriod, ExclusionList, SafeListApps, EncryptedPassword
    Gui, Settings:Submit, NoHide
    
    NewKeyboardGracePeriod := (KeyboardGracePeriodChoice = 1) ? 2 : (KeyboardGracePeriodChoice = 2) ? 3 : (KeyboardGracePeriodChoice = 3) ? 4 : (KeyboardGracePeriodChoice = 4) ? 5 : (KeyboardGracePeriodChoice = 5) ? 6 : 7
    NewContextMenuGracePeriod := (ContextMenuGracePeriodChoice = 1) ? 2 : (ContextMenuGracePeriodChoice = 2) ? 3 : (ContextMenuGracePeriodChoice = 3) ? 4 : (ContextMenuGracePeriodChoice = 4) ? 5 : (ContextMenuGracePeriodChoice = 5) ? 6 : 7
    
    ; If password fields are filled, validate and update password
    if (OldPassword != "" || NewPassword != "" || ConfirmPassword != "") {
        if (OldPassword != SavedPassword) {
            MsgBox, 16, Error, Current password is incorrect!
            return
        }
        
        if (NewPassword = "") {
            MsgBox, 16, Error, New password cannot be empty!
            return
        }
        
        if (NewPassword != ConfirmPassword) {
            MsgBox, 16, Error, New passwords do not match!
            return
        }
        
        ; Encrypt and save new password
        SavedPassword := NewPassword
        EncryptedPassword := DPAPI_Encrypt(SavedPassword)
        IniWrite, %EncryptedPassword%, %ConfigFile%, Settings, EncryptedPassword
    }
    
    ; Save SafeList apps
    SafeListApps := Trim(SafeListAppsInput)
    IniWrite, %SafeListApps%, %ConfigFile%, Settings, SafeListApps
    
    ; Save exclusion list
    ExclusionList := Trim(ExclusionListInput)
    IniWrite, %ExclusionList%, %ConfigFile%, Settings, ExclusionList
    
    ; Save grace periods
    KeyboardGracePeriod := NewKeyboardGracePeriod
    ContextMenuGracePeriod := NewContextMenuGracePeriod
    IniWrite, %KeyboardGracePeriod%, %ConfigFile%, Settings, KeyboardGracePeriod
    IniWrite, %ContextMenuGracePeriod%, %ConfigFile%, Settings, ContextMenuGracePeriod
    
    MsgBox, 64, Success, Settings updated successfully!`n`nKeyboard Grace Period: %KeyboardGracePeriod% seconds`nContext Menu Grace Period: %ContextMenuGracePeriod% seconds`nExclusion List: %ExclusionList%`n`nPassword is encrypted with Windows DPAPI
    Gui, Settings:Destroy
    return
}

CancelSettings:
SettingsGuiClose:
{
    Gui, Settings:Destroy
    return
}

!x::
ExitApp:
{
    ShowExitPasswordPrompt()
    return
}