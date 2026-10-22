import test from 'node:test';
import assert from 'node:assert/strict';
import { extractNotes, validateVersions, publishRelease } from './release.mjs';

const changelog = '# 변경 이력\n\n## [미출시]\n\n- 다음 작업\n\n## [0.0.0] - 2026-10-22\n\n### 추가\n- 첫 배포 #1\n\n## [0.0.1] - 2026-10-20\n- 다른 항목\n';
test('지정 버전의 내용만 릴리즈 노트로 추출한다', () => {
  assert.equal(extractNotes(changelog, '0.0.0'), '### 추가\n- 첫 배포 #1\n');
});
test('누락·중복·빈 릴리즈 항목은 거절한다', () => {
  for (const text of ['# 변경 이력', '## [0.0.0]\n', '## [0.0.0]\na\n## [0.0.0]\nb']) {
    assert.throws(() => extractNotes(text, '0.0.0'));
  }
});
test('프론트·잠금 파일·백엔드·설치 버전은 모두 일치해야 한다', () => {
  assert.doesNotThrow(() => validateVersions('0.0.0', ['0.0.0', '0.0.0']));
  assert.throws(() => validateVersions('0.0.0', ['0.1.0']));
  assert.throws(() => validateVersions('0.0.0-SNAPSHOT', ['0.0.0-SNAPSHOT']));
});
const base = { repository: 'owner/repo', token: '테스트', version: '0.0.0', sha: 'a'.repeat(40), notes: 'notes.md', assets: ['app.jar', 'setup.exe'] };
test('최초 릴리즈는 정확한 SHA·태그·노트·두 결과물로 생성한다', async () => {
  const calls = [];
  await publishRelease(base, async () => ({ status: 404 }), (args) => { calls.push(args); });
  assert.deepEqual(calls, [['release', 'create', 'v.0.0.0', '--repo', 'owner/repo', '--target', 'a'.repeat(40), '--title', 'v.0.0.0', '--notes-file', 'notes.md', 'app.jar', 'setup.exe']]);
});
test('이미 게시된 버전은 다시 만들지 않는다', async () => {
  await publishRelease(base, async () => ({ status: 200, json: async () => ({ draft: false }) }), () => assert.fail('재게시 금지'));
});
test('권한·서버 오류와 기존 초안·태그는 덮어쓰지 않는다', async () => {
  for (const status of [401, 403, 500]) {
    await assert.rejects(publishRelease(base, async () => ({ status }), () => assert.fail('게시 금지')));
  }
  await assert.rejects(publishRelease(base, async () => ({ status: 200, json: async () => ({ draft: true }) }), () => assert.fail('초안 덮어쓰기 금지')));
  let count = 0;
  await assert.rejects(publishRelease(base, async () => ({ status: ++count === 1 ? 404 : 200 }), () => assert.fail('기존 태그 덮어쓰기 금지')));
});