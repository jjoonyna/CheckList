param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'install-config.ps1')
. (Join-Path $PSScriptRoot 'runtime-support.ps1')
$configDir=Join-Path $Root 'config'
if(Assert-OwnedService 'CheckList' (Join-Path $Root 'checklist-service.exe')){Stop-Service CheckList}
foreach($name in @('CheckListRedis','CheckListPostgreSQL')){
 $marker=if($name -eq 'CheckListRedis'){'bundled-redis.marker'}else{'bundled-postgresql.marker'}
 $exe=if($name -eq 'CheckListRedis'){'redis-service.exe'}else{'postgresql/bin/pg_ctl.exe'}
 if((Test-Path -LiteralPath (Join-Path $configDir $marker)) -and (Assert-OwnedService $name (Join-Path $Root $exe))){Stop-Service $name}
}