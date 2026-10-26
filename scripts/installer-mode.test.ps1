[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Compiler)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'install-config.ps1')
$testBase=Join-Path $repo ('build/installer mode '+[guid]::NewGuid().ToString('N'))
$stage=Join-Path $testBase 'stage';$output=Join-Path $testBase 'output'
foreach($directory in @('postgresql','redis','licenses',$output)){
 $path=if($directory -eq $output){$output}else{Join-Path $stage $directory}
 New-Item -ItemType Directory -Force -Path $path | Out-Null
}
foreach($file in @('postgresql/keep.txt','redis/keep.txt','licenses/keep.txt','redis-service.exe','checklist.jar')){[IO.File]::WriteAllText((Join-Path $stage $file),'검증용')}
foreach($file in @('detect-services.ps1','install-config.ps1','runtime-support.ps1','stop-services.ps1','stop-checklist.ps1')){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $stage}
$source=[IO.File]::ReadAllText((Join-Path $repo 'installer/checklist.iss'))
$source=$source.Replace('AppId={{C5E9D885-726D-40B7-9A65-C0FFEE57A001}',('AppId=CheckListModeTest'+[guid]::NewGuid().ToString('N'))).Replace('PrivilegesRequired=admin','PrivilegesRequired=lowest').Replace('Uninstallable=yes',('Uninstallable=yes'+[Environment]::NewLine+'CreateUninstallRegKey=no'+[Environment]::NewLine+'UsePreviousAppDir=no')).Replace('Compression=lzma2','Compression=none').Replace('SolidCompression=yes','SolidCompression=no')
# 실제 설치 직전에 중단하며 제품의 안내·화면 생략·설치 요약을 실제 Inno에서 실행한다.
$probe=@'
  if CurPageID=InstallModePage.ID then begin
    Log('MODE_CAPTION='+InstallModePage.Caption);
    Log('MODE_MESSAGE='+InstallModePage.MsgLabel.Caption);
    if ExpandConstant('{param:MODETESTTARGET|}')<>'' then begin
      WizardForm.DirEdit.Text := ExpandConstant('{param:MODETESTTARGET}');
      RefreshInstallationMode;
      Log('CHANGED_CAPTION='+InstallModePage.Caption);
    end;
  end;
  if CurPageID=PgDetails.ID then begin
    Log('PG_INPUT_SEEN');
    PgDetails.Values[0] := '127.0.0.1'; PgDetails.Values[1] := '5544'; PgDetails.Values[2] := 'fixture'; PgDetails.Values[3] := 'fixture'; PgDetails.Values[4] := 'fixture';
  end;
  if CurPageID=RedisDetails.ID then begin
    Log('REDIS_INPUT_SEEN');
    RedisDetails.Values[0] := '127.0.0.1'; RedisDetails.Values[1] := '6388'; RedisDetails.Values[2] := 'fixture';
  end;
  if CurPageID=wpReady then begin
    Log('READY_MEMO='+WizardForm.ReadyMemo.Text);
    Log('MODE_TEST_STOP_BEFORE_INSTALL');
    Result := False; Exit;
  end;
'@
$pattern='(function NextButtonClick\(CurPageID: Integer\): Boolean;[\s\S]*?\bbegin\r?\n)'
if(![regex]::IsMatch($source,$pattern)){throw '설치 시험 삽입 위치를 찾지 못했습니다.'}
$source=[regex]::Replace($source,$pattern,('$1'+$probe+[Environment]::NewLine))
$iss=Join-Path $testBase 'mode-test.iss'
[IO.File]::WriteAllText($iss,$source,[Text.UTF8Encoding]::new($true))
& $Compiler /Q /DAppVersion=0.0.0 ('/DStageDir='+$stage) ('/DOutputDir='+$output) $iss *> (Join-Path $testBase 'compile.log')
if($LASTEXITCODE -ne 0){throw ('설치 방식 시험 컴파일 실패: '+$testBase)}
function Assert($value,[string]$message){if(!$value){throw $message}}
foreach($case in @('new','update','retained-config','pending','change-path')){
 $target=Join-Path $testBase $case;$config=Join-Path $target 'config'
 New-Item -ItemType Directory -Force -Path $config | Out-Null
 $existing=$case -in @('update','retained-config','change-path')
 if($existing){[IO.File]::WriteAllText((Join-Path $config 'application.properties'),'보존할 완료 설정')}
 if($case -eq 'update'){[IO.File]::WriteAllText((Join-Path $target 'checklist-service.exe'),'기존 앱')}
 if($case -eq 'pending'){
  $settings=@{postgresMode='new';dbHost='127.0.0.1';dbPort=5544;dbName='fixture';dbUser='fixture';dbPassword='fixture-db';redisMode='new';redisHost='127.0.0.1';redisPort=6388;redisPassword='fixture-redis'}
  [IO.File]::WriteAllText((Join-Path $config 'setup-pending.json'),((ConvertTo-InstallState $settings)|ConvertTo-Json -Depth 5),[Text.UTF8Encoding]::new($false))
 }
 $log=Join-Path $testBase ($case+'.log')
 $arguments='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /DIR="'+$target+'" /LOG="'+$log+'"'
 if($case -eq 'change-path'){$arguments+=' /MODETESTTARGET="'+(Join-Path $testBase 'changed-empty')+'"'}
 $process=Start-Process -FilePath (Join-Path $output 'checklist-setup-0.0.0.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru
 $null=$process.Handle
 try{
  $watch=[Diagnostics.Stopwatch]::StartNew()
  while(!$process.WaitForExit(200)){if($watch.Elapsed.TotalSeconds -gt 60){Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue;throw ('설치 방식 시험 시간 초과: '+$case)}}
  $process.Refresh();Assert ($process.ExitCode -ne 0) '시험 설치가 중단되지 않음'
 }finally{$process.Dispose()}
 $text=[IO.File]::ReadAllText($log)
 $initialMode=if($existing){'업데이트'}else{'신규 설치'}
 $finalUpdate=$existing -and $case -ne 'change-path'
 $finalMode=if($finalUpdate){'업데이트'}else{'신규 설치'}
 Assert ($text.Contains('MODE_CAPTION=CheckList '+$initialMode)) ('설치 방식 안내 오류: '+$case)
 Assert ($text.Contains('MODE_TEST_STOP_BEFORE_INSTALL')) ('설치 직전 요약에 도달하지 못함: '+$case)
 Assert ($text.Contains('READY_MEMO=설치 방식: '+$finalMode)) ('설치 요약 방식 오류: '+$case)
 Assert ($text.Contains('PG_INPUT_SEEN') -eq !$finalUpdate) ('PostgreSQL 입력 화면 분기 오류: '+$case)
 Assert ($text.Contains('REDIS_INPUT_SEEN') -eq !$finalUpdate) ('Redis 입력 화면 분기 오류: '+$case)
 if($case -eq 'change-path'){Assert ($text.Contains('CHANGED_CAPTION=CheckList 신규 설치')) '폴더 변경 후 안내가 갱신되지 않음'}
 if($existing){Assert ([IO.File]::ReadAllText((Join-Path $config 'application.properties')) -eq '보존할 완료 설정') '기존 설정이 변경됨'}
 Assert (!(Test-Path -LiteralPath (Join-Path $target 'checklist.jar'))) '시험 중 앱 파일이 설치됨'
 Write-Host ('실제 설치 방식 안내 검사 통과: '+$case)
}
Write-Host ('설치 방식 시험 로그: '+$testBase)
