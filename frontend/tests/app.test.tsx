// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest';
import '@testing-library/jest-dom/vitest';
import { cleanup, render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import App from '../App';

afterEach(() => {
  cleanup();
  vi.restoreAllMocks();
  sessionStorage.clear();
});

const currentUser = { id: 1, email: 'minji@example.com', name: '민지' };
const tree = [
  { id: 10, parentId: null, rootId: 10, depth: 1, title: '분기 보고서', description: '자료를 정리합니다', dueDate: '2026-10-30', assigneeId: 1, editorIds: [1], createdBy: 1, status: 'OPEN', version: 0, editable: true, matchesFilter: true, sourceUrl: null },
  { id: 11, parentId: 10, rootId: 10, depth: 2, title: '매출 자료', description: '월별 표', dueDate: null, assigneeId: 1, editorIds: [1], createdBy: 1, status: 'OPEN', version: 0, editable: true, matchesFilter: true, sourceUrl: null },
  { id: 12, parentId: 11, rootId: 10, depth: 3, title: '10월 수치 확인', description: '검산', dueDate: null, assigneeId: 1, editorIds: [1], createdBy: 1, status: 'OPEN', version: 0, editable: true, matchesFilter: true, sourceUrl: null },
];

function mockApi() {
  const fetchMock = vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    if (url.endsWith('/api/auth/refresh')) return Response.json({ message: '로그인이 필요합니다', code: 'UNAUTHORIZED' }, { status: 401 });
    if (url.endsWith('/api/auth/login') || url.endsWith('/api/auth/register')) return Response.json({ user: currentUser, accessToken: 'access' });
    if (url.endsWith('/api/auth/me')) return Response.json(currentUser);
    if (url.endsWith('/api/users')) return Response.json([currentUser, { id: 2, email: 'yuna@example.com', name: '유나' }]);
    if (url.includes('/api/items?')) return Response.json(tree);
    if (url.endsWith('/api/items/12/comments')) return Response.json([{ id: 50, itemId: 12, parentId: null, author: currentUser, body: '확인했습니다', createdAt: '2026-10-21T09:00:00Z', attachments: [] }]);
    if (url.endsWith('/api/github/issues')) return Response.json({ issues: [{ number: 7, title: '로그인 화면 개선', body: '접근성 보완', htmlUrl: 'https://github.com/team/app/issues/7', state: 'open' }], hasNext: false, page: 1 });
    if (url.endsWith('/api/items/12/status')) return Response.json({ ...tree[2], status: 'DONE', version: 1 });
    if (url.endsWith('/api/items') && init?.method === 'POST') return Response.json({ ...tree[0], id: 13, title: '새 작업' });
    return new Response(null, { status: 204 });
  });
  vi.stubGlobal('fetch', fetchMock);
  return fetchMock;
}

