import { priorityLabels } from '../types/api';
import { useWorkspace } from '../store/WorkspaceContext';
import CommentPanel from './CommentPanel';
export default function ItemDetail() {
  const { user, users, selected, toggleStatus, openCreate, openEdit } = useWorkspace();
  if (!user) return null;
  return (<section className="detail-card" aria-label="항목 상세">{selected ? <><div className="detail-top"><span className="level-tag">{['최상위', '세부 항목', '하위 항목'][selected.depth - 1]}</span>{selected.editable && <button className="secondary compact" onClick={() => openEdit(selected)}>수정</button>}</div><div className="detail-title"><button className={`check large ${selected.status === 'DONE' ? 'checked' : ''}`} aria-label={selected.status === 'DONE' ? '미완료로 표시' : '완료로 표시'} onClick={() => selected.editable && void toggleStatus(selected)} disabled={!selected.editable}>{selected.status === 'DONE' ? '✓' : ''}</button><h2>{selected.title}</h2></div><p className="detail-description">{selected.description || '상세 내용이 없습니다.'}</p><div className="detail-facts"><div><span>우선순위</span><b>{priorityLabels[selected.priority || 'NORMAL']}</b></div><div><span>마감기한</span><b>{selected.dueDate || '미지정'}</b></div><div><span>담당자</span><b>{users.find(person => person.id === selected.assigneeId)?.name || '미지정'}</b></div></div>{selected.editable && selected.depth < 3 && <button className="secondary full-width" onClick={() => openCreate(selected)}>＋ 하위 항목 추가</button>}
        <CommentPanel /></> : <div className="detail-placeholder"><div className="placeholder-mark">↖</div><h2>항목을 선택하세요</h2><p>목록에서 항목을 선택하면 상세 내용과 댓글을 볼 수 있습니다.</p></div>}</section>);
}
