[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Root,[switch]$Quiet)
$ErrorActionPreference='Stop'
function Show-StopResult([string]$Message,[bool]$Failed=$false){
 if($Quiet){Write-Host $Message;return}
 Add-Type -AssemblyName System.Windows.Forms
 $icon=if($Failed){[Windows.Forms.MessageBoxIcon]::Error}else{[Windows.Forms.MessageBoxIcon]::Information}
 [void][Windows.Forms.MessageBox]::Show($Message,'CheckList 종료',[Windows.Forms.MessageBoxButtons]::OK,$icon)
}
try{
 $Root=[IO.Path]::GetFullPath($Root)
 $identity=[Security.Principal.WindowsIdentity]::GetCurrent()
 if(!([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){
  $arguments='-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "'+$PSCommandPath+'" -Root "'+$Root+'"'
  if($Quiet){$arguments+=' -Quiet'}
  $process=Start-Process -FilePath (Join-Path $env:SystemRoot 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $arguments -Verb RunAs -WindowStyle Hidden -PassThru
  $null=$process.Handle
  try{while(!$process.WaitForExit(200)){};$process.Refresh();exit $process.ExitCode}finally{$process.Dispose()}
 }
 . (Join-Path $PSScriptRoot 'install-config.ps1')
 . (Join-Path $PSScriptRoot 'runtime-support.ps1')
 # 두 서비스의 소유 경로부터 확인하며 PostgreSQL과 외부 Redis는 건드리지 않는다.
 $owned=Assert-OwnedService 'CheckList' (Join-Path $Root 'checklist-service.exe')
 if($owned){$owned.Dispose()}
 $stopRedis=Test-Path -LiteralPath (Join-Path $Root 'config/bundled-redis.marker')
 if($stopRedis){$owned=Assert-OwnedService 'CheckListRedis' (Join-Path $Root 'redis-service.exe');if($owned){$owned.Dispose()}}
 [void](Stop-OwnedService 'CheckList' (Join-Path $Root 'checklist-service.exe'))
 if($stopRedis){[void](Stop-OwnedService 'CheckListRedis' (Join-Path $Root 'redis-service.exe'))}
 Show-StopResult 'CheckList 앱과 전용 Redis를 종료했습니다. PostgreSQL과 저장 데이터는 그대로 유지됩니다.'
}catch{
 Show-StopResult ('종료하지 못했습니다: '+$_.Exception.Message) $true
 exit 1
}