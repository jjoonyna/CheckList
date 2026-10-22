import { readFileSync, writeFileSync, appendFileSync, mkdirSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

export function extractNotes(changelog, version) {
  const sections = [...changelog.matchAll(/^## \[([^\]]+)\][^\r\n]*\r?\n/gm)];
  const matches = sections.filter((section) => section[1] === version);
  if (matches.length !== 1) throw new Error(`CHANGELOG에 버전 ${version} 항목이 정확히 하나 필요합니다.`);
  const section = matches[0];
  const next = sections[sections.indexOf(section) + 1];
  const notes = changelog.slice(section.index + section[0].length, next?.index).trim();
  if (!notes) throw new Error('릴리즈 내용이 비어 있습니다.');
  return `${notes}\n`;
}

export function validateVersions(version, versions) {
  if (!/^\d+\.\d+\.\d+$/.test(version) || versions.some((value) => value !== version)) {
    throw new Error('프론트·잠금 파일·백엔드·설치 버전을 동일한 정식 버전으로 맞춰 주세요.');
  }
}

export function prepareRelease(root) {
  const read = (path) => readFileSync(resolve(root, path), 'utf8');
  const version = JSON.parse(read('frontend/package.json')).version;
  const lock = JSON.parse(read('frontend/package-lock.json'));
  validateVersions(version, [lock.version, lock.packages[''].version,
    read('backend/build.gradle').match(/^version = '([^']+)'/m)?.[1],
    read('installer/checklist.iss').match(/#define AppVersion "([^"]+)"/)?.[1],
    read('scripts/package-deploy.ps1').match(/\[string\]\$Version='([^']+)'/)?.[1]]);
  return { version, tag: `v.${version}`, notes: extractNotes(read('CHANGELOG.md'), version) };
}

export async function publishRelease(config, request = fetch, run = runGh) {
  const { repository, token, version, sha, notes, assets } = config;
  if (!repository || !token || !/^[a-f0-9]{40}$/.test(sha)) throw new Error('릴리즈 저장소·토큰·대상 SHA가 필요합니다.');
  const tag = `v.${version}`;
  const api = `https://api.github.com/repos/${repository}`;
  const options = { headers: { Authorization: `Bearer ${token}`, Accept: 'application/vnd.github+json', 'X-GitHub-Api-Version': '2022-11-28' } };
  const existing = await request(`${api}/releases/tags/${encodeURIComponent(tag)}`, options);
  if (existing.status === 200) {
    if ((await existing.json()).draft) throw new Error('동일 태그의 초안이 있습니다. 확인 후 수동으로 처리해 주세요.');
    console.log(`이미 게시된 ${tag} 릴리즈를 유지합니다.`);
    return;
  }
  if (existing.status !== 404) throw new Error(`릴리즈 조회 실패: HTTP ${existing.status}`);
  const ref = await request(`${api}/git/ref/tags/${encodeURIComponent(tag)}`, options);
  if (ref.status !== 404) throw new Error(`기존 태그 또는 태그 조회 오류로 게시를 중단합니다: HTTP ${ref.status}`);
  // 두 결과물을 모두 받은 뒤 게시한다. 기존 태그·릴리즈는 덮어쓰지 않는다.
  run(['release', 'create', tag, '--repo', repository, '--target', sha, '--title', tag, '--notes-file', notes, ...assets]);
}

function runGh(args) {
  const result = spawnSync('gh', args, { stdio: 'inherit', shell: false });
  if (result.error || result.status !== 0) throw new Error('GitHub 릴리즈 게시에 실패했습니다.', { cause: result.error });
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
  const release = prepareRelease(root);
  const notes = resolve(root, 'build/release-notes.md');
  mkdirSync(dirname(notes), { recursive: true });
  writeFileSync(notes, release.notes);
  console.log(`릴리즈 버전: ${release.version}, 태그: ${release.tag}`);
  if (process.env.GITHUB_OUTPUT) appendFileSync(process.env.GITHUB_OUTPUT, `version=${release.version}\ntag=${release.tag}\n`);
  if (process.argv.includes('--publish')) {
    await publishRelease({ repository: process.env.GITHUB_REPOSITORY, token: process.env.GH_TOKEN,
      version: release.version, sha: process.env.RELEASE_SHA, notes,
      assets: [resolve(root, `backend/build/libs/checklist-${release.version}.jar`), resolve(root, `dist/checklist-setup-${release.version}.exe`)] });
  }
}