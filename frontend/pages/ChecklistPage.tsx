import { useWorkspace } from '../store/WorkspaceContext';
import MainLayout from '../layouts/MainLayout';
import ChecklistFilters from '../components/ChecklistFilters';
import ChecklistTree from '../components/ChecklistTree';
import EmptyState from '../components/EmptyState';
import ItemDetail from '../components/ItemDetail';
import ItemEditorModal from '../components/ItemEditorModal';
import GithubImportModal from '../components/GithubImportModal';
export default function ChecklistPage() {
  const { user, items, setSelected, error, showEditor, setShowGithub, setIssues, setRepository, setToken, setChosenIssues, setGithubParentId, reload, openCreate } = useWorkspace();
  if (!user) return null;
  return (<MainLayout><main className="main-panel"><header className="topbar"><div><div className="breadcrumb">업무 공간 <span>/</span> 체크리스트</div><h1>체크리스트</h1></div><div className="top-actions"><button className="secondary" onClick={() => { setRepository(''); setToken(''); setIssues([]); setChosenIssues([]); setGithubParentId(''); setShowGithub(true); }}>GitHub에서 가져오기</button><button className="primary" onClick={() => { setSelected(null); openCreate(null); }}>＋ 새 항목</button></div></header>
      {error && !showEditor && <div className="alert global-alert" role="alert">{error}<button onClick={() => void reload()}>다시 시도</button></div>}
      <ChecklistFilters />
      <div className="content-grid"><section className="list-card"><div className="list-heading"><h2>업무 목록</h2><span>{items.length}개 항목</span></div>{items.length ? <ChecklistTree /> : <EmptyState />}</section><ItemDetail /></div>
    </main><ItemEditorModal /><GithubImportModal /></MainLayout>);
}