describe('체크리스트 사용자 흐름', () => {
  async function login(user: ReturnType<typeof userEvent.setup>) {
    render(<App />);
    await user.type(screen.getByLabelText('이메일'), 'minji@example.com');
    await user.type(screen.getByLabelText('비밀번호'), 'secure-pass-1');
    await user.click(screen.getByRole('button', { name: '로그인', exact: true }));
    await screen.findByRole('button', { name: '분기 보고서', exact: true });
  }

  it('처음에는 3단계를 펼치고 자식이 있는 항목에만 접기 버튼을 표시한다', async () => {
    const user = userEvent.setup();
    mockApi();
    await login(user);
    expect(screen.getByRole('button', { name: '분기 보고서 하위 항목 접기' })).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByRole('button', { name: '매출 자료 하위 항목 접기' })).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByRole('button', { name: '10월 수치 확인', exact: true })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: /10월 수치 확인 하위 항목 (접기|펼치기)/ })).not.toBeInTheDocument();
  });

  it('화살표로 자손을 숨기고 복원하며 중간 부모의 접힘 상태와 상세 선택을 유지한다', async () => {
    const user = userEvent.setup();
    const fetchMock = mockApi();
    const normal = fetchMock.getMockImplementation()!;
    fetchMock.mockImplementation(async (input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input).endsWith('/api/items/10/comments')) return Response.json([]);
      return normal(input, init);
    });
    await login(user);
    await user.click(screen.getByRole('button', { name: '10월 수치 확인', exact: true }));
    expect(await screen.findByText('확인했습니다')).toBeInTheDocument();
    fetchMock.mockClear();
    await user.click(screen.getByRole('button', { name: '매출 자료 하위 항목 접기' }));
    expect(screen.queryByRole('button', { name: '10월 수치 확인', exact: true })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: '매출 자료 하위 항목 펼치기' })).toHaveAttribute('aria-expanded', 'false');
    await user.click(screen.getByRole('button', { name: '분기 보고서 하위 항목 접기' }));
    expect(screen.queryByRole('button', { name: '매출 자료', exact: true })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: '분기 보고서 하위 항목 펼치기' })).toHaveAttribute('aria-expanded', 'false');
    expect(screen.getByRole('heading', { name: '10월 수치 확인' })).toBeInTheDocument();
    expect(screen.getByText('확인했습니다')).toBeInTheDocument();
    expect(fetchMock).not.toHaveBeenCalled();
    await user.click(screen.getByRole('button', { name: '분기 보고서', exact: true }));
    expect(screen.getByText('자료를 정리합니다')).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: '매출 자료', exact: true })).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: '분기 보고서 하위 항목 펼치기' }));
    expect(screen.getByRole('button', { name: '매출 자료 하위 항목 펼치기' })).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByRole('button', { name: '10월 수치 확인', exact: true })).not.toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: '매출 자료 하위 항목 펼치기' }));
    expect(screen.getByRole('button', { name: '10월 수치 확인', exact: true })).toBeInTheDocument();
    expect(screen.getByText('자료를 정리합니다')).toBeInTheDocument();
    expect(fetchMock.mock.calls.filter(([input]) => String(input).endsWith('/comments')).map(([input]) => input)).toEqual(['/api/items/10/comments']);
  });

  it('한 부모를 접어도 다른 부모는 펼친 상태를 유지하고 키보드로 토글할 수 있다', async () => {
    const user = userEvent.setup();
    const fetchMock = mockApi();
    const normal = fetchMock.getMockImplementation()!;
    fetchMock.mockImplementation(async (input: RequestInfo | URL, init?: RequestInit) => {
      if (String(input).includes('/api/items?')) return Response.json([...tree,
        { ...tree[0], id: 20, rootId: 20, title: '다른 보고서' },
        { ...tree[1], id: 21, parentId: 20, rootId: 20, title: '다른 자료' },
      ]);
      return normal(input, init);
    });
    await login(user);
    const toggle = screen.getByRole('button', { name: '분기 보고서 하위 항목 접기' });
    toggle.focus();
    await user.keyboard('{Enter}');
    expect(toggle).toHaveFocus();
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    expect(screen.queryByRole('button', { name: '매출 자료', exact: true })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: '다른 자료', exact: true })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: '다른 보고서 하위 항목 접기' })).toHaveAttribute('aria-expanded', 'true');
    await user.keyboard(' ');
    expect(toggle).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByRole('button', { name: '10월 수치 확인', exact: true })).toBeInTheDocument();
  });

  it('가입과 로그인을 제공하고 로그인 후 체크리스트를 연다', async () => {
    const user = userEvent.setup();
    mockApi();
    render(<App />);
    await user.click(await screen.findByRole('button', { name: '처음이신가요? 계정 만들기' }));
    await user.type(screen.getByLabelText('이름'), '민지');
    await user.type(screen.getByLabelText('이메일'), 'minji@example.com');
    await user.type(screen.getByLabelText('비밀번호'), 'secure-pass-1');
    await user.click(screen.getByRole('button', { name: '가입하기' }));
    expect(await screen.findByRole('heading', { name: '체크리스트' })).toBeInTheDocument();
    expect(screen.getByText('분기 보고서')).toBeInTheDocument();
    expect(screen.getByLabelText('기간')).toHaveValue('thisMonth');
    await user.click(screen.getByRole('button', { name: '로그아웃' }));
    expect(await screen.findByRole('heading', { name: '로그인' })).toBeInTheDocument();
    await user.type(screen.getByLabelText('이메일'), 'minji@example.com');
    await user.type(screen.getByLabelText('비밀번호'), 'secure-pass-1');
    await user.click(screen.getByRole('button', { name: '로그인' }));
    expect(await screen.findByRole('heading', { name: '체크리스트' })).toBeInTheDocument();
  });

  it('3단계 트리 선택, 독립 완료, 필터 조회와 상세 댓글을 처리한다', async () => {
    const user = userEvent.setup();
    const fetchMock = mockApi();
    render(<App />);
    await user.type(screen.getByLabelText('이메일'), 'minji@example.com');
    await user.type(screen.getByLabelText('비밀번호'), 'secure-pass-1');
    await user.click(await screen.findByRole('button', { name: '로그인' }));
    await user.click(await screen.findByRole('button', { name: '10월 수치 확인' }));
    expect(screen.getByText('하위 항목')).toBeInTheDocument();
    expect(await screen.findByText('검산')).toBeInTheDocument();
    expect(await screen.findByText('확인했습니다')).toBeInTheDocument();
    await user.click(screen.getByRole('button', { name: '완료로 표시' }));
    expect(fetchMock).toHaveBeenCalledWith('/api/items/12/status', expect.objectContaining({ method: 'PATCH' }));
    await user.selectOptions(screen.getByLabelText('상태'), 'done');
    await waitFor(() => expect(fetchMock).toHaveBeenCalledWith(expect.stringContaining('status=done'), expect.anything()));
    expect(within(screen.getByRole('navigation')).getByText('체크리스트')).toBeInTheDocument();
  });

  it('권한 없는 항목은 수정 동작을 숨기고 완료 동작을 비활성화한다', async () => {
    const user = userEvent.setup();
    const fetchMock = mockApi();
    fetchMock.mockImplementation(async (input: RequestInfo | URL) => {
      if (String(input).endsWith('/api/auth/refresh')) return Response.json({ message: '로그인이 필요합니다', code: 'UNAUTHORIZED' }, { status: 401 });
      if (String(input).endsWith('/api/auth/login')) return Response.json({ user: currentUser, accessToken: 'access' });
      if (String(input).endsWith('/api/auth/me')) return Response.json(currentUser);
      if (String(input).endsWith('/api/users')) return Response.json([currentUser]);
      if (String(input).includes('/api/items?')) return Response.json([{ ...tree[0], editable: false }]);
      return Response.json({ message: '일시적인 오류입니다', code: 'ERROR' }, { status: 503 });
    });
    render(<App />);
    await user.type(screen.getByLabelText('이메일'), 'minji@example.com');
    await user.type(screen.getByLabelText('비밀번호'), 'secure-pass-1');
    await user.click(await screen.findByRole('button', { name: '로그인' }));
    await user.click(await screen.findByRole('button', { name: '분기 보고서' }));
    expect(screen.queryByRole('button', { name: '수정' })).not.toBeInTheDocument();
    expect(screen.getByRole('button', { name: '완료로 표시' })).toBeDisabled();
  });

  it('로그아웃 후 가입 모드가 남지 않고 로그인 폼을 보여준다', async () => {
    const user = userEvent.setup(); mockApi(); render(<App />);
    await user.click(await screen.findByRole('button', { name: '처음이신가요? 계정 만들기' }));
    await user.type(screen.getByLabelText('이름'), '민지');
    await user.type(screen.getByLabelText('이메일'), 'minji@example.com');
    await user.type(screen.getByLabelText('비밀번호'), 'secure-pass-1');
    await user.click(screen.getByRole('button', { name: '가입하기' }));
    await user.click(await screen.findByRole('button', { name: '로그아웃' }));
    expect(await screen.findByRole('heading', { name: '로그인' })).toBeInTheDocument();
    expect(screen.queryByLabelText('이름')).not.toBeInTheDocument();
  });
  it('담당자가 남아 편집자 제외가 거절되면 편집 창 안에서 이유를 보여준다', async () => {
    const user=userEvent.setup();const fetchMock=mockApi();const normal=fetchMock.getMockImplementation()!;
    const message='하위 항목에 담당자로 지정된 계정은 편집자에서 제외할 수 없습니다. 담당자를 먼저 변경해 주세요.';
    fetchMock.mockImplementation(async (input:RequestInfo | URL,init?:RequestInit) => {
      if(String(input).includes('/api/items?'))return Response.json(tree.map(row=>({...row,editorIds:[1,2]})));
      if(String(input).endsWith('/comments'))return Response.json([]);
      if(String(input).endsWith('/api/items/10')&&init?.method==='PATCH')return Response.json({code:'EDITOR_STILL_ASSIGNED',message},{status:400});
      return normal(input,init);
    });
    render(<App />);
    await user.type(screen.getByLabelText('이메일'),'minji@example.com');await user.type(screen.getByLabelText('비밀번호'),'secure-pass-1');
    await user.click(screen.getByRole('button',{name:'로그인',exact:true}));
    await user.click(await screen.findByRole('button',{name:'분기 보고서',exact:true}));
    await user.click(screen.getByRole('button',{name:'수정',exact:true}));
    const dialog=screen.getByRole('dialog');
    await user.click(within(dialog).getByRole('checkbox',{name:'유나',exact:true}));
    await user.click(within(dialog).getByRole('button',{name:'저장',exact:true}));
    expect(await within(dialog).findByRole('alert')).toHaveTextContent(message);
    expect(within(dialog).getByLabelText('제목')).toHaveValue('분기 보고서');
  });
  it('우선순위 다섯 단계와 기본값을 제공하고 생성·수정 요청에 담는다', async () => {
    const user=userEvent.setup();const fetchMock=mockApi();const normal=fetchMock.getMockImplementation()!;
    fetchMock.mockImplementation(async (input:RequestInfo | URL,init?:RequestInit)=>{
      if(String(input).includes('/api/items?'))return Response.json(tree.map(row=>({...row,priority:'HIGH'})));
      if(String(input).endsWith('/comments'))return Response.json([]);
      if(String(input).endsWith('/api/items')&&init?.method==='POST')return Response.json({...tree[0],id:13,...JSON.parse(String(init.body))});
      if(String(input).endsWith('/api/items/10')&&init?.method==='PATCH')return Response.json({...tree[0],...JSON.parse(String(init.body)),version:1});
      return normal(input,init);
    });
    render(<App />);await user.type(screen.getByLabelText('이메일'),'minji@example.com');await user.type(screen.getByLabelText('비밀번호'),'secure-pass-1');await user.click(screen.getByRole('button',{name:'로그인',exact:true}));
    await user.click(await screen.findByRole('button',{name:'＋ 새 항목',exact:true}));
    let dialog=screen.getByRole('dialog');const priority=within(dialog).getByLabelText('우선순위',{exact:true});
    expect(priority).toHaveValue('NORMAL');expect(within(priority).getAllByRole('option').map(option=>option.textContent)).toEqual(['긴급','높음','보통','낮음','고려']);
    await user.type(within(dialog).getByLabelText('제목'),'우선순위 새 작업');await user.selectOptions(priority,'CONSIDER');await user.click(within(dialog).getByRole('button',{name:'저장',exact:true}));
    await waitFor(()=>expect(screen.queryByRole('dialog')).not.toBeInTheDocument());
    expect(fetchMock).toHaveBeenCalledWith('/api/items',expect.objectContaining({method:'POST',body:expect.stringContaining('"priority":"CONSIDER"')}));
    await user.click(screen.getByRole('button',{name:'분기 보고서',exact:true}));await user.click(screen.getByRole('button',{name:'수정',exact:true}));dialog=screen.getByRole('dialog');
    expect(within(dialog).getByLabelText('우선순위',{exact:true})).toHaveValue('HIGH');await user.selectOptions(within(dialog).getByLabelText('우선순위',{exact:true}),'URGENT');await user.click(within(dialog).getByRole('button',{name:'저장',exact:true}));
    await waitFor(()=>expect(fetchMock).toHaveBeenCalledWith('/api/items/10',expect.objectContaining({method:'PATCH',body:expect.stringContaining('"priority":"URGENT"')})));
  });
  it('원댓글을 중요 표시하면 답글 묶음도 같이 올라가며 해제·신규 중요 등록이 가능하다', async () => {
    const user=userEvent.setup();const fetchMock=mockApi();const normal=fetchMock.getMockImplementation()!;
    const author=currentUser;let comments=[{id:72,itemId:10,parentId:70,author,body:'따라가는 답글',createdAt:'2026-10-03T00:00:00Z',attachments:[],important:false},{id:71,itemId:10,parentId:null,author,body:'최신 일반 댓글',createdAt:'2026-10-02T00:00:00Z',attachments:[],important:false},{id:70,itemId:10,parentId:null,author,body:'묶음 원댓글',createdAt:'2026-10-01T00:00:00Z',attachments:[],important:false}];
    function sort(){comments.sort((a,b)=>Number(b.important)-Number(a.important)||b.createdAt.localeCompare(a.createdAt)||b.id-a.id);}
    fetchMock.mockImplementation(async(input:RequestInfo|URL,init?:RequestInit)=>{
      if(String(input).endsWith('/api/comments/70/importance')&&init?.method==='PATCH'){comments=comments.map(row=>row.id===70?{...row,important:JSON.parse(String(init.body)).important}:row);sort();return Response.json(comments.find(row=>row.id===70));}
      if(String(input).endsWith('/api/items/10/comments')){
        if(init?.method==='POST'){const form=init.body as FormData;const added={id:73,itemId:10,parentId:null,author,body:String(form.get('body')),createdAt:'2026-10-04T00:00:00Z',attachments:[],important:form.get('important')==='true'};comments.push(added);sort();return Response.json(added);}
        return Response.json(comments);
      }
      return normal(input,init);
    });
    render(<App />);await user.type(screen.getByLabelText('이메일'),'minji@example.com');await user.type(screen.getByLabelText('비밀번호'),'secure-pass-1');await user.click(screen.getByRole('button',{name:'로그인',exact:true}));await user.click(await screen.findByRole('button',{name:'분기 보고서',exact:true}));
    const old=(await screen.findByText('묶음 원댓글',{exact:true})).closest('article')!;
    await user.click(within(old).getByRole('button',{name:'중요 댓글로 등록',exact:true}));
    await waitFor(()=>{const first=document.querySelector('.comment')!;expect(first).toHaveTextContent('묶음 원댓글');expect(first).toHaveTextContent('따라가는 답글');});
    expect(fetchMock).toHaveBeenCalledWith('/api/comments/70/importance',expect.objectContaining({method:'PATCH',body:'{"important":true}'}));
    await user.click(within(document.querySelector('.comment') as HTMLElement).getByRole('button',{name:'중요 해제',exact:true}));
    await waitFor(()=>expect(document.querySelector('.comment')).toHaveTextContent('최신 일반 댓글'));
    await user.type(screen.getByRole('textbox',{name:'댓글 내용',exact:true}),'새 중요 댓글');await user.click(screen.getByRole('checkbox',{name:'중요 댓글로 등록',exact:true}));await user.click(screen.getByRole('button',{name:'등록',exact:true}));
    await waitFor(()=>expect(document.querySelector('.comment')).toHaveTextContent('새 중요 댓글'));
  });
  it('기존 상세내용이 있는 항목도 이름으로 수정 필드를 찾아 편집한다', async () => {
    const user=userEvent.setup();mockApi();render(<App />);
    await user.type(screen.getByLabelText('이메일'),'minji@example.com');
    await user.type(screen.getByLabelText('비밀번호'),'secure-pass-1');
    await user.click(screen.getByRole('button',{name:'로그인',exact:true}));
    await user.click(await screen.findByRole('button',{name:'10월 수치 확인',exact:true}));
    await user.click(screen.getByRole('button',{name:'수정',exact:true}));
    const dialog=screen.getByRole('dialog');
    const details=within(dialog).getByLabelText('상세 내용',{exact:true});
    expect(details).toHaveValue('검산');
    await user.clear(details);await user.type(details,'수정된 세부 내용');
    expect(details).toHaveValue('수정된 세부 내용');
  });});
