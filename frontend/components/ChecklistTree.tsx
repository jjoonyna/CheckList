import { priorityLabels } from '../types/api';
import { useMemo, type ReactElement } from 'react';
import type { Item } from '../types/api';
import { useWorkspace } from '../store/WorkspaceContext';
export default function ChecklistTree() {
const { items, selected, setSelected, openCreate } = useWorkspace();
  const children = useMemo(() => { const map = new Map<number | null, Item[]>(); items.forEach(item => map.set(item.parentId, [...(map.get(item.parentId) || []), item])); return map; }, [items]);
  function treeRows(parent: number | null = null): ReactElement[] { return (children.get(parent) || []).map(item => <div className={`tree-row depth-${item.depth} ${selected?.id === item.id ? 'selected' : ''} ${item.matchesFilter ? '' : 'context'}`} key={item.id}>
    <button className="tree-select" onClick={() => setSelected(item)} aria-label={item.title}><span className={`check ${item.status === 'DONE' ? 'checked' : ''}`} aria-hidden="true">{item.status === 'DONE' ? '✓' : ''}</span><span className="tree-title">{item.title}</span><span className={`priority-badge priority-${item.priority || 'NORMAL'}`} aria-label={`우선순위 ${priorityLabels[item.priority || 'NORMAL']}`}>{priorityLabels[item.priority || 'NORMAL']}</span><span className="tree-meta">{item.dueDate || '기한 없음'}</span></button>
    {item.editable && item.depth < 3 && <button className="icon-button add-child" aria-label={`${item.title} 하위 항목 추가`} onClick={() => { setSelected(item); openCreate(item); }}>+</button>}{treeRows(item.id)}</div>); }
return <div className="tree-list">{treeRows()}</div>;
}
