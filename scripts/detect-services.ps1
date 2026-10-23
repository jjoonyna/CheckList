param([Parameter(Mandatory=$true)][string]$OutputFile,[string]$Root)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'install-config.ps1')
$found=Get-LocalEndpoints
$lines=@('[Defaults]',('DbPassword='+(New-InstallSecret)),('RedisPassword='+(New-InstallSecret)))
foreach($kind in @('PostgreSQL','Redis')){
 $entries=@($found.$kind);$lines+='['+$kind+']';$lines+='Count='+$entries.Count
 for($index=0;$index -lt $entries.Count;$index++){$lines+='Host'+$index+'='+$entries[$index].Host;$lines+='Port'+$index+'='+$entries[$index].Port}
}
if($Root){
 $pending=Join-Path $Root 'config/setup-pending.json'
 if(Test-Path -LiteralPath $pending){
  $state=Get-Content -LiteralPath $pending -Encoding UTF8 -Raw|ConvertFrom-Json
  $settings=ConvertFrom-PendingState $state
  $lines+='[Pending]';$lines+='Exists=1'
  foreach($key in $settings.Keys){$lines+=$key+'='+(ConvertTo-IniHex ([string]$settings[$key]))}
 }
}
# 원문 비밀번호가 있으므로 내용을 쓰기 전에 ACL부터 제한한다.
Write-ProtectedText $OutputFile ($lines -join "`r`n")