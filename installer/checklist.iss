#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef StageDir
  #define StageDir "..\build\deploy-stage"
#endif
#ifndef OutputDir
  #define OutputDir "..\dist"
#endif

[Setup]
AppId={{C5E9D885-726D-40B7-9A65-C0FFEE57A001}
AppName=CheckList
AppVersion={#AppVersion}
DefaultDirName={autopf}\CheckList
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir={#OutputDir}
OutputBaseFilename=checklist-setup-{#AppVersion}
Uninstallable=yes
CloseApplications=yes
Compression=lzma2
SolidCompression=yes

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[UninstallRun]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\install-runtime.ps1"" -Action uninstall -Root ""{app}"""; Flags: runhidden waituntilterminated; RunOnceId: "CheckListServices"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\jre"
Type: filesandordirs; Name: "{app}\postgresql"
Type: filesandordirs; Name: "{app}\checklist.jar"

[Code]
procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
  Started: Boolean;
begin
  if (CurStep = ssInstall) and FileExists(ExpandConstant('{app}\checklist-service.exe')) then
    Exec(ExpandConstant('{app}\checklist-service.exe'), 'stop', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  if CurStep = ssPostInstall then
  begin
    Started := Exec(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),
      '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{app}\install-runtime.ps1') + '" -Action install -Root "' + ExpandConstant('{app}') + '"',
      ExpandConstant('{app}'), SW_SHOW, ewWaitUntilTerminated, ResultCode);
    if (not Started) or (ResultCode <> 0) then
      RaiseException('서비스 설정에 실패했습니다. 설정과 데이터는 보존됩니다. 원인을 확인한 뒤 설치 프로그램을 다시 실행해 주세요.');
  end;
end;