Option Explicit
Dim shell, fso, scriptDirectory, agentPath
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
scriptDirectory = fso.GetParentFolderName(WScript.ScriptFullName)
agentPath = fso.BuildPath(scriptDirectory, "Agent\PurviewProtectionAgent.exe")
shell.Run Chr(34) & agentPath & Chr(34), 0, False

