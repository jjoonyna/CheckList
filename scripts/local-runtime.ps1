[CmdletBinding()]
param([ValidateSet('start','stop','status')][string]$Action='status')
$ErrorActionPreference='Stop'
$runtime=Join-Path $env:LOCALAPPDATA 'CheckListRuntime'
$pgCtl=Join-Path $runtime 'postgresql-18.6/bin/pg_ctl.exe'
$pgData=Join-Path $runtime 'postgres-data'
if(!(Test-Path -LiteralPath $pgCtl)){throw '로컬 PostgreSQL 설치를 찾지 못했습니다.'}
function Invoke-Redis([string]$Command){
 $secrets=Get-Content -LiteralPath (Join-Path $runtime 'credentials.json') -Raw | ConvertFrom-Json
 $client=New-Object Net.Sockets.TcpClient('127.0.0.1',6379)
 try{
  $client.ReceiveTimeout=3000;$stream=$client.GetStream();$writer=New-Object IO.StreamWriter($stream,[Text.UTF8Encoding]::new($false));$writer.NewLine="`r`n";$writer.AutoFlush=$true
  $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8)
  $writer.WriteLine('AUTH '+$secrets.redisPassword)
  if($reader.ReadLine() -ne '+OK'){throw 'Redis 인증 실패'}
  $writer.WriteLine($Command)
  if($Command -eq 'PING' -and $reader.ReadLine() -ne '+PONG'){throw 'Redis 응답 확인 실패'}
 }finally{$client.Close()}
}
if($Action -eq 'start'){
 & $pgCtl -D $pgData status *> $null
 if($LASTEXITCODE -ne 0){& $pgCtl -D $pgData -l (Join-Path $runtime 'postgres.log') -w start;if($LASTEXITCODE -ne 0){throw 'PostgreSQL 시작 실패'}}
 if(!(Get-NetTCPConnection -State Listen -LocalPort 6379 -ErrorAction SilentlyContinue)){Start-Process -FilePath (Join-Path $runtime 'redis-8.10.2/redis-server.exe') -ArgumentList 'redis.conf' -WorkingDirectory $runtime -WindowStyle Hidden | Out-Null;Start-Sleep -Milliseconds 1000}
 Invoke-Redis 'PING';Write-Host 'PostgreSQL 5432 / Redis 6379 실행 중'
}elseif($Action -eq 'stop'){
 Invoke-Redis 'SHUTDOWN SAVE'
 & $pgCtl -D $pgData -m fast -w stop
 if($LASTEXITCODE -ne 0){throw 'PostgreSQL 종료 실패'}
 Write-Host '로컬 PostgreSQL·Redis를 종료했습니다. 데이터는 유지됩니다.'
}else{
 & $pgCtl -D $pgData status
 Invoke-Redis 'PING';Write-Host 'Redis 비밀번호 인증·PING 정상 (127.0.0.1:6379)'
}