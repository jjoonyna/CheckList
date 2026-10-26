[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Compiler)
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$testBase=Join-Path $repo ('build/installer-test-logs/encoding-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testBase | Out-Null
$utf8=[Text.UTF8Encoding]::new($true)
$runtime=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'install-runtime.ps1'))
$initialization=[regex]::Match($runtime,'(?m)^\[Console\]::OutputEncoding=.*$').Value
$installer=[IO.File]::ReadAllText((Join-Path $repo 'installer/checklist.iss'))
$callback=[regex]::Match($installer,'procedure OutputLine\([\s\S]*?\r?\nend;').Value
if(!$callback){throw '설치 진행 출력 콜백을 찾지 못했습니다.'}
$probe=@'
param([string]$Root,[int]$CodePage,[switch]$Fixed)
[Console]::OutputEncoding=[Text.Encoding]::GetEncoding($CodePage)
ENCODING_INITIALIZATION
. 'RUNTIME_SUPPORT'
New-Item -ItemType Directory -Force -Path (Join-Path $Root 'logs') | Out-Null
Write-SetupStatus '한글 설치 진행 · 연결 확인'
[Console]::Error.WriteLine('한글 오류: 서비스 설정 실패')
[IO.File]::WriteAllText((Join-Path $Root 'logs/install-error.txt'),'한글 오류: 서비스 설정 실패',[Text.UTF8Encoding]::new($false))
'@
# Windows PowerShell이 한글 소스도 일관되게 읽도록 BOM을 유지한다.
$probe=$probe.Replace('ENCODING_INITIALIZATION',('if($Fixed){'+$initialization+'}')).Replace('RUNTIME_SUPPORT',(Join-Path $PSScriptRoot 'runtime-support.ps1').Replace("'","''"))
$probePath=Join-Path $testBase '한글 출력 시험.ps1'
[IO.File]::WriteAllText($probePath,$probe,$utf8)
$source=@'
[Setup]
AppName=CheckList 한글 출력 시험
AppVersion=0.0.0
DefaultDirName={tmp}\CheckListEncodingProbe
CreateAppDir=no
Uninstallable=no
PrivilegesRequired=lowest
OutputDir=OUTPUT
OutputBaseFilename=encoding-probe
Compression=none
[Code]
var Progress: TOutputMarqueeProgressWizardPage;
CALLBACK
procedure Capture(const S: String; const Error, FirstLine: Boolean);
begin
  if Error then RaiseException('출력 읽기 실패');
  OutputLine(S, Error, FirstLine);
  SaveStringToFile(ExpandConstant('{param:RESULT}'), Utf8Encode(S+#13#10), True);
end;
procedure CurStepChanged(CurStep: TSetupStep);
var Code: Integer; Params, Root: String; RawError: AnsiString;
begin
  if CurStep<>ssPostInstall then Exit;
  Root := ExpandConstant('{param:ROOT}');
  Progress := CreateOutputMarqueeProgressPage('한글 출력 시험','');
  Params := '-NoProfile -ExecutionPolicy Bypass -File "PROBE" -Root "'+Root+'" -CodePage '+ExpandConstant('{param:CP}');
  if ExpandConstant('{param:FIXED}')='1' then Params := Params+' -Fixed';
  if not ExecAndLogOutput(ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe'),Params,'',SW_HIDE,ewWaitUntilTerminated,Code,@Capture) then RaiseException('시험 실행 실패');
  if Code<>0 then RaiseException('시험 프로세스 실패');
  if not LoadStringFromFile(Root+'\logs\install-error.txt',RawError) then RaiseException('오류 파일 누락');
  SaveStringToFile(ExpandConstant('{param:RESULT}')+'.error',Utf8Encode(Utf8Decode(RawError)),False);

end;
'@
$source=$source.Replace('OUTPUT',$testBase).Replace('PROBE',$probePath).Replace('CALLBACK',$callback)
$iss=Join-Path $testBase 'encoding.iss'
[IO.File]::WriteAllText($iss,$source,$utf8)
& $Compiler /Q $iss *> (Join-Path $testBase 'compile.log')
if($LASTEXITCODE -ne 0){throw ('한글 출력 시험 컴파일 실패: '+$testBase)}
foreach($cp in @(949,437,65001)){
 foreach($fixed in @($false,$true)){
  $case="$cp-$fixed";$result=Join-Path $testBase ($case+'.txt');$root=Join-Path $testBase ('한글 경로 '+$case)
  $arguments='/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP- /ROOT="'+$root+'" /RESULT="'+$result+'" /CP='+$cp+' /FIXED='+[int]$fixed
  $process=Start-Process -FilePath (Join-Path $testBase 'encoding-probe.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru
  $null=$process.Handle
  try{if(!$process.WaitForExit(30000)){$process.Kill();throw ('한글 출력 시험 시간 초과: '+$case)}}finally{$process.Dispose()}
  if(!(Test-Path -LiteralPath $result)){throw ('한글 출력 시험 결과 누락: '+$case)}
  $text=[IO.File]::ReadAllText($result)
  $valid=$text.Contains('[설치] 한글 설치 진행 · 연결 확인') -and $text.Contains('한글 오류: 서비스 설정 실패')
  if(($fixed -or $cp -eq 65001) -and !$valid){throw ('설치 진행 한글 깨짐: '+$case)}
  if(!$fixed -and $cp -ne 65001 -and $valid){throw ('기존 인코딩 문제 재현 실패: '+$case)}
  if([IO.File]::ReadAllText($result+'.error') -ne '한글 오류: 서비스 설정 실패'){throw ('오류 파일 한글 깨짐: '+$case)}
  if(![IO.File]::ReadAllText((Join-Path $root 'logs/install.log')).Contains('한글 설치 진행 · 연결 확인')){throw ('설치 로그 한글 깨짐: '+$case)}
  Write-Host ('실제 설치 출력 인코딩 검사 통과: '+$case+', 한글 정상='+$valid)
 }
}
if(!$initialization){throw '설치 출력 UTF-8 초기화가 없습니다.'}
Write-Host ('한글 출력 시험 로그: '+$testBase)