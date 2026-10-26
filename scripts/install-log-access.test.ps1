[CmdletBinding()]
param([string]$VerifyRoot)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'install-config.ps1')
. (Join-Path $PSScriptRoot 'runtime-support.ps1')
function Assert($value,[string]$message){if(!$value){throw $message}}
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin=[Security.Principal.WindowsPrincipal]::new($identity).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if($VerifyRoot){
 Assert (!$isAdmin) '읽기·쓰기 검증은 설치 계정의 일반 권한 PowerShell에서 실행해 주세요.'
 foreach($file in @('install.log','install-error.txt','new.log','rotated/service.log')){
  Assert (([IO.File]::ReadAllText((Join-Path $VerifyRoot ('logs/'+$file)))).Contains('검증')) ('일반 권한 로그 읽기 실패: '+$file)
 }
 $writeDenied=$false
 try{[IO.File]::AppendAllText((Join-Path $VerifyRoot 'logs/install.log'),'쓰기 시도')}catch [UnauthorizedAccessException]{$writeDenied=$true}
 Assert $writeDenied '일반 권한으로 로그를 변경할 수 있음'
 $createDenied=$false
 try{[IO.File]::WriteAllText((Join-Path $VerifyRoot 'logs/forbidden.txt'),'쓰기 시도')}catch [UnauthorizedAccessException]{$createDenied=$true}
 Assert $createDenied '일반 권한으로 로그 파일을 만들 수 있음'
 $configDenied=$false
 try{$null=[IO.File]::ReadAllText((Join-Path $VerifyRoot 'config/application.properties'))}catch [UnauthorizedAccessException]{$configDenied=$true}
 Assert $configDenied '일반 권한으로 비밀번호 설정을 읽을 수 있음'
 Write-Host '일반 권한 로그 읽기·쓰기 거부·설정 읽기 거부 검사 통과'
 return
}
Assert $isAdmin '권한 시험 준비는 관리자 PowerShell에서 실행해 주세요.'
$root=Join-Path $env:ProgramData ('CheckList log access test '+[guid]::NewGuid().ToString('N'))
foreach($directory in @('logs','config')){New-Item -ItemType Directory -Path (Join-Path $root $directory) -Force | Out-Null}
Protect-Configuration (Join-Path $root 'config')
Protect-Configuration (Join-Path $root 'logs')
Write-ProtectedText (Join-Path $root 'config/application.properties') '검증 전용 비밀번호'
Write-ProtectedText (Join-Path $root 'logs/install.log') '기존 설치 로그 검증'
Write-ProtectedText (Join-Path $root 'logs/install-error.txt') '과거 오류 검증'
$configAcl=(Get-Acl -LiteralPath (Join-Path $root 'config/application.properties')).Sddl
Set-InstallLogAccess (Join-Path $root 'logs')
[IO.File]::WriteAllText((Join-Path $root 'logs/install-error.txt'),'최신 오류 검증')
[IO.File]::WriteAllText((Join-Path $root 'logs/new.log'),'새 로그 검증')
New-Item -ItemType Directory -Path (Join-Path $root 'logs/rotated') | Out-Null
[IO.File]::WriteAllText((Join-Path $root 'logs/rotated/service.log'),'하위 서비스 로그 검증')
Assert ((Get-Acl -LiteralPath (Join-Path $root 'config/application.properties')).Sddl -eq $configAcl) '로그 권한 변경이 비밀번호 설정 권한에 영향을 줌'
foreach($file in @('install.log','install-error.txt','new.log','rotated/service.log')){
 $rules=(Get-Acl -LiteralPath (Join-Path $root ('logs/'+$file))).GetAccessRules($true,$true,[Security.Principal.SecurityIdentifier])
 $reader=@($rules | Where-Object {$_.IdentityReference.Value -eq $identity.User.Value -and $_.AccessControlType -eq 'Allow'})
 Assert ($reader.Count -gt 0) ('설치 계정 로그 읽기 권한 누락: '+$file)
 Assert (@($reader | Where-Object {$_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::WriteData}).Count -eq 0) ('설치 계정 로그 쓰기 권한 포함: '+$file)
}
Write-Host '기존·새 로그와 하위 로그의 읽기 권한 및 설정 보호 검사 통과'
Write-Host ('LOG_ACCESS_ROOT='+$root)
