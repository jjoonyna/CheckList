[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Initdb)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'install-config.ps1')
. (Join-Path $PSScriptRoot 'runtime-support.ps1')
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
if(!([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){throw '관리자 권한으로 실행해 주세요.'}
$Root=Join-Path $env:ProgramFiles ('CheckList initdb test '+[guid]::NewGuid().ToString('N'))
foreach($directory in @('data','config','logs')){New-Item -ItemType Directory -Path (Join-Path $Root $directory) -Force | Out-Null}
Protect-Configuration (Join-Path $Root 'config');Protect-Configuration (Join-Path $Root 'logs')
$configAcl=(Get-Acl (Join-Path $Root 'config')).Sddl
function Assert($Value,[string]$Message){if(!$Value){throw $Message}}
function Assert-Cleaned([string]$DataDirectory){
 Assert (@(Get-ChildItem (Join-Path $Root 'data') -Force -Filter '.pg-init-*').Count -eq 0) '초기화 임시 비밀번호 파일이 남았습니다.'
 if($identity.User.Value -ne 'S-1-5-18'){
  foreach($item in @((Get-Item $DataDirectory)) + @(Get-ChildItem $DataDirectory -Recurse -Force)){
   $rules=(Get-Acl -LiteralPath $item.FullName).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
   Assert (@($rules|Where-Object {$_.IdentityReference.Value -eq $identity.User.Value -and $_.AccessControlType -eq 'Allow'}).Count -eq 0) ('초기화 계정의 임시 권한이 남았습니다: '+$item.FullName)
  }
 }
 Assert ((Get-Acl (Join-Path $Root 'config')).Sddl -eq $configAcl) '설정 폴더 권한이 변경됐습니다.'
}
$data=Join-Path $Root 'data/postgres'
Write-Host ('검증 경로: '+$Root)
Initialize-PostgresData $Initdb $data 'checklist_test' 'test-only-password'
Assert (Test-Path (Join-Path $data 'PG_VERSION')) '실제 PostgreSQL 초기화에 실패했습니다.'
Assert-Cleaned $data
Write-Host '실제 Program Files 초기화·임시 파일/권한 회수·config 보호 통과'
$failedData=Join-Path $Root 'data/failed-postgres'
New-Item -ItemType Directory -Path $failedData | Out-Null
$sentinel=Join-Path $failedData 'existing.txt'
[IO.File]::WriteAllText($sentinel,'보존 확인')
$failed=$false
try{Initialize-PostgresData $Initdb $failedData 'checklist_test' 'test-only-password'}catch{$failed=$_.Exception.Message -match 'PostgreSQL 초기화 실패'}
Assert $failed '초기화 실패 검증이 실패했습니다.'
Assert-Cleaned $failedData
Assert ([IO.File]::ReadAllText($sentinel) -eq '보존 확인') '초기화 실패 시 기존 파일이 변경됐습니다.'
Write-Host '초기화 실패 시 임시 파일·권한 회수 통과'