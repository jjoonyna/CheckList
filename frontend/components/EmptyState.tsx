import { useWorkspace } from '../store/WorkspaceContext';

export default function EmptyState() {
  const { user, openCreate } = useWorkspace();
  if (!user) return null;
  return (<div className="empty-state"><div className="empty-icon">✓</div><h3>표시할 항목이 없습니다</h3><p>새 항목을 만들어 업무를 정리해 보세요.</p><button className="primary" onClick={() => openCreate(null)}>첫 항목 만들기</button></div>);
}
