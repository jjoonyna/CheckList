$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'package-support.ps1')
$repo=Split-Path -Parent $PSScriptRoot
$source=Join-Path $repo 'third-party/licenses'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('checklist-license-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
function Assert($value,[string]$message){if(!$value){throw $message}}
function Assert-Fails([scriptblock]$action,[string]$pattern){
 $failure=$null
 try{& $action}catch{$failure=$_.Exception.Message}
 Assert ($null -ne $failure -and $failure -match $pattern) ('고지 검사의 예상 실패 불일치: '+$failure)
}
# 고지 준비에 기존 다운로드나 외부 프로세스 실행이 필요하면 즉시 실패한다.
function Get-PackageDownload {throw '고지 준비 중 네트워크 다운로드를 호출했습니다.'}
function Invoke-PackageProcess {throw '고지 준비 중 외부 프로세스를 호출했습니다.'}
$entries=@(Get-Content -LiteralPath (Join-Path $source 'manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object {$_})
$required=@('postgresql/LICENSE.txt','licenses/WinSW-2.12.0.txt','licenses/Inno-Setup-6.7.3.txt','licenses/Redis-8.10.2.txt','licenses/Redis-Windows-8.10.2.txt','licenses/Cygwin-LGPLv3.txt','licenses/Cygwin-GPLv3.txt','licenses/OpenSSL-3.5.8.txt','licenses/GCC-14.4.0-Runtime-Exception.txt','licenses/GCC-14.4.0-GPLv3.txt','licenses/libiconv-libintl-LGPLv2.1.txt','licenses/zlib-1.3.2-license-and-header.txt')
Assert ($entries.Count -eq $required.Count) '필수 원문12개의 목록이 다릅니다.'
foreach($target in $required){Assert ($target -in $entries.target) ('필수 고지 누락: '+$target)}
$stage=Join-Path $testRoot '정상 출력'
Copy-PackageLicenses -Source $source -Stage $stage
foreach($entry in $entries){
 Assert ((Get-FileHash -LiteralPath (Join-Path $stage $entry.target) -Algorithm SHA256).Hash -eq $entry.sha256) ('출력 원문 해시 불일치: '+$entry.target)
 $path='third-party/licenses/'+$entry.file
 $attributes=git -C $repo check-attr text -- $path
 Assert ($LASTEXITCODE -eq 0 -and $attributes -match ': text: unset$') ('Git 원문 바이트 보존 규칙 누락: '+$path)
 $filtered=git -C $repo hash-object ('--path='+$path) -- $path
 Assert ($LASTEXITCODE -eq 0) ('Git 필터 해시 검사 실패: '+$path)
 $raw=git -C $repo hash-object --no-filters -- $path
 Assert ($LASTEXITCODE -eq 0 -and $filtered -eq $raw) ('Git 줄바꿈 변환 발생: '+$path)
}
foreach($case in @('missing','tampered','escape','duplicate','empty')){
 $fixture=Join-Path $testRoot $case
 Copy-Item -LiteralPath $source -Destination $fixture -Recurse
 $output=Join-Path $testRoot ($case+'-output')
 $manifest=Join-Path $fixture 'manifest.json'
 $records=@(Get-Content -LiteralPath $manifest -Raw -Encoding UTF8 | ConvertFrom-Json | ForEach-Object {$_})
 switch($case){
  'missing'{Remove-Item -LiteralPath (Join-Path $fixture $records[0].file);$pattern='고지 원문 파일이 없습니다'}
  'tampered'{[IO.File]::WriteAllText((Join-Path $fixture $records[0].file),'변조된 원문');$pattern='SHA-256 불일치'}
  'escape'{$records[0].target='../outside.txt';$pattern='형식이 올바르지'}
  'duplicate'{$records[1].target=$records[0].target;$pattern='중복'}
  'empty'{$records=@();$pattern='비어 있습니다'}
 }
 if($case -in @('escape','duplicate')){[IO.File]::WriteAllText($manifest,($records | ConvertTo-Json -Depth 4),[Text.UTF8Encoding]::new($false))}
 if($case -eq 'empty'){[IO.File]::WriteAllText($manifest,'[]',[Text.UTF8Encoding]::new($false))}
 Assert-Fails {Copy-PackageLicenses -Source $fixture -Stage $output} $pattern
 Assert (!(Test-Path -LiteralPath $output)) ('검증 실패 전 고지를 복사했습니다: '+$case)
 Assert (!(Test-Path -LiteralPath (Join-Path $testRoot 'outside.txt'))) '고지 출력 범위를 벗어난 파일을 만들었습니다.'
}
Write-Host ('네트워크 없는 고지12개 복사·원문 해시·누락/변조/경로·Git 바이트 보존 검사 통과: '+$testRoot)
