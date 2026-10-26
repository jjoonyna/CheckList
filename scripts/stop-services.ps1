param([Parameter(Mandatory=$true)][string]$Root)
$ErrorActionPreference='Stop'
$Root=[IO.Path]::GetFullPath($Root)
. (Join-Path $PSScriptRoot 'install-config.ps1')
. (Join-Path $PSScriptRoot 'runtime-support.ps1')
$configDir=Join-Path $Root 'config'
$targets=@(@{Name='CheckList';Executable=(Join-Path $Root 'checklist-service.exe')})
foreach($name in @('CheckListRedis','CheckListPostgreSQL')){
 $marker=if($name -eq 'CheckListRedis'){'bundled-redis.marker'}else{'bundled-postgresql.marker'}
 $exe=if($name -eq 'CheckListRedis'){'redis-service.exe'}else{'postgresql/bin/pg_ctl.exe'}
 if(Test-Path -LiteralPath (Join-Path $configDir $marker)){$targets+=@{Name=$name;Executable=(Join-Path $Root $exe)}}
}
# 미확인 프로세스나 타 설치 서비스가 있으면 기존 서비스를 중단하기 전에 설치를 차단한다.
$null=@(Get-InstallJavaProcesses $Root)
foreach($target in $targets){$service=Assert-OwnedService $target.Name $target.Executable;if($service){$service.Dispose()}}
foreach($target in $targets){[void](Stop-OwnedService $target.Name $target.Executable)}
Stop-InstallJavaProcesses $Root
Write-Host '기존 CheckList 서비스와 전용 Java 프로세스의 종료를 확인했습니다.'
