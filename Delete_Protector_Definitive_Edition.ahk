; Author: AndrianAngel(Github)
; Version: 5.5 - Fixed Keyboard Protection Grace Period
; License: Open-Source MIT

#NoEnv
#SingleInstance Force
SetWorkingDir %A_ScriptDir%

; Configuration file
ConfigFile := A_ScriptDir . "\DeleteProtector.ini"

; Load settings from config file
IniRead, SavedPassword, %ConfigFile%, Settings, Password, admin123
IniRead, KeyboardGracePeriod, %ConfigFile%, Settings, KeyboardGracePeriod, 3
IniRead, ContextMenuGracePeriod, %ConfigFile%, Settings, ContextMenuGracePeriod, 3
IniRead, ExclusionList, %ConfigFile%, Settings, ExclusionList, Stack|Opus|DOpus

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

; Function to check if window title should be excluded
IsWindowExcluded(windowTitle) {
    global ExclusionList
    
    ; If exclusion list is empty, don't exclude anything
    if (ExclusionList = "" || ExclusionList = "ERROR") {
        return false
    }
    
    ; Split exclusion list by pipe (|) and check each keyword
    Loop, Parse, ExclusionList, |
    {
        keyword := A_LoopField
        ; Trim whitespace
        keyword := Trim(keyword)
        
        ; Skip empty keywords
        if (keyword = "") {
            continue
        }
        
        ; Check if the keyword exists in the window title (case-insensitive)
        if (InStr(windowTitle, keyword)) {
            return true
        }
    }
    
    return false
}

; Function to get window title and check exclusion
CheckWindowExclusion(winTitle) {
    ; First get the actual window title
    WinGetTitle, ActualTitle, %winTitle%
    
    ; Check if it should be excluded
    return IsWindowExcluded(ActualTitle)
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
    ; English versions - CHECK EXCLUSION FIRST
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
    
    ; French versions - CHECK EXCLUSION FIRST
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
    
    ; Additional English and French variants - CHECK EXCLUSION LIST
	IfWinExist, ahk_class #32770
	{
		; Get the title of the DETECTED #32770 window, not the active window
		WinGetTitle, Title, ahk_class #32770
		
		; Check if window is in exclusion list FIRST
		if (IsWindowExcluded(Title)) {
			return
		}
		
		; Only trigger for actual delete dialogs
		if (InStr(Title, "Delete") || InStr(Title, "Confirm") || InStr(Title, "Supprimer") || InStr(Title, "Confirmer")) {
			DetectedWindow := Title
			goto HandleDeleteDialog
		}
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
            DisableDialogDetection := true
            SetTimer, MonitorDeleteDialog, Off
            Send +{Delete}
            ; Keyboard protection stays ON, only disable dialog detection temporarily
            SetTimer, ReEnableDialogDetection, % -KeyboardGracePeriod * 1000
        } else if (PwdPrompt_DeleteType = "delete") {
            DisableDialogDetection := true
            SetTimer, MonitorDeleteDialog, Off
            Send {Delete}
            ; Keyboard protection stays ON, only disable dialog detection temporarily
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

; This function is no longer needed - keyboard protection now stays enabled

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

!s::
ShowSettings:
{
    global SavedPassword, ConfigFile, KeyboardGracePeriod, ContextMenuGracePeriod, ExclusionList
    
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
    
    ; Exclusion List Settings
    Gui, Settings:Add, GroupBox, xm y+20 w300 h110 cWhite, Window Exclusion List
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Exclude windows with these keywords:
    Gui, Settings:Add, Text, xp y+5 cGray, (Separate multiple keywords with | symbol)
    
    ; Convert ERROR to empty string for display
    DisplayExclusionList := (ExclusionList = "ERROR") ? "" : ExclusionList
    
    Gui, Settings:Add, Edit, vExclusionListInput w270 h90 Background2d2d2d cWhite HwndHEdit1, %DisplayExclusionList%
    DllCall("UxTheme\SetWindowTheme", "Ptr", hEdit1, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    Gui, Settings:Add, Text, xp y+5 cGray, Example: Stack|Opus|MyApp
    
    ; Keyboard Grace Period Settings
    Gui, Settings:Add, GroupBox, xm y+20 w300 h90 cWhite, Keyboard Grace Period (Delete/Shift+Delete)
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Wait time before re-protection:
    
    KeyboardGraceChoice := (KeyboardGracePeriod = 2) ? 1 : (KeyboardGracePeriod = 3) ? 2 : (KeyboardGracePeriod = 4) ? 3 : (KeyboardGracePeriod = 5) ? 4 : (KeyboardGracePeriod = 6) ? 5 : 6 
    
    Gui, Settings:Add, ListBox, vKeyboardGracePeriodChoice w280 h90 Background2d2d2d cWhite Choose%KeyboardGraceChoice% HwndHList1 AltSubmit, 2 seconds|3 seconds|4 seconds|5 seconds|6 seconds|7 seconds
    DllCall("UxTheme\SetWindowTheme", "Ptr", hList1, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    ; Context Menu Grace Period Settings
    Gui, Settings:Add, GroupBox, xm y+20 w300 h90 cWhite, Context Menu Grace Period (Right-click Delete)
    Gui, Settings:Add, Text, xp+10 yp+25 cWhite, Wait time before re-protection:
    
    ContextGraceChoice := (ContextMenuGracePeriod = 2) ? 1 : (ContextMenuGracePeriod = 3) ? 2 : (ContextMenuGracePeriod = 4) ? 3 : (ContextMenuGracePeriod = 5) ? 4 : (ContextMenuGracePeriod = 6) ? 5 : 6
    
    Gui, Settings:Add, ListBox, vContextMenuGracePeriodChoice w280 h90 Background2d2d2d cWhite Choose%ContextGraceChoice% HwndHList2 AltSubmit, 2 seconds|3 seconds|4 seconds|5 seconds|6 seconds|7 seconds
    DllCall("UxTheme\SetWindowTheme", "Ptr", hList2, "Str", "DarkMode_Explorer", "Ptr", 0)
    
    ; Info text about pause feature and hotkeys
    Gui, Settings:Add, Text, xm y+15 w300 cGray Center, Press Alt+P to pause/resume protection
    Gui, Settings:Add, Text, xm y+5 w300 cGray Center, Press Alt+S to open setting
    Gui, Settings:Add, Text, xm y+5 w300 cGray Center, Press Alt+X to exit script
    
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
    global SavedPassword, ConfigFile, KeyboardGracePeriod, ContextMenuGracePeriod, ExclusionList
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
        
        SavedPassword := NewPassword
        IniWrite, %SavedPassword%, %ConfigFile%, Settings, Password
    }
    
    ; Save exclusion list
    ExclusionList := Trim(ExclusionListInput)
    IniWrite, %ExclusionList%, %ConfigFile%, Settings, ExclusionList
    
    ; Save grace periods
    KeyboardGracePeriod := NewKeyboardGracePeriod
    ContextMenuGracePeriod := NewContextMenuGracePeriod
    IniWrite, %KeyboardGracePeriod%, %ConfigFile%, Settings, KeyboardGracePeriod
    IniWrite, %ContextMenuGracePeriod%, %ConfigFile%, Settings, ContextMenuGracePeriod
    
    MsgBox, 64, Success, Settings updated successfully!`n`nKeyboard Grace Period: %KeyboardGracePeriod% seconds`nContext Menu Grace Period: %ContextMenuGracePeriod% seconds`nExclusion List: %ExclusionList%
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
    ExitApp
    return
}