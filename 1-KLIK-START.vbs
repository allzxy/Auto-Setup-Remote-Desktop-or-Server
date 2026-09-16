' ==============================================================================
' 1-KLIK LAUNCHER SETUP REMOTE SERVER (Silent Background Mode)
' ==============================================================================

Dim objShell, fso, currentDir, psScript, args
Set objShell = CreateObject("Shell.Application")
Set fso = CreateObject("Scripting.FileSystemObject")

currentDir = fso.GetParentFolderName(WScript.ScriptFullName)
psScript = currentDir & "\setup-remote.ps1"

' Menggunakan Chr(34) agar path ber-spasi tidak pernah error
args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File " & Chr(34) & psScript & Chr(34)
objShell.ShellExecute "powershell.exe", args, "", "runas", 0
