$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'package-support.ps1')
$testRoot=Join-Path $PSScriptRoot ('../build/postgres archive test '+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
$script:PackageLogDirectory=$testRoot
$sevenZip=Resolve-Package7Zip
$source=Join-Path $testRoot 'source';$bin=Join-Path $source 'bin'
New-Item -ItemType Directory -Path $bin | Out-Null
[IO.File]::WriteAllText((Join-Path $bin 'initdb.exe'),'추출 검증 데이터')
$tar=Join-Path $testRoot 'fixture.tar';$txz=Join-Path $testRoot 'fixture.txz'
Invoke-PackageProcess -Name 'TAR fixture 생성' -FilePath $sevenZip -Arguments ('a -ttar -sccUTF-8 "'+$tar+'" bin') -WorkingDirectory $source | Out-Null
Invoke-PackageProcess -Name 'XZ fixture 생성' -FilePath $sevenZip -Arguments ('a -txz -sccUTF-8 "'+$txz+'" "'+$tar+'"') | Out-Null
$destination=Join-Path $testRoot 'output'
Expand-PackagePostgres -Archive $txz -Destination $destination -WorkDirectory (Join-Path $testRoot 'xz output') -SevenZip $sevenZip
if([IO.File]::ReadAllText((Join-Path $destination 'bin/initdb.exe')) -ne '추출 검증 데이터'){throw '아카이브 왕복 추출 실패'}
$bad=Join-Path $testRoot 'bad.txz';[IO.File]::WriteAllText($bad,'손상된 아카이브')
$failed=$false
try{Expand-PackagePostgres -Archive $bad -Destination (Join-Path $testRoot 'bad output') -WorkDirectory (Join-Path $testRoot 'bad xz') -SevenZip $sevenZip}catch{$failed=$true;Write-Host "예상 실패: $($_.Exception.Message)"}
if(!$failed){throw '손상된 아카이브를 허용함'}
$empty=Join-Path $testRoot 'empty';New-Item -ItemType Directory -Path $empty | Out-Null
[IO.File]::WriteAllText((Join-Path $empty 'other.txt'),'필수 파일 없음')
$emptyTar=Join-Path $testRoot 'empty.tar';$emptyXz=Join-Path $testRoot 'empty.txz'
Invoke-PackageProcess -Name '누락 TAR fixture 생성' -FilePath $sevenZip -Arguments ('a -ttar -sccUTF-8 "'+$emptyTar+'" other.txt') -WorkingDirectory $empty | Out-Null
Invoke-PackageProcess -Name '누락 XZ fixture 생성' -FilePath $sevenZip -Arguments ('a -txz -sccUTF-8 "'+$emptyXz+'" "'+$emptyTar+'"') | Out-Null
$failed=$false
try{Expand-PackagePostgres -Archive $emptyXz -Destination (Join-Path $testRoot 'missing output') -WorkDirectory (Join-Path $testRoot 'missing xz') -SevenZip $sevenZip}catch{$failed=$_.Exception.Message -match 'initdb';Write-Host "예상 실패: $($_.Exception.Message)"}
if(!$failed){throw 'initdb 없는 아카이브를 허용함'}
Write-Host "PostgreSQL 압축 회귀 검사 3개 통과: $testRoot"