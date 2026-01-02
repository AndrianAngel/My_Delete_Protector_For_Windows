; Author: AndrianAngel(Github)
; Version: 5.1 Stable Release 02/01/2026
; License: Open-Source MIT

#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%

; Configuration file
ConfigFile := A_ScriptDir . "\DeleteProtector.ini"

; Load settings from config file
IniRead, SavedPassword, %ConfigFile%, Settings, Password, admin123
IniRead, KeyboardGracePeriod, %ConfigFile%, Settings, KeyboardGracePeriod, 25
IniRead, ContextMenuGracePeriod, %ConfigFile%, Settings, ContextMenuGracePeriod, 3

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

; Lets Context Menu Remember The Delete Prompt (A Trick To Fool Context Menu Delete Bug // Don't Remove) 
ShowPasswordPrompt("delete")
Send !{F4}
return

; Alt+P hotkey to pause/resume protection
!p::
TogglePause:
{
    global ScriptPaused
    ScriptPaused := !ScriptPaused
    
    if (ScriptPaused) {
        Menu, Tray, Icon, shell32.dll, 110  ; Different icon for paused state
        Menu, Tray, Tip, Delete Protector - PAUSED
        SetTimer, MonitorDeleteDialog, Off
        TrayTip, Delete Protector, Protection PAUSED - Files can be deleted without password, 3, 2
    } else {
        Menu, Tray, Icon, shell32.dll, 47   ; Original icon for active state
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
    if (ScriptPaused || DisableKeyboardProtection) {
        Send {Delete}
        return
    }
    ShowPasswordPrompt("delete")
    return
}

; === MONITOR FOR DELETE CONFIRMATION DIALOGS ===
; Start monitoring immediately when script loads
SetTimer, MonitorDeleteDialog, 50

MonitorDeleteDialog:
{
    global ScriptPaused
    
    ; Skip detection if paused or temporarily disabled
    if (ScriptPaused || DisableDialogDetection) {
        return
    }
    
    ; Check for Windows delete confirmation dialogs
    ; English versions
    IfWinExist, Delete File ahk_class #32770
    {
        DetectedWindow := "Delete File"
        goto HandleDeleteDialog
    }
    
    IfWinExist, Delete Folder ahk_class #32770
    {
        DetectedWindow := "Delete Folder"
        goto HandleDeleteDialog
    }
    
    IfWinExist, Delete Multiple Items ahk_class #32770
    {
        DetectedWindow := "Delete Multiple Items"
        goto HandleDeleteDialog
    }
    
    IfWinExist, Confirm File Delete ahk_class #32770
    {
        DetectedWindow := "Confirm File Delete"
        goto HandleDeleteDialog
    }
    
    ; Additional English and French variants that might appear
    IfWinExist, ahk_class #32770
    {
        WinGetTitle, Title, A
        if (InStr(Title, "Delete") || InStr(Title, "Confirm") || InStr(Title, "Supprimer") || InStr(Title, "Confirmer")) {
            DetectedWindow := Title
            goto HandleDeleteDialog
        }
    }
    
    ; French versions
    IfWinExist, Supprimer le fichier ahk_class #32770
    {
        DetectedWindow := "Supprimer le fichier"
        goto HandleDeleteDialog
    }
    
    IfWinExist, Supprimer le dossier ahk_class #32770
    {
        DetectedWindow := "Supprimer le dossier"
        goto HandleDeleteDialog
    }
    
    IfWinExist, Supprimer plusieurs éléments ahk_class #32770
    {
        DetectedWindow := "Supprimer plusieurs éléments"
        goto HandleDeleteDialog
    }
    
    return
    
    HandleDeleteDialog:
    {
        ; Stop monitoring temporarily to avoid multiple triggers
        SetTimer, MonitorDeleteDialog, Off
        
        ; Store the window handle
        WinGet, DeleteDialogHwnd, ID, %DetectedWindow% ahk_class #32770
        
        ; FREEZE the dialog - disable it but keep it visible
        WinSet, Disable, , ahk_id %DeleteDialogHwnd%
        
        ; Show our password prompt
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
            ; Only disable KEYBOARD protection temporarily, not dialog detection
            DisableKeyboardProtection := true
            Send +{Delete}
            ; Re-enable after keyboard grace period
            SetTimer, ReEnableKeyboardProtection, % -KeyboardGracePeriod * 1000
        } else if (PwdPrompt_DeleteType = "delete") {
            ; Only disable KEYBOARD protection temporarily, not dialog detection
            DisableKeyboardProtection := true
            Send {Delete}
            ; Re-enable after keyboard grace period
            SetTimer, ReEnableKeyboardProtection, % -KeyboardGracePeriod * 1000
        } else if (PwdPrompt_DeleteType = "delete_dialog") {
            ; For dialog/context menu: use context menu grace period
            
            ; Disable detection BRIEFLY for this operation
            DisableDialogDetection := true
            SetTimer, MonitorDeleteDialog, Off
            
            ; Re-enable the frozen dialog
            WinSet, Enable, , ahk_id %PwdPrompt_DialogHwnd%
            
            ; Activate frozen dialog
            WinActivate, ahk_id %PwdPrompt_DialogHwnd%
            Sleep, 100
            
            ; Re-enable dialog monitoring after context menu grace period
            SetTimer, ReEnableDialogDetection, % -ContextMenuGracePeriod * 1000
        }
    } else {
        MsgBox, 16, Error, Incorrect password!
        Gui, PwdPrompt:Destroy
        
        ; If it was a dialog, re-enable and close it
        if (PwdPrompt_DeleteType = "delete_dialog" && PwdPrompt_DialogHwnd != 0) {
            WinSet, Enable, , ahk_id %PwdPrompt_DialogHwnd%
            WinClose, ahk_id %PwdPrompt_DialogHwnd%
        }
        
        ; Resume monitoring
        SetTimer, MonitorDeleteDialog, 50
    }
    return
}

ReEnableDialogDetection:
{
    global DisableDialogDetection
    DisableDialogDetection := false
    ; Resume monitoring
    SetTimer, MonitorDeleteDialog, 50
    return
}

ReEnableKeyboardProtection:
{
    global DisableKeyboardProtection
    DisableKeyboardProtection := false
    return
}

CancelDelete:
PwdPromptGuiClose:
{
    global PwdPrompt_DeleteType, PwdPrompt_DialogHwnd
    
    ; If canceling a dialog interception, re-enable and close the original dialog
    if (PwdPrompt_DeleteType = "delete_dialog" && PwdPrompt_DialogHwnd != 0) {
        WinSet, Enable, , ahk_id %PwdPrompt_DialogHwnd%
        WinClose, ahk_id %PwdPrompt_DialogHwnd%
    }
    
    Gui, PwdPrompt:Destroy
    
    ; Resume monitoring
    SetTimer, MonitorDeleteDialog, 50
    return
}

!s:: ; ALT+S Hotkey To Open Setting (especially in case you want to hide Tray icon)
ShowSettings:
{
    global SavedPassword, ConfigFile, KeyboardGracePeriod, ContextMenuGracePeriod
    
    ; Create Settings GUI with dark theme
    Gui, Settings:New, , Delete Protector - Settings
    Gui, Settings:Color, 202020, 2d2d2d
    Gui, Settings:Font, cWhite s9, Segoe UI
    
    ; Password Settings
    Gui, Settings:Add, GroupBox, w300 h130 cWhite, Password Settings
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Current Password:
    Gui, Settings:Add, Edit, vOldPassword Password w270 Background2d2d2d cWhite
    Gui, Settings:Add, Text, xp y+10 cWhite, New Password:
    Gui, Settings:Add, Edit, vNewPassword Password w270 Background2d2d2d cWhite
    Gui, Settings:Add, Text, xp y+10 cWhite, Confirm Password:
    Gui, Settings:Add, Edit, vConfirmPassword Password w270 Background2d2d2d cWhite
    
    ; Keyboard Grace Period Settings
    Gui, Settings:Add, GroupBox, xm y+20 w300 h90 cWhite, Keyboard Grace Period (Delete/Shift+Delete)
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Wait time before re-protection:
    
    ; Calculate which option to select for keyboard (1=10s, 2=15s, 3=20s, 4=25s)
    KeyboardGraceChoice := (KeyboardGracePeriod = 10) ? 1 : (KeyboardGracePeriod = 15) ? 2 : (KeyboardGracePeriod = 20) ? 3 : 4
    
    Gui, Settings:Add, ListBox, vKeyboardGracePeriodChoice w280 h60 Background2d2d2d cWhite Choose%KeyboardGraceChoice% HwndHList1 AltSubmit, 10 seconds|15 seconds|20 seconds|25 seconds
    DllCall("UxTheme\SetWindowTheme", "Ptr", hList1, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    ; Context Menu Grace Period Settings
    Gui, Settings:Add, GroupBox, xm y+20 w300 h90 cWhite, Context Menu Grace Period (Right-click Delete)
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Wait time before re-protection:
    
    ; Calculate which option to select for context menu (1=2s, 2=3s, 3=4s, 4=5s, 5=6s, 6=7s)
    ContextGraceChoice := (ContextMenuGracePeriod = 2) ? 1 : (ContextMenuGracePeriod = 3) ? 2 : (ContextMenuGracePeriod = 4) ? 3 : (ContextMenuGracePeriod = 5) ? 4 : (ContextMenuGracePeriod = 6) ? 5 : 6
    
    Gui, Settings:Add, ListBox, vContextMenuGracePeriodChoice w280 h90 Background2d2d2d cWhite Choose%ContextGraceChoice% HwndHList2 AltSubmit, 2 seconds|3 seconds|4 seconds|5 seconds|6 seconds|7 seconds
    DllCall("UxTheme\SetWindowTheme", "Ptr", hList2, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    ; Info text about pause feature and hotkeys
    Gui, Settings:Add, Text, xm y+15 w300 cGray Center, Press Alt+P to pause/resume protection
	Gui, Settings:Add, Text, xm y+15 w300 cGray Center, Press Alt+S to open setting
	Gui, Settings:Add, Text, xm y+15 w300 cGray Center, Press Alt+X to exit script
    
    ; Buttons
    Gui, Settings:Font, cWhite s9 Bold, Segoe UI
    Gui, Settings:Add, Button, Default w140 xm+2 y+10 gSaveSettings HwndHBtn1 Background404040, Save
    Gui, Settings:Add, Button, x+14 w140 gCancelSettings HwndHBtn2 Background404040, Cancel
    
    ; Apply dark button styling
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn1, "Str", "DarkMode_Explorer", "Ptr", 0)
    DllCall("UxTheme\SetWindowTheme", "Ptr", hBtn2, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    Gui, Settings:Show, w320
    return
}

SaveSettings:
{
    global SavedPassword, ConfigFile, KeyboardGracePeriod, ContextMenuGracePeriod
    Gui, Settings:Submit, NoHide
    
    ; Calculate new grace periods from selections
    NewKeyboardGracePeriod := (KeyboardGracePeriodChoice = 1) ? 10 : (KeyboardGracePeriodChoice = 2) ? 15 : (KeyboardGracePeriodChoice = 3) ? 20 : 25
    NewContextMenuGracePeriod := (ContextMenuGracePeriodChoice = 1) ? 2 : (ContextMenuGracePeriodChoice = 2) ? 3 : (ContextMenuGracePeriodChoice = 3) ? 4 : (ContextMenuGracePeriodChoice = 4) ? 5 : (ContextMenuGracePeriodChoice = 5) ? 6 : 7
    
    ; If password fields are filled, validate and update password
    if (OldPassword != "" || NewPassword != "" || ConfirmPassword != "") {
        ; Verify old password
        if (OldPassword != SavedPassword) {
            MsgBox, 16, Error, Current password is incorrect!
            return
        }
        
        ; Check if new password is empty
        if (NewPassword = "") {
            MsgBox, 16, Error, New password cannot be empty!
            return
        }
        
        ; Verify new password confirmation
        if (NewPassword != ConfirmPassword) {
            MsgBox, 16, Error, New passwords do not match!
            return
        }
        
        ; Save new password
        SavedPassword := NewPassword
        IniWrite, %SavedPassword%, %ConfigFile%, Settings, Password
    }
    
    ; Save grace periods
    KeyboardGracePeriod := NewKeyboardGracePeriod
    ContextMenuGracePeriod := NewContextMenuGracePeriod
    IniWrite, %KeyboardGracePeriod%, %ConfigFile%, Settings, KeyboardGracePeriod
    IniWrite, %ContextMenuGracePeriod%, %ConfigFile%, Settings, ContextMenuGracePeriod
    
    MsgBox, 64, Success, Settings updated successfully!`n`nKeyboard Grace Period: %KeyboardGracePeriod% seconds`nContext Menu Grace Period: %ContextMenuGracePeriod% seconds
    Gui, Settings:Destroy
    return
}

CancelSettings:
SettingsGuiClose:
{
    Gui, Settings:Destroy
    return
}

!x:: ; ALT+X Hotkey To Exit the script (especially in case you want to hide Tray icon)
ExitApp:
{
    ExitApp
    return
}