#ifndef AppVersion
  #define AppVersion "0.0.3"
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
WizardStyle=modern
WizardSizePercent=120,130
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
Source: "{#StageDir}\detect-services.ps1"; Flags: dontcopy
Source: "{#StageDir}\install-config.ps1"; Flags: dontcopy
Source: "{#StageDir}\runtime-support.ps1"; Flags: dontcopy
Source: "{#StageDir}\stop-services.ps1"; Flags: dontcopy
[UninstallDelete]
Type: filesandordirs; Name: "{app}\jre"
Type: filesandordirs; Name: "{app}\postgresql"
Type: filesandordirs; Name: "{app}\redis"
Type: filesandordirs; Name: "{app}\checklist.jar"
[Code]
var
  PgMode, RedisMode: TInputOptionWizardPage;
  PgDetails, RedisDetails: TInputQueryWizardPage;
  PgCandidates, RedisCandidates: TNewComboBox;
  ShowPgPassword, ShowRedisPassword: TNewCheckBox;
  Progress: TOutputMarqueeProgressWizardPage;
  DetectionFile, LastSettingsRoot: String;
  LastPgMode, LastRedisMode, LastPgCandidate, LastRedisCandidate: Integer;

function PowerShellPath: String;
begin
  Result := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
end;

procedure OutputLine(const S: String; const Error, FirstLine: Boolean);
begin
  if not Error then begin
    Progress.SetText(S, '자세한 기록: ' + ExpandConstant('{app}\logs'));
    Log(S);
  end;
end;

procedure ExtractSetupHelpers;
begin
  ExtractTemporaryFile('install-config.ps1');
  ExtractTemporaryFile('runtime-support.ps1');
  ExtractTemporaryFile('detect-services.ps1');
  ExtractTemporaryFile('stop-services.ps1');
end;

procedure AddCandidates(Page: TInputOptionWizardPage; var Combo: TNewComboBox; Kind: String);
var I, Count: Integer; Host, Port: String; LabelControl: TNewStaticText;
begin
  Page.CheckListBox.Height := ScaleY(70);
  LabelControl := TNewStaticText.Create(Page);
  LabelControl.Parent := Page.Surface;
  LabelControl.Caption := '이 PC에서 발견한 서버 (입력 화면에서 수정 가능)';
  LabelControl.Top := ScaleY(90); LabelControl.Width := Page.SurfaceWidth;
  Combo := TNewComboBox.Create(Page);
  Combo.Parent := Page.Surface; Combo.Top := ScaleY(115);
  Combo.Width := Page.SurfaceWidth; Combo.Style := csDropDownList;
  Count := GetIniInt(Kind, 'Count', 0, 0, 100, DetectionFile);
  for I := 0 to Count - 1 do begin
    Host := GetIniString(Kind, 'Host'+IntToStr(I), '', DetectionFile);
    Port := GetIniString(Kind, 'Port'+IntToStr(I), '', DetectionFile);
    Combo.Items.Add(Host+':'+Port);
  end;
  if Count > 0 then begin Combo.ItemIndex := 0; Page.SelectedValueIndex := 0; end
  else begin Combo.Items.Add('탐지 결과 없음 — 기존 서버 선택 시 직접 입력'); Combo.ItemIndex := 0; Page.SelectedValueIndex := 1; end;
end;

procedure TogglePgPassword(Sender: TObject);
begin PgDetails.Edits[4].Password := not ShowPgPassword.Checked; end;
procedure ToggleRedisPassword(Sender: TObject);
begin RedisDetails.Edits[2].Password := not ShowRedisPassword.Checked; end;
procedure InitializeWizard;
var Code: Integer;
begin
  ExtractSetupHelpers;
  DetectionFile := ExpandConstant('{tmp}\checklist-detection.ini');
  if not Exec(PowerShellPath, '-NoProfile -ExecutionPolicy Bypass -File "'+ExpandConstant('{tmp}\detect-services.ps1')+'" -OutputFile "'+DetectionFile+'"', '', SW_HIDE, ewWaitUntilTerminated, Code) then
    Log('자동 탐지를 시작하지 못했습니다. 직접 입력을 사용합니다.');
  PgMode := CreateInputOptionPage(wpSelectDir, 'PostgreSQL 설치 방식', '기존 서버를 사용하거나 이 PC에 새로 설치합니다.', '기존 서버가 다른 PC에 있거나 목록에 없으면 다음 화면에서 주소를 입력하세요.', True, False);
  PgMode.Add('기존 PostgreSQL 서버 사용'); PgMode.Add('이 PC에 PostgreSQL 새로 설치'); AddCandidates(PgMode,PgCandidates,'PostgreSQL');
  PgDetails := CreateInputQueryPage(PgMode.ID, 'PostgreSQL 연결 설정', '기본값과 탐지 결과를 수정할 수 있습니다.', '새로 설치할 경우 기본값이 채워집니다. 기존 서버 계정과 비밀번호는 직접 입력하세요.');
  PgDetails.Add('서버 주소:',False); PgDetails.Add('포트:',False); PgDetails.Add('데이터베이스 이름:',False); PgDetails.Add('계정:',False); PgDetails.Add('비밀번호:',True);
  ShowPgPassword := TNewCheckBox.Create(PgDetails); ShowPgPassword.Parent := PgDetails.Surface;
  ShowPgPassword.Top := PgDetails.Edits[4].Top+PgDetails.Edits[4].Height+ScaleY(8);
  ShowPgPassword.Width := PgDetails.SurfaceWidth; ShowPgPassword.Caption := '비밀번호 표시'; ShowPgPassword.OnClick := @TogglePgPassword;
  RedisMode := CreateInputOptionPage(PgDetails.ID, 'Redis 설치 방식', 'PostgreSQL과 별도로 설치 방식을 선택합니다.', '기존 서버가 없으면 이 PC에 새로 설치할 수 있습니다.', True, False);
  RedisMode.Add('기존 Redis 서버 사용'); RedisMode.Add('이 PC에 Redis 새로 설치'); AddCandidates(RedisMode,RedisCandidates,'Redis');
  RedisDetails := CreateInputQueryPage(RedisMode.ID, 'Redis 연결 설정', '기본값과 탐지 결과를 수정할 수 있습니다.', '기존 서버가 비밀번호를 사용하지 않으면 비워 두세요. 신규 설치 비밀번호는 수정할 수 있습니다.');
  RedisDetails.Add('서버 주소:',False); RedisDetails.Add('포트:',False); RedisDetails.Add('비밀번호:',True);
  ShowRedisPassword := TNewCheckBox.Create(RedisDetails); ShowRedisPassword.Parent := RedisDetails.Surface;
  ShowRedisPassword.Top := RedisDetails.Edits[2].Top+RedisDetails.Edits[2].Height+ScaleY(8);
  ShowRedisPassword.Width := RedisDetails.SurfaceWidth; ShowRedisPassword.Caption := '비밀번호 표시'; ShowRedisPassword.OnClick := @ToggleRedisPassword;
  Progress := CreateOutputMarqueeProgressPage('서비스 준비', '데이터베이스와 인증 서버를 준비하고 있습니다.');
  LastPgMode := -1; LastRedisMode := -1; LastPgCandidate := -1; LastRedisCandidate := -1;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := ((PageID=PgMode.ID) or (PageID=PgDetails.ID) or (PageID=RedisMode.ID) or (PageID=RedisDetails.ID)) and FileExists(ExpandConstant('{app}\config\application.properties'));
end;

function ValidPort(Value: String): Boolean;
var Port: Integer;
begin Port := StrToIntDef(Value,0); Result := (Port>=1) and (Port<=65535); end;

function PendingValue(Key: String): String;
var Value: String; I: Integer;
begin
  Value := GetIniString('Pending',Key,'',DetectionFile); Result := ''; I := 1;
  while I<=Length(Value) do begin Result := Result+Chr(StrToIntDef('$'+Copy(Value,I,4),0)); I := I+4; end;
end;
procedure LoadPendingSettings;
var Code: Integer;
begin
  if LastSettingsRoot=WizardDirValue then Exit;
  LastSettingsRoot := WizardDirValue;
  DeleteFile(DetectionFile);
  if not Exec(PowerShellPath,'-NoProfile -ExecutionPolicy Bypass -File "'+ExpandConstant('{tmp}\detect-services.ps1')+'" -OutputFile "'+DetectionFile+'" -Root "'+WizardDirValue+'"','',SW_HIDE,ewWaitUntilTerminated,Code) then Log('재시도 설정 탐지 시작 실패');
  LastPgMode := -1; LastRedisMode := -1;
  if GetIniInt('Pending','Exists',0,0,1,DetectionFile)=1 then begin
    if PendingValue('postgresMode')='new' then PgMode.SelectedValueIndex := 1 else PgMode.SelectedValueIndex := 0;
    PgDetails.Values[0] := PendingValue('dbHost'); PgDetails.Values[1] := PendingValue('dbPort'); PgDetails.Values[2] := PendingValue('dbName'); PgDetails.Values[3] := PendingValue('dbUser'); PgDetails.Values[4] := PendingValue('dbPassword');
    if PendingValue('redisMode')='new' then RedisMode.SelectedValueIndex := 1 else RedisMode.SelectedValueIndex := 0;
    RedisDetails.Values[0] := PendingValue('redisHost'); RedisDetails.Values[1] := PendingValue('redisPort'); RedisDetails.Values[2] := PendingValue('redisPassword');
    LastPgMode := PgMode.SelectedValueIndex; LastRedisMode := RedisMode.SelectedValueIndex;
    LastPgCandidate := PgCandidates.ItemIndex; LastRedisCandidate := RedisCandidates.ItemIndex;
  end;
end;
function NextButtonClick(CurPageID: Integer): Boolean;
var Index: String;
begin
  Result := True;
  if CurPageID=wpSelectDir then LoadPendingSettings;
  if (CurPageID=PgMode.ID) and ((LastPgMode<>PgMode.SelectedValueIndex) or (LastPgCandidate<>PgCandidates.ItemIndex)) then begin
    PgDetails.Values[2] := 'checklist'; PgDetails.Values[3] := 'checklist';
    if PgMode.SelectedValueIndex=1 then begin
      PgDetails.Values[0] := '127.0.0.1'; PgDetails.Values[1] := '5432';
      PgDetails.Values[4] := GetIniString('Defaults','DbPassword','',DetectionFile);
    end else begin
      Index := IntToStr(PgCandidates.ItemIndex);
      PgDetails.Values[0] := GetIniString('PostgreSQL','Host'+Index,'',DetectionFile);
      PgDetails.Values[1] := GetIniString('PostgreSQL','Port'+Index,'',DetectionFile); PgDetails.Values[4] := '';
    end;
    LastPgMode := PgMode.SelectedValueIndex; LastPgCandidate := PgCandidates.ItemIndex;
  end;
  if (CurPageID=RedisMode.ID) and ((LastRedisMode<>RedisMode.SelectedValueIndex) or (LastRedisCandidate<>RedisCandidates.ItemIndex)) then begin
    if RedisMode.SelectedValueIndex=1 then begin
      RedisDetails.Values[0] := '127.0.0.1'; RedisDetails.Values[1] := '6379'; RedisDetails.Values[2] := GetIniString('Defaults','RedisPassword','',DetectionFile);
    end else begin
      Index := IntToStr(RedisCandidates.ItemIndex);
      RedisDetails.Values[0] := GetIniString('Redis','Host'+Index,'',DetectionFile);
      RedisDetails.Values[1] := GetIniString('Redis','Port'+Index,'',DetectionFile); RedisDetails.Values[2] := '';
    end;
    LastRedisMode := RedisMode.SelectedValueIndex; LastRedisCandidate := RedisCandidates.ItemIndex;
  end;
  if CurPageID=PgDetails.ID then begin
    Result := (Trim(PgDetails.Values[0])<>'') and ValidPort(PgDetails.Values[1]) and (Trim(PgDetails.Values[2])<>'') and (Trim(PgDetails.Values[3])<>'') and (PgDetails.Values[4]<>'');
    if not Result then MsgBox('PostgreSQL 주소·포트·DB 이름·계정·비밀번호를 확인해 주세요.',mbError,MB_OK);
  end;
  if CurPageID=RedisDetails.ID then begin
    Result := (Trim(RedisDetails.Values[0])<>'') and ValidPort(RedisDetails.Values[1]) and ((RedisMode.SelectedValueIndex=0) or (RedisDetails.Values[2]<>''));
    if not Result then MsgBox('Redis 주소·포트와 신규 설치 비밀번호를 확인해 주세요.',mbError,MB_OK);
  end;
end;

function Json(Value: String): String;
begin
  StringChangeEx(Value,'\','\\',True); StringChangeEx(Value,'"','\"',True);
  StringChangeEx(Value,#13,'\r',True); StringChangeEx(Value,#10,'\n',True); StringChangeEx(Value,#9,'\t',True);
  Result := '"'+Value+'"';
end;
function ModeValue(Page: TInputOptionWizardPage): String;
begin if Page.SelectedValueIndex=1 then Result := 'new' else Result := 'existing'; end;

procedure SaveSettings(Path: String);
var Value: String; Code: Integer;
begin
  ForceDirectories(ExtractFileDir(Path));
  if not SaveStringToFile(Path,'',False) then RaiseException('설정 파일을 만들지 못했습니다.');
  if (not Exec(ExpandConstant('{sys}\icacls.exe'),'"'+Path+'" /inheritance:r /grant:r "*S-1-5-18:(F)" "*S-1-5-32-544:(F)"','',SW_HIDE,ewWaitUntilTerminated,Code)) or (Code<>0) then
    RaiseException('설정 파일 접근 권한을 제한하지 못했습니다.');
  Value := '{"postgresMode":'+Json(ModeValue(PgMode))+',"dbHost":'+Json(PgDetails.Values[0])+',"dbPort":'+Json(PgDetails.Values[1])+',"dbName":'+Json(PgDetails.Values[2])+',"dbUser":'+Json(PgDetails.Values[3])+',"dbPassword":'+Json(PgDetails.Values[4])+',"redisMode":'+Json(ModeValue(RedisMode))+',"redisHost":'+Json(RedisDetails.Values[0])+',"redisPort":'+Json(RedisDetails.Values[1])+',"redisPassword":'+Json(RedisDetails.Values[2])+'}';
  if not SaveStringToFile(Path,Utf8Encode(Value),False) then RaiseException('설정 파일을 저장하지 못했습니다.');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer; Started: Boolean; Params, Settings, ErrorText: String; RawError: AnsiString;
begin
  if CurStep=ssInstall then begin
    if FileExists(ExpandConstant('{app}\checklist-service.exe')) then
      if (not Exec(PowerShellPath,'-NoProfile -ExecutionPolicy Bypass -File "'+ExpandConstant('{tmp}\stop-services.ps1')+'" -Root "'+ExpandConstant('{app}')+'"','',SW_HIDE,ewWaitUntilTerminated,Code)) or (Code<>0) then RaiseException('기존 서비스 중단에 실패했습니다. 실행 중인 서비스와 설치 경로를 확인해 주세요.');
  end;
  if CurStep=ssPostInstall then begin
    Settings := ExpandConstant('{app}\config\setup-input.json');
    Params := '-NoProfile -ExecutionPolicy Bypass -File "'+ExpandConstant('{app}\install-runtime.ps1')+'" -Root "'+ExpandConstant('{app}')+'"';
    if not FileExists(ExpandConstant('{app}\config\application.properties')) then begin SaveSettings(Settings); Params := Params+' -SettingsFile "'+Settings+'"'; end;
    Progress.Show;
    try
      Progress.Animate;
      Started := ExecAndLogOutput(PowerShellPath,Params,ExpandConstant('{app}'),SW_HIDE,ewWaitUntilTerminated,Code,@OutputLine);
      if (not Started) or (Code<>0) then begin
        ErrorText := '서비스 설정에 실패했습니다. 설정과 데이터는 보존됩니다.';
        if LoadStringFromFile(ExpandConstant('{app}\logs\install-error.txt'),RawError) then ErrorText := ErrorText+#13#10+Utf8Decode(RawError);
        RaiseException(ErrorText+#13#10+'자세한 기록: '+ExpandConstant('{app}\logs'));
      end;
    finally Progress.Hide; DeleteFile(Settings); end;
  end;
end;
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var Code: Integer;
begin
  if CurUninstallStep=usUninstall then
    if (not Exec(PowerShellPath,'-NoProfile -ExecutionPolicy Bypass -File "'+ExpandConstant('{app}\install-runtime.ps1')+'" -Action uninstall -Root "'+ExpandConstant('{app}')+'"','',SW_HIDE,ewWaitUntilTerminated,Code)) or (Code<>0) then RaiseException('서비스 해제에 실패했습니다. 데이터를 보존하고 제거를 중단합니다.');
end;
procedure DeinitializeSetup;
begin if DetectionFile<>'' then DeleteFile(DetectionFile); end;