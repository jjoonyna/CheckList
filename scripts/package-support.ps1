function Write-PackageLog([string]$Message){
 Write-Host ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'),$Message)
}

function Invoke-PackageStep([string]$StepName,[scriptblock]$Action){
 $watch=[Diagnostics.Stopwatch]::StartNew()
 Write-PackageLog "시작: $StepName"
 try{
  & $Action
  Write-PackageLog ('완료: {0} ({1:N1}초)' -f $StepName,$watch.Elapsed.TotalSeconds)
 }catch{
  Write-PackageLog ('실패: {0} ({1:N1}초) 원인: {2}' -f $StepName,$watch.Elapsed.TotalSeconds,$_.Exception.Message)
  throw
 }
}

function Invoke-PackageProcess {
 param([string]$Name,[string]$FilePath,[string]$Arguments,[int]$TimeoutSeconds=300,[int]$HeartbeatSeconds=15,[string]$WorkingDirectory=(Get-Location).Path)
 if($TimeoutSeconds -lt 1 -or $HeartbeatSeconds -lt 1){throw '프로세스 제한 시간은 1초 이상이어야 합니다.'}
 $safeName=$Name -replace '[^\p{L}\p{N}._-]','-'
 $prefix=Join-Path $script:PackageLogDirectory ($safeName+'-'+[guid]::NewGuid().ToString('N'))
 $stdout=$prefix+'.stdout.log';$stderr=$prefix+'.stderr.log'
 $seen=@{Out=0;Err=0}
 function Show-NewOutput {
  foreach($entry in @(@('Out',$stdout),@('Err',$stderr))){
   if(Test-Path -LiteralPath $entry[1]){
    $lines=@(Get-Content -LiteralPath $entry[1] -Encoding UTF8)
    $lines | Select-Object -Skip $seen[$entry[0]] | ForEach-Object {Write-Host $_}
    $seen[$entry[0]]=$lines.Count
   }
  }
 }
 $watch=[Diagnostics.Stopwatch]::StartNew();$nextHeartbeat=$HeartbeatSeconds
 Write-PackageLog "프로세스 시작: $Name, 실행 파일=$FilePath, 제한=${TimeoutSeconds}초"
 $process=Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
 $null=$process.Handle
 try{
  while(!$process.WaitForExit(200)){
   Show-NewOutput
   if($watch.Elapsed.TotalSeconds -ge $TimeoutSeconds){
    Write-PackageLog "시간 제한: $Name, PID=$($process.Id), 제한=${TimeoutSeconds}초"
    throw "$Name 시간 제한 ${TimeoutSeconds}초 초과. 진단 로그: $prefix"
   }
   if($watch.Elapsed.TotalSeconds -ge $nextHeartbeat){
    $process.Refresh()
    Write-PackageLog ('진행 중: {0}, PID={1}, 경과={2:N1}초, CPU={3:N1}초' -f $Name,$process.Id,$watch.Elapsed.TotalSeconds,$process.TotalProcessorTime.TotalSeconds)
    $nextHeartbeat=$watch.Elapsed.TotalSeconds+$HeartbeatSeconds
   }
  }
  Show-NewOutput
  $process.Refresh()
  if($process.ExitCode -ne 0){throw "$Name 실패: 종료 코드 $($process.ExitCode). 진단 로그: $prefix"}
  Write-PackageLog ('프로세스 완료: {0}, 종료 코드 0, {1:N1}초' -f $Name,$watch.Elapsed.TotalSeconds)
  return [pscustomobject]@{OutputLog=$stdout;ErrorLog=$stderr;ExitCode=$process.ExitCode}
 }finally{
  if(!$process.HasExited){
   # 이 함수가 시작한 프로세스와 그 자식만 종료한다.
   if($PSVersionTable.PSEdition -eq 'Core'){$process.Kill($true)}
   else{& "$env:SystemRoot\System32\taskkill.exe" /PID $process.Id /T /F | Out-Host}
   $null=$process.WaitForExit(5000)
  }
  Show-NewOutput
  $process.Dispose()
 }
}

function Get-PackageDownload {
 param([string]$File,[string]$Url,[string]$Hash,[int]$TimeoutSeconds=180)
 $name=Split-Path -Leaf $File
 Invoke-PackageStep "다운로드·검증 $name" {
  if(!(Test-Path -LiteralPath $File)){
   $partial=$File+'.partial'
   Write-PackageLog "다운로드 주소: $Url"
   try{
    $curl=(Get-Command curl.exe -ErrorAction Stop).Source
    # 전송별 제한 외에 외부 프로세스 전체에도 제한을 둔다. 실패한 파일은 캐시로 승격하지 않는다.
    $arguments='--fail --location --silent --show-error --connect-timeout 20 --max-time '+$TimeoutSeconds+' --retry 1 --retry-max-time '+($TimeoutSeconds*2)+' --output "'+$partial+'" "'+$Url+'"'
    Invoke-PackageProcess -Name "다운로드 $name" -FilePath $curl -Arguments $arguments -TimeoutSeconds ($TimeoutSeconds*2+30) | Out-Null
    if($Hash -and (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $Hash){throw "배포 도구 SHA-256 불일치: $name"}
    Move-Item -LiteralPath $partial -Destination $File -Force
   }finally{
    if(Test-Path -LiteralPath $partial){Remove-Item -LiteralPath $partial -Force}
   }
  }else{Write-PackageLog "캐시 사용: $File"}
  $size=(Get-Item -LiteralPath $File).Length
  Write-PackageLog "파일 준비: $name, ${size}바이트"
  if($Hash -and (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -ne $Hash){throw "배포 도구 SHA-256 불일치: $name"}
  if($Hash){Write-PackageLog "SHA-256 일치: $name"}
 }
}
function Start-PackageStage([string]$StageName){
 Complete-PackageStage
 $script:PackageStageName=$StageName
 $script:PackageStageWatch=[Diagnostics.Stopwatch]::StartNew()
 Write-PackageLog "단계 시작: $StageName"
}
function Complete-PackageStage {
 if($script:PackageStageName){
  Write-PackageLog ('단계 완료: {0} ({1:N1}초)' -f $script:PackageStageName,$script:PackageStageWatch.Elapsed.TotalSeconds)
  $script:PackageStageName=$null
 }
}
function Resolve-Package7Zip {
 $command=Get-Command 7z.exe -ErrorAction SilentlyContinue
 if($command){Write-PackageLog "7-Zip 사용: $($command.Source)";return $command.Source}
 $installed=Join-Path $env:ProgramFiles '7-Zip/7z.exe'
 if(Test-Path -LiteralPath $installed){Write-PackageLog "7-Zip 사용: $installed";return $installed}
 $toolDirectory=Join-Path $PSScriptRoot '../tools-cache/deploy/7zip-26.04'
 New-Item -ItemType Directory -Force -Path $toolDirectory | Out-Null
 $sevenZip=Join-Path $toolDirectory 'x64/7za.exe'
 if(!(Test-Path -LiteralPath $sevenZip)){
  $bootstrap=Join-Path $toolDirectory '7zr.exe'
  $extra=Join-Path $toolDirectory '7z2604-extra.7z'
  Get-PackageDownload -File $bootstrap -Url 'https://github.com/ip7z/7zip/releases/download/26.04/7zr.exe' -Hash '256feca8e274e5da655e2a284fabafd9f554365eb164862089dacd4e8276d282'
  Get-PackageDownload -File $extra -Url 'https://github.com/ip7z/7zip/releases/download/26.04/7z2604-extra.7z' -Hash 'dc4b11d3399db18b063630137145f5585d8f7ac847bf3639bd1185d7d1f7cee0'
  Invoke-PackageProcess -Name '포터블 7-Zip 준비' -FilePath $bootstrap -Arguments ('x -y -sccUTF-8 "'+$extra+'" "-o'+$toolDirectory+'"') -TimeoutSeconds 120 | Out-Null
 }
 if(!(Test-Path -LiteralPath $sevenZip)){throw '포터블 7-Zip 실행 파일을 찾을 수 없습니다.'}
 Write-PackageLog "포터블 7-Zip 사용: $sevenZip"
 return (Get-Item -LiteralPath $sevenZip).FullName
}

function Expand-PackagePostgres {
 param([string]$Archive,[string]$Destination,[string]$WorkDirectory,[string]$SevenZip)
 if(!$SevenZip){$SevenZip=Resolve-Package7Zip}
 New-Item -ItemType Directory -Force -Path $Destination,$WorkDirectory | Out-Null
 Invoke-PackageStep 'PostgreSQL XZ 해제' {
  Invoke-PackageProcess -Name '7-Zip XZ 해제' -FilePath $SevenZip -Arguments ('e -txz -y -sccUTF-8 "'+$Archive+'" "-o'+$WorkDirectory+'"') -TimeoutSeconds 180 | Out-Null
 }
 $tarFiles=@(Get-ChildItem -LiteralPath $WorkDirectory -File)
 if($tarFiles.Count -ne 1){throw 'PostgreSQL XZ 안에 TAR 파일이 정확히 하나 필요합니다.'}
 Invoke-PackageStep 'PostgreSQL TAR 해제' {
  Invoke-PackageProcess -Name '7-Zip TAR 해제' -FilePath $SevenZip -Arguments ('x -ttar -y -sccUTF-8 "'+$tarFiles[0].FullName+'" "-o'+$Destination+'"') -TimeoutSeconds 180 | Out-Null
 }
 if(!(Test-Path -LiteralPath (Join-Path $Destination 'bin/initdb.exe'))){throw 'PostgreSQL 압축 구조 오류: bin/initdb.exe가 없습니다.'}
 Write-PackageLog "PostgreSQL 추출 검증 완료: $Destination"
}

function Copy-PackageLicenses {
 param([Parameter(Mandatory=$true)][string]$Source,[Parameter(Mandatory=$true)][string]$Stage)
 $manifest=Join-Path $Source 'manifest.json'
 if(!(Test-Path -LiteralPath $manifest -PathType Leaf)){throw '고지 원문 목록이 없습니다.'}
 $entries=@(Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop | ForEach-Object {$_})
 if(!$entries.Count){throw '고지 원문 목록이 비어 있습니다.'}
 $files=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 $targets=[Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
 # 모든 원문을 먼저 검증한다. 누락·변조 시 일부 고지만 복사한 산출물을 만들지 않는다.
 foreach($entry in $entries){
  if($entry.file -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*\.txt$' -or
     $entry.target -notmatch '^(?:licenses/[A-Za-z0-9][A-Za-z0-9._-]*\.txt|postgresql/LICENSE\.txt)$' -or
     $entry.sha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $entry.source -notmatch '^https://'){
   throw '고지 원문 목록의 파일·대상 경로·출처·해시 형식이 올바르지 않습니다.'
  }
  if(!$files.Add($entry.file) -or !$targets.Add($entry.target)){throw '고지 원문 목록에 중복 파일 또는 대상 경로가 있습니다.'}
  $file=Join-Path $Source $entry.file
  if(!(Test-Path -LiteralPath $file -PathType Leaf)){throw ('고지 원문 파일이 없습니다: '+$entry.file)}
  if((Get-FileHash -LiteralPath $file -Algorithm SHA256 -ErrorAction Stop).Hash -ne $entry.sha256){throw ('고지 원문 SHA-256 불일치: '+$entry.file)}
 }
 foreach($entry in $entries){
  $target=Join-Path $Stage $entry.target
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
  Copy-Item -LiteralPath (Join-Path $Source $entry.file) -Destination $target -Force -ErrorAction Stop
  if((Get-FileHash -LiteralPath $target -Algorithm SHA256 -ErrorAction Stop).Hash -ne $entry.sha256){throw ('고지 복사 SHA-256 불일치: '+$entry.target)}
  Write-PackageLog ('원문 고지 복사·SHA-256 일치: '+$entry.target)
 }
}
