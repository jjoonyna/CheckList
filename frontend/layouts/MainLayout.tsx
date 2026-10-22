import type { ReactNode } from 'react';
import { useWorkspace } from '../store/WorkspaceContext';
export default function MainLayout({ children }: { children: ReactNode }) {
const { user, logout } = useWorkspace();
if (!user) return null;
return <div className="workspace-app"><aside className="sidebar"><a className="brand" href="/" aria-label="체크리스트 홈"><span className="brand-mark">✓</span><span>체크리스트</span></a><div className="team-label">업무 공간</div><nav aria-label="주요 메뉴"><button className="nav-link active"><span>▦</span>체크리스트</button></nav><div className="side-bottom"><div className="user-chip"><span className="avatar">{user.name.slice(0, 1)}</span><span><b>{user.name}</b><small>{user.email}</small></span></div><button className="nav-link" onClick={logout}>로그아웃</button></div></aside>{children}</div>;
}
