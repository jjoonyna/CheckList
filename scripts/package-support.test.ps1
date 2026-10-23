$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'package-support.ps1')
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('checklist-package-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
$script:PackageLogDirectory=$testRoot
function Assert-True([bool]$Value,[string]$Message){if(!$Value){throw $Message}}
function Assert-Fails([scriptblock]$Action,[string]$Pattern){
 $failure=$null
 try{& $Action}catch{$failure=$_.Exception.Message}
 Assert-True ($null -ne $failure -and $failure -match $Pattern) "예상 실패 불일치: $failure / $Pattern"
}
$hostExe=(Get-Process -Id $PID).Path
$log=Join-Path $testRoot 'test-transcript.log'
Start-Transcript -Path $log | Out-Null
try{
 Invoke-PackageStep '성공 단계' {Write-Host '검증 출력'}
 Assert-Fails {Invoke-PackageStep '실패 단계' {throw '원인 보존'}} '원인 보존'
 Invoke-PackageProcess -Name '정상 프로세스' -FilePath $hostExe -Arguments '-NoProfile -Command "Write-Output ''child-output''; Start-Sleep -Seconds 2; exit 0"' -TimeoutSeconds 5 -HeartbeatSeconds 1
 Assert-Fails {Invoke-PackageProcess -Name '실패 프로세스' -FilePath $hostExe -Arguments '-NoProfile -Command "[Console]::Error.WriteLine(''child-error''); exit 7"' -TimeoutSeconds 5} '종료 코드 7'
 $watch=[Diagnostics.Stopwatch]::StartNew()
 Assert-Fails {Invoke-PackageProcess -Name '대기 프로세스' -FilePath $hostExe -Arguments '-NoProfile -Command "Start-Sleep -Seconds 30"' -TimeoutSeconds 1 -HeartbeatSeconds 1} '시간 제한'
 Assert-True ($watch.Elapsed.TotalSeconds -lt 12) '프로세스 제한 시간이 작동하지 않음'
 $cached=Join-Path $testRoot 'cached.bin'
 [IO.File]::WriteAllText($cached,'cached')
 $hash=(Get-FileHash -LiteralPath $cached -Algorithm SHA256).Hash
 Get-PackageDownload -File $cached -Url 'https://사용하지않는주소.invalid/' -Hash $hash
 Assert-Fails {Get-PackageDownload -File $cached -Url 'https://사용하지않는주소.invalid/' -Hash ('0'*64)} 'SHA-256 불일치'
 $source=Join-Path $testRoot 'source.bin'
 [IO.File]::WriteAllText($source,'실제 전송 검증')
 $target=Join-Path $testRoot 'downloaded.bin'
 $sourceHash=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
 Get-PackageDownload -File $target -Url ([uri]$source).AbsoluteUri -Hash $sourceHash
 Assert-True ((Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash -eq $sourceHash) '다운로드 정상 파일·해시 불일치'
 $bad=Join-Path $testRoot 'bad-download.bin'
 Assert-Fails {Get-PackageDownload -File $bad -Url ([uri]$source).AbsoluteUri -Hash ('0'*64)} 'SHA-256 불일치'
 Assert-True (!(Test-Path -LiteralPath $bad)) '해시 오류 파일이 정상 캐시로 남음'
 Assert-True (!(Test-Path -LiteralPath ($bad+'.partial'))) '해시 오류 임시 파일이 남음'
 $missing=Join-Path $testRoot 'missing.bin'
 Assert-Fails {Get-PackageDownload -File $missing -Url 'http://127.0.0.1:1/missing' -TimeoutSeconds 2} '실패'
 Assert-True (!(Test-Path -LiteralPath $missing)) '다운로드 실패 파일이 정상 캐시로 남음'
 Assert-True (!(Test-Path -LiteralPath ($missing+'.partial'))) '임시 다운로드 파일이 남음'
}finally{Stop-Transcript | Out-Null}
$content=Get-Content -LiteralPath $log -Raw
foreach($marker in @('성공 단계','프로세스 완료: 정상 프로세스','진행 중: 정상 프로세스','완료','실패 단계','원인 보존','대기 프로세스','시간 제한','child-output','child-error')){
 Assert-True ($content.Contains($marker)) "진단 로그 누락: $marker"
}
Write-Host "패키징 진단 테스트 통과: $testRoot"