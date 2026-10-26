[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Compiler,[Parameter(Mandatory=$true)][string]$WinSW,[ValidateSet('keep','remove','cancel','foreign-service','missing-wrapper','stop','failure')][string[]]$Cases=@('keep','remove','cancel','foreign-service','missing-wrapper','stop','failure'))
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(!([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw '실제 제거 검사는 관리자 권한으로 실행해 주세요.'}
$repo=Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'install-config.ps1')
. (Join-Path $PSScriptRoot 'runtime-support.ps1')
$testBase=Join-Path $env:ProgramData ('CheckList uninstall test '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testBase | Out-Null
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class UninstallDialogTest {
 public delegate bool EnumProc(IntPtr h,IntPtr d);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p,IntPtr d);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h,EnumProc p,IntPtr d);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h,StringBuilder b,int n);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h,out uint id);
 [DllImport("user32.dll",SetLastError=true)] public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h,IntPtr a,int x,int y,int w,int z,uint f);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h,StringBuilder b,int n);
 public static string Class(IntPtr h){var b=new StringBuilder(256);GetClassName(h,b,b.Capacity);return b.ToString();}
 public static string Contents(IntPtr h){var b=new StringBuilder(Text(h));EnumChildWindows(h,(c,v)=>{b.Append(" | ").Append(Text(c));return true;},IntPtr.Zero);return b.ToString();}
 public static IntPtr FindError(int[] ids){
  var h=Find("","Runtime error",ids);if(h!=IntPtr.Zero)return h;
  h=Find("","제거를 완료하지 못했습니다",ids);if(h!=IntPtr.Zero)return h;
  IntPtr found=IntPtr.Zero;
  EnumWindows((w,d)=>{uint pid;GetWindowThreadProcessId(w,out pid);if(Array.IndexOf(ids,(int)pid)>=0 && Class(w)=="#32770" && Buttons(w).Length==1){found=w;return false;}return true;},IntPtr.Zero);return found;
 }
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
 public static IntPtr[] Buttons(IntPtr h){var buttons=new System.Collections.Generic.List<IntPtr>();EnumChildWindows(h,(c,d)=>{if(Class(c)=="Button")buttons.Add(c);return true;},IntPtr.Zero);return buttons.ToArray();}
 public static bool TryCloseError(IntPtr h,int[] ids){
  uint pid;GetWindowThreadProcessId(h,out pid);
  if(Array.IndexOf(ids,(int)pid)<0 || Class(h)!="#32770")return false;
  var text=Contents(h);
  if(text.IndexOf("Runtime error",StringComparison.OrdinalIgnoreCase)<0 && text.IndexOf("제거를 완료하지 못했습니다",StringComparison.OrdinalIgnoreCase)<0)return false;
  var buttons=Buttons(h);
  if(buttons.Length!=1 || !IsWindowEnabled(buttons[0]))return false;
  // 확인 버튼 ID에 의존하지 않고, 검증한 오류 창에만 닫기 요청을 보낸다.
  if(!PostMessage(h,0x10,IntPtr.Zero,IntPtr.Zero))throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
  return true;
 }
 public static string Dump(int[] ids){var b=new StringBuilder();EnumWindows((h,d)=>{uint pid;GetWindowThreadProcessId(h,out pid);if(Array.IndexOf(ids,(int)pid)>=0){b.AppendLine("PID="+pid+" HWND="+h+" class="+Class(h)+" text="+Contents(h));EnumChildWindows(h,(c,v)=>{b.AppendLine("  HWND="+c+" id="+GetDlgCtrlID(c)+" class="+Class(c)+" text="+Text(c));return true;},IntPtr.Zero);}return true;},IntPtr.Zero);return b.ToString();}
 public static string Text(IntPtr h){var b=new StringBuilder(4096);GetWindowText(h,b,b.Capacity);return b.ToString();}
 public static IntPtr Find(string title,string content,int[] ids){IntPtr result=IntPtr.Zero;EnumWindows((h,d)=>{uint pid;GetWindowThreadProcessId(h,out pid);if(Array.IndexOf(ids,(int)pid)>=0 && Text(h).IndexOf(title,StringComparison.OrdinalIgnoreCase)>=0){var b=new StringBuilder(Text(h));EnumChildWindows(h,(c,v)=>{b.Append(Text(c));return true;},IntPtr.Zero);if(b.ToString().IndexOf(content,StringComparison.OrdinalIgnoreCase)>=0){result=h;return false;}}return true;},IntPtr.Zero);return result;}
}
"@
function Assert($Value,[string]$Message){if(!$Value){throw $Message}}
function Stop-TestProcess([Diagnostics.Process]$Process){
 try{if(!$Process.HasExited){& (Join-Path $env:SystemRoot 'System32/taskkill.exe') /PID $Process.Id /T /F 2>&1 | Out-Null;$null=$Process.WaitForExit(5000)}}catch{Write-Warning ('시험 프로세스 종료 확인 실패: '+$_.Exception.Message)}
}
function Get-TestProcessIds([int]$ProcessId){
 $ids=[Collections.Generic.List[int]]::new();$ids.Add($ProcessId)
 for($index=0;$index -lt $ids.Count;$index++){foreach($child in @(Get-CimInstance Win32_Process -Filter ('ParentProcessId='+$ids[$index]))){if(!$ids.Contains([int]$child.ProcessId)){$ids.Add([int]$child.ProcessId)}}}
 return $ids.ToArray()
}
function Publish-TestLogs {
 $destination=Join-Path $repo ('build/installer-test-logs/'+(Split-Path -Leaf $testBase))
 foreach($file in @(Get-ChildItem -LiteralPath $testBase -Recurse -File | Where-Object Extension -in @('.log','.out','.error'))){
  $path=Join-Path $destination $file.FullName.Substring($testBase.Length+1)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $path) | Out-Null
  Copy-Item -LiteralPath $file.FullName -Destination $path
 }
}
function Test-DialogSearch {
 $probe=@'
param([string]$Kind)
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class NativeUninstallErrorProbe { [DllImport("user32.dll",CharSet=CharSet.Unicode)] public static extern int MessageBox(IntPtr h,string text,string title,uint flags); }'
$message=if($Kind -eq 'lower'){'Runtime error: 제거를 완료하지 못했습니다.'}else{'Runtime Error: 제거를 완료하지 못했습니다.'}
$buttons=if($Kind -eq 'choice'){3}else{0}
$result=[NativeUninstallErrorProbe]::MessageBox([IntPtr]::Zero,$message,'제거 오류 창 검증',[uint32](16+$buttons))
if($Kind -ne 'choice' -and $result -ne 1){exit 3}
'@
 $path=Join-Path $testBase 'dialog-probe.ps1';[IO.File]::WriteAllText($path,$probe,[Text.UTF8Encoding]::new($true))
 foreach($kind in @('upper','lower','choice')){
  $process=Start-Process (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "'+$path+'" -Kind '+$kind) -WindowStyle Hidden -PassThru
  $null=$process.Handle
  try{
   $ids=[int[]]@($process.Id);$found=[IntPtr]::Zero
   for($attempt=0;$attempt -lt 80;$attempt++){$found=[UninstallDialogTest]::FindError($ids);if($found -ne [IntPtr]::Zero){break};Start-Sleep -Milliseconds 100}
   Assert ($found -ne [IntPtr]::Zero) ('실제 Windows 오류 창 감지 실패: '+$kind)
   Assert ([UninstallDialogTest]::FindError([int[]]@(-1)) -eq [IntPtr]::Zero) '다른 프로세스 창이 감지됐습니다.'
   Assert (![UninstallDialogTest]::TryCloseError($found,[int[]]@(-1))) '다른 프로세스의 오류 창에 닫기를 요청했습니다.'
   [void][UninstallDialogTest]::SetWindowPos($found,[IntPtr]::Zero,-32000,-32000,0,0,0x15)
   if($kind -eq 'choice'){
    for($attempt=0;$attempt -lt 40;$attempt++){if(([UninstallDialogTest]::Buttons($found)).Length -eq 3){break};Start-Sleep -Milliseconds 100}
    Assert (([UninstallDialogTest]::Buttons($found)).Length -eq 3) '복수 선택 창의 버튼 준비 실패'
    Assert (![UninstallDialogTest]::TryCloseError($found,$ids)) '선택이 필요한 창에 닫기를 요청했습니다.'
    Assert (!$process.HasExited) '선택이 필요한 창을 자동 종료했습니다.'
    $diagnostic=[UninstallDialogTest]::Dump($ids)
   }else{
    $requested=$false
    for($attempt=0;$attempt -lt 80;$attempt++){
     $diagnostic=[UninstallDialogTest]::Dump($ids)
     $requested=[UninstallDialogTest]::TryCloseError($found,$ids)
     if($requested){break};Start-Sleep -Milliseconds 100
    }
    Assert $requested ('실제 오류 창 닫기 요청 실패: '+$kind)
    Assert ($process.WaitForExit(5000)) ('실제 오류 창을 닫은 뒤 프로세스가 끝나지 않았습니다: '+$kind)
    $process.Refresh();Assert ($process.ExitCode -eq 0) ('오류 창 닫기 결과가 확인 버튼과 다릅니다: '+$kind)
   }
   [IO.File]::AppendAllText((Join-Path $testBase 'dialog-probe.log'),$kind+[Environment]::NewLine+$diagnostic,[Text.UTF8Encoding]::new($false))
  }finally{Stop-TestProcess $process;$process.Dispose()}
 }
 Write-Host '실제 Windows 오류 창 감지·닫기·프로세스 종료 및 타 PID·선택 창 보호 검사 통과'
}
function Run-Hidden([string]$File,[string]$Arguments,[string]$Log,[int]$ExpectedExit=0){
 $process=Start-Process -FilePath $File -ArgumentList $Arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput ($Log+'.out') -RedirectStandardError ($Log+'.error')
 $null=$process.Handle
 try{$watch=[Diagnostics.Stopwatch]::StartNew();while(!$process.WaitForExit(200)){if($watch.Elapsed.TotalSeconds -gt 90){throw '시험 설치·서비스 명령 시간 초과'}};$process.Refresh();if($process.ExitCode -ne $ExpectedExit){throw ('시험 명령 실패: '+$File+' 종료='+$process.ExitCode)}}finally{Stop-TestProcess $process;$process.Dispose()}
}
function New-ServiceFixture([string]$Executable,[string]$Name){
 $arguments=[Security.SecurityElement]::Escape('-NoProfile -Command "Start-Sleep -Seconds 600"')
 $xml='<service><id>'+$Name+'</id><name>'+$Name+'</name><description>CheckList 제거 기능 검증용 임시 서비스</description><executable>'+[Security.SecurityElement]::Escape((Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe'))+'</executable><arguments>'+$arguments+'</arguments><logpath>%BASE%\logs</logpath><log mode="roll"/><stoptimeout>2 sec</stoptimeout></service>'
 [IO.File]::WriteAllText([IO.Path]::ChangeExtension($Executable,'.xml'),$xml,[Text.UTF8Encoding]::new($false))
 Run-Hidden $Executable 'install' ($Executable+'.install')
 Start-Service -Name $Name
}
$newSource=[IO.File]::ReadAllText((Join-Path $repo 'installer/checklist.iss'))
# 0.0.3의 자동 파일 제거 및 추가 폴더 제거 정책을 독립적으로 재현한다.
$legacyFiles=@"
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
"@
$filesStart=$newSource.IndexOf('[Files]');$codeStart=$newSource.IndexOf('[Code]')
$oldSource=($newSource.Substring(0,$filesStart)+$legacyFiles+"`n"+$newSource.Substring($codeStart)).Replace('UninstallLogMode=overwrite','UninstallLogMode=append')
try{
Test-DialogSearch
foreach($case in $Cases){
 $id=[guid]::NewGuid().ToString('N');$prefix='CheckListRemovalTest'+$id;$root=Join-Path $testBase $case;$stage=Join-Path $root 'stage';$target=Join-Path $root 'installed';$output=Join-Path $root 'output';$title='제거검증'+$id
 foreach($directory in @('postgresql/bin','redis','jre','licenses')){New-Item -ItemType Directory -Force -Path (Join-Path $stage $directory) | Out-Null}
 foreach($file in @('postgresql/keep.txt','redis/keep.txt','jre/keep.txt','licenses/keep.txt','checklist.jar')){[IO.File]::WriteAllText((Join-Path $stage $file),'검증용')}
 foreach($file in @('checklist-service.exe','redis-service.exe','postgresql/bin/pg_ctl.exe')){Copy-Item -LiteralPath $WinSW -Destination (Join-Path $stage $file)}
 foreach($file in @('install-runtime.ps1','runtime-support.ps1','install-config.ps1','stop-services.ps1','stop-checklist.ps1','detect-services.ps1')){
  $source=[IO.File]::ReadAllText((Join-Path $PSScriptRoot $file)).Replace('CheckList',$prefix)
  [IO.File]::WriteAllText((Join-Path $stage $file),$source,[Text.UTF8Encoding]::new($true))
 }
 foreach($directory in @('config','data/redis','data/postgres','data/attachments',$output)){ $full=if($directory -eq $output){$output}else{Join-Path $target $directory};New-Item -ItemType Directory -Force -Path $full | Out-Null}
 Protect-Configuration (Join-Path $target 'config')
 foreach($file in @('config/application.properties','config/bundled-redis.marker','config/bundled-postgresql.marker','config/redis.conf','data/redis/session.txt','data/postgres/PG_VERSION','data/attachments/keep.txt')){if($file.StartsWith('config/')){Write-ProtectedText (Join-Path $target $file) '보존 검증'}else{[IO.File]::WriteAllText((Join-Path $target $file),'보존 검증')}}
 $names=@($prefix,($prefix+'Redis'),($prefix+'PostgreSQL'))
 try{
  foreach($version in @('old','new')){
   $source=if($version -eq 'old'){$oldSource}else{$newSource}
   $source=$source.Replace('AppId={{C5E9D885-726D-40B7-9A65-C0FFEE57A001}',('AppId='+$prefix)).Replace('AppName=CheckList',('AppName='+$title)).Replace('DefaultDirName={autopf}\CheckList',('DefaultDirName='+$target)).Replace('Uninstallable=yes',"Uninstallable=yes`nCreateUninstallRegKey=no").Replace('CloseApplications=yes','CloseApplications=no').Replace('Compression=lzma2','Compression=none').Replace('SolidCompression=yes','SolidCompression=no').Replace('{autoprograms}\CheckList','{app}\test-shortcuts')
   # 설치 부작용은 건너뛰되 제품의 파일 목록·제거 질문·제거 훅은 그대로 검증한다.
   $source=[regex]::Replace($source,'(procedure CurStepChanged\(CurStep: TSetupStep\);[\s\S]*?\bbegin)','$1'+"`n  Exit;")
   $iss=Join-Path $root ($version+'.iss');[IO.File]::WriteAllText($iss,$source,[Text.UTF8Encoding]::new($true))
   Run-Hidden $Compiler ('/Q "/DStageDir='+$stage+'" "/DOutputDir='+$output+'" "/DAppVersion=0.0.4" "'+$iss+'"') (Join-Path $root ($version+'-compile'))
   Run-Hidden (Join-Path $output 'checklist-setup-0.0.4.exe') '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART /SP-' (Join-Path $root ($version+'-install'))
  }
  $appExe=Join-Path $target 'checklist-service.exe'
  if($case -eq 'foreign-service'){$appExe=Join-Path $target 'other-service.exe';Copy-Item -LiteralPath $WinSW -Destination $appExe}
  New-ServiceFixture $appExe $prefix
  New-ServiceFixture (Join-Path $target 'redis-service.exe') ($prefix+'Redis')
  New-ServiceFixture (Join-Path $target 'postgresql/bin/pg_ctl.exe') ($prefix+'PostgreSQL')
  if($case -eq 'failure'){
   $properties=@('spring.data.redis.host=127.0.0.1','spring.data.redis.port=6388','spring.data.redis.password=fixture')
   Write-ProtectedText (Join-Path $target 'config/application.properties') ($properties -join [Environment]::NewLine)
   $before=[IO.File]::ReadAllBytes((Join-Path $target 'config/application.properties'))
   $supportPath=Join-Path $target 'runtime-support.ps1'
   [IO.File]::AppendAllText($supportPath,([Environment]::NewLine+'function Test-RedisConnection {param($Server,$Port,$Password) throw ''검증용 Redis 연결 실패''}'+[Environment]::NewLine),[Text.UTF8Encoding]::new($false))
   Run-Hidden (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') ('-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $target 'install-runtime.ps1')+'" -Root "'+$target+'" -Action upgrade') (Join-Path $root 'failed-install') 1
   Assert ((Get-Service $prefix).Status -eq 'Stopped') '설치 실패 후 앱 서비스가 실행 중'
   Assert ((Get-Service ($prefix+'Redis')).Status -eq 'Running') '설치 실패가 Redis를 중단함'
   Assert ((Get-Service ($prefix+'PostgreSQL')).Status -eq 'Running') '설치 실패가 PostgreSQL을 중단함'
   foreach($relative in @('checklist-service.exe','redis-service.exe','postgresql/bin/pg_ctl.exe','checklist.jar','data/redis/session.txt','data/postgres/PG_VERSION','data/attachments/keep.txt')){Assert (Test-Path (Join-Path $target $relative)) ('실패 후 파일 유실: '+$relative)}
   Assert ([Convert]::ToBase64String($before) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $target 'config/application.properties')))) '실패 후 설정 변경'
   $errorText=[IO.File]::ReadAllText((Join-Path $target 'logs/install-error.txt'))
   Assert ($errorText.Contains('검증용 Redis 연결 실패')) '설치 실패 원인 기록 유실'
   Write-Host '실제 설치 실패 시 앱 중단·DB/Redis 실행·설정/파일/데이터 보존 통과'
   continue
  }
  if($case -eq 'stop'){
   Run-Hidden (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') ('-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $target 'stop-checklist.ps1')+'" -Root "'+$target+'" -Quiet') (Join-Path $root 'stop-app')
   Assert ((Get-Service $prefix).Status -eq 'Stopped') '앱 종료 실패'
   Assert ((Get-Service ($prefix+'Redis')).Status -eq 'Stopped') '전용 Redis 종료 실패'
   Assert ((Get-Service ($prefix+'PostgreSQL')).Status -eq 'Running') '종료 기능이 PostgreSQL을 중단함'
   Assert (Test-Path (Join-Path $target 'data/redis/session.txt')) '종료 기능이 Redis 데이터를 삭제함'
   Assert (Test-Path (Join-Path $target 'test-shortcuts/CheckList 종료.lnk')) '종료 바로가기가 누락됨'
   Start-Service $prefix;Start-Service ($prefix+'Redis')
   Write-Host '실제 앱·전용 Redis 종료 및 PostgreSQL·데이터 보존 통과'
  }
  if($case -eq 'missing-wrapper'){
   [void](Stop-OwnedService $prefix $appExe)
   Remove-Item -LiteralPath $appExe -Force
  }
  $uninstall=Join-Path $target 'unins000.exe';$log=Join-Path $root 'uninstall.log'
  $process=Start-Process -FilePath $uninstall -ArgumentList ('/VERYSILENT /NORESTART /LOG="'+$log+'"') -WindowStyle Hidden -PassThru
  $null=$process.Handle
  $answered=$false;$errorShown=$false;$errorCloseRequested=$false;$watch=[Diagnostics.Stopwatch]::StartNew()
  try{
   while(!$process.WaitForExit(100)){
    if($watch.Elapsed.TotalSeconds -gt 90){
     $ids=Get-TestProcessIds $process.Id
     $diagnostic='case='+$case+' answered='+$answered+' errorShown='+$errorShown+' errorCloseRequested='+$errorCloseRequested+[Environment]::NewLine+[UninstallDialogTest]::Dump([int[]]$ids)
     [IO.File]::WriteAllText((Join-Path $root 'timeout.log'),$diagnostic,[Text.UTF8Encoding]::new($false))
     Write-Warning $diagnostic
     if(Test-Path -LiteralPath $log){Get-Content -LiteralPath $log -Tail 25 | Write-Host}
     throw ('제거 시험 시간 초과: '+$case)
    }
    $windowPids=@(Get-TestProcessIds $process.Id)
    $dialog=[UninstallDialogTest]::Find('','CheckList 전용 Redis도 함께 삭제할까요?',[int[]]$windowPids)
    if(!$answered -and $dialog -ne [IntPtr]::Zero){
     [void][UninstallDialogTest]::SetWindowPos($dialog,[IntPtr]::Zero,-32000,-32000,0,0,0x15)
     $choice=if($case -eq 'remove'){6}elseif($case -eq 'cancel'){2}else{7}
     [void][UninstallDialogTest]::PostMessage($dialog,0x111,[IntPtr]$choice,[IntPtr]::Zero);$answered=$true
    }
    $errorDialog=[UninstallDialogTest]::FindError([int[]]$windowPids)
    if($errorDialog -ne [IntPtr]::Zero){$errorShown=$true;if([UninstallDialogTest]::TryCloseError($errorDialog,[int[]]$windowPids)){$errorCloseRequested=$true}}
   }
   $process.Refresh();$exitCode=$process.ExitCode
  }finally{Stop-TestProcess $process;$process.Dispose()}
  Assert $answered 'Redis 제거 선택 질문이 나타나지 않았습니다.'
  $shouldAbort=$case -in @('cancel','foreign-service')
  Assert (($exitCode -ne 0) -eq $shouldAbort) ('제거 종료 코드가 예상과 다릅니다: '+$case+'='+$exitCode)
  Assert (Test-Path (Join-Path $target 'postgresql/bin/pg_ctl.exe')) '구버전 갱신 후 PostgreSQL 실행 파일이 삭제됐습니다.'
  Assert (Test-Path (Join-Path $target 'data/postgres/PG_VERSION')) 'PostgreSQL 데이터가 삭제됐습니다.'
  Assert ((Get-Service ($prefix+'PostgreSQL')).Status -eq 'Running') 'PostgreSQL 서비스가 변경됐습니다.'
  Assert (Test-Path (Join-Path $target 'data/attachments/keep.txt')) '첨부 데이터가 삭제됐습니다.'
  if($case -eq 'remove'){
   foreach($relative in @('redis','redis-service.exe','redis-service.xml','data/redis','config/redis.conf','config/bundled-redis.marker')){Assert (!(Test-Path (Join-Path $target $relative))) ('Redis 제거 잔존: '+$relative)}
   Assert (!(Get-Service ($prefix+'Redis') -ErrorAction SilentlyContinue)) 'Redis 서비스가 남았습니다.'
  }else{
   Assert (Test-Path (Join-Path $target 'data/redis/session.txt')) '보존 선택한 Redis 데이터가 삭제됐습니다.'
   Assert (Test-Path (Join-Path $target 'redis-service.exe')) '보존 선택한 Redis 실행 파일이 삭제됐습니다.'
   Assert ((Get-Service ($prefix+'Redis')).Status -eq 'Running') '보존 선택한 Redis 서비스가 변경됐습니다.'
  }
  if($shouldAbort){Assert (Test-Path (Join-Path $target 'checklist-service.exe')) '취소·실패 후 앱 파일이 삭제됐습니다.'}
  else{Assert (!(Test-Path (Join-Path $target 'checklist.jar'))) '앱 파일 제거 실패';Assert (!(Get-Service $prefix -ErrorAction SilentlyContinue)) '앱 서비스 제거 실패'}
  if($case -eq 'foreign-service'){
   Assert $errorShown '다른 설치 서비스 충돌 안내가 누락됐습니다.'
   Assert $errorCloseRequested '다른 설치 서비스 충돌 오류 창에 닫기를 요청하지 못했습니다.'
   Assert ([IO.File]::ReadAllText((Join-Path $target 'logs/install-error.txt')).Contains('동일 이름의 다른 서비스')) '예상한 서비스 소유권 오류가 아닙니다.'
  }
  Write-Host ('실제 제거 검사 통과: '+$case+' (구버전 갱신·PostgreSQL 보존 포함)')
 }finally{
  foreach($name in $names){
   $service=Get-Service -Name $name -ErrorAction SilentlyContinue
   if($service){try{if($service.Status -ne 'Stopped'){Stop-Service -Name $name -ErrorAction Stop};$service.WaitForStatus([ServiceProcess.ServiceControllerStatus]::Stopped,[TimeSpan]::FromSeconds(15))}finally{$service.Dispose()}; & (Join-Path $env:SystemRoot 'System32/sc.exe') delete $name | Out-Null}
  }
 }
}
}finally{try{Publish-TestLogs}catch{Write-Warning ('시험 로그 보관 실패: '+$_.Exception.Message)}}
Write-Host ('실제 제거 검사 로그: '+$testBase)