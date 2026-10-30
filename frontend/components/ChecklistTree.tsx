import { priorityLabels } from '../types/api';
import { useMemo, useState, type ReactElement } from 'react';
import type { Item } from '../types/api';
import { useWorkspace } from '../store/WorkspaceContext';
export default function ChecklistTree() {
const { items, selected, setSelected, openCreate } = useWorkspace();
  const [collapsedIds, setCollapsedIds] = useState<Set<number>>(() => new Set());
  function toggleCollapsed(id: number) {
    setCollapsedIds(previous => {
      const next = new Set(previous);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }
  const children = useMemo(() => { const map = new Map<number | null, Item[]>(); items.forEach(item => map.set(item.parentId, [...(map.get(item.parentId) || []), item])); return map; }, [items]);
  function treeRows(parent: number | null = null): ReactElement[] { return (children.get(parent) || []).map(item => <div className={`tree-row depth-${item.depth} ${selected?.id === item.id ? 'selected' : ''} ${item.matchesFilter ? '' : 'context'}`} key={item.id}>
    {!!children.get(item.id)?.length && <button type="button" className="icon-button tree-toggle" aria-label={`${item.title} 하위 항목 ${collapsedIds.has(item.id) ? '펼치기' : '접기'}`} aria-expanded={!collapsedIds.has(item.id)} onClick={() => toggleCollapsed(item.id)}><span aria-hidden="true">{collapsedIds.has(item.id) ? '▸' : '▾'}</span></button>}
    <button className="tree-select" onClick={() => setSelected(item)} aria-label={item.title}><span className={`check ${item.status === 'DONE' ? 'checked' : ''}`} aria-hidden="true">{item.status === 'DONE' ? '✓' : ''}</span><span className="tree-title">{item.title}</span><span className={`priority-badge priority-${item.priority || 'NORMAL'}`} aria-label={`우선순위 ${priorityLabels[item.priority || 'NORMAL']}`}>{priorityLabels[item.priority || 'NORMAL']}</span><span className="tree-meta">{item.dueDate || '기한 없음'}</span></button>
    {item.editable && item.depth < 3 && <button className="icon-button add-child" aria-label={`${item.title} 하위 항목 추가`} onClick={() => { setSelected(item); openCreate(item); }}>+</button>}{!collapsedIds.has(item.id) && treeRows(item.id)}</div>); }
return <div className="tree-list">{treeRows()}</div>;
}
