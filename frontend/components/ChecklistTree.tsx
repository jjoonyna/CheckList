import { priorityLabels } from '../types/api';
import { useLayoutEffect, useMemo, useRef, useState, type DragEvent, type KeyboardEvent, type ReactElement } from 'react';
import type { Item } from '../types/api';
import { useWorkspace } from '../store/WorkspaceContext';
export default function ChecklistTree() {
const { items, selected, setSelected, reorder } = useWorkspace();
  const dragging = useRef<Item | null>(null);
  const focusAfter = useRef<number | null>(null);
  const [drop, setDrop] = useState<{ id: number; after: boolean } | null>(null);
  const [collapsedIds, setCollapsedIds] = useState<Set<number>>(() => new Set());
  function toggleCollapsed(id: number) {
    setCollapsedIds(previous => {
      const next = new Set(previous);
      if (next.has(id)) next.delete(id); else next.add(id);
      return next;
    });
  }
  const children = useMemo(() => { const map = new Map<number | null, Item[]>(); items.forEach(item => map.set(item.parentId, [...(map.get(item.parentId) || []), item])); return map; }, [items]);
  useLayoutEffect(() => { if (focusAfter.current !== null) { document.querySelector<HTMLElement>(`[data-handle="${focusAfter.current}"]`)?.focus(); focusAfter.current = null; } }, [items]);
  function move(item: Item, to: number) {
    const ids = (children.get(item.parentId) || []).map(row => row.id); const from = ids.indexOf(item.id);
    if (to < 0 || to >= ids.length || to === from) return;
    ids.splice(to, 0, ids.splice(from, 1)[0]); void reorder(item.parentId, ids);
  }
  function keyMove(event: KeyboardEvent, item: Item) {
    if (!event.altKey || (event.key !== 'ArrowUp' && event.key !== 'ArrowDown')) return;
    event.preventDefault();
    const siblings = children.get(item.parentId) || []; const to = siblings.findIndex(row => row.id === item.id) + (event.key === 'ArrowUp' ? -1 : 1);
    if (to < 0 || to >= siblings.length) return;
    focusAfter.current = item.id; move(item, to);
  }
  function dragOver(event: DragEvent<HTMLDivElement>, item: Item) {
    const from = dragging.current; if (!from || from.parentId !== item.parentId || (event.target as Element).closest('.tree-row') !== event.currentTarget) return;
    event.preventDefault(); event.stopPropagation();
    const head = event.currentTarget.firstElementChild!.getBoundingClientRect(); setDrop({ id: item.id, after: event.clientY > head.top + head.height / 2 });
  }
  function dropOn(event: DragEvent<HTMLDivElement>, item: Item) {
    const from = dragging.current; if (!from || from.parentId !== item.parentId || !drop || (event.target as Element).closest('.tree-row') !== event.currentTarget) return;
    event.preventDefault(); event.stopPropagation(); if (from.id === item.id) { setDrop(null); return; }
    const ids = (children.get(item.parentId) || []).map(row => row.id).filter(id => id !== from.id);
    ids.splice(ids.indexOf(item.id) + (drop.after ? 1 : 0), 0, from.id); dragging.current = null; setDrop(null); focusAfter.current = from.id; void reorder(item.parentId, ids);
  }
  function treeRows(parent: number | null = null): ReactElement[] { return (children.get(parent) || []).map(item => <div className={`tree-row depth-${item.depth} ${selected?.id === item.id ? 'selected' : ''} ${item.matchesFilter ? '' : 'context'} ${drop?.id === item.id ? (drop.after ? 'drop-after' : 'drop-before') : ''}`} key={item.id} onDragOver={event => dragOver(event, item)} onDrop={event => dropOn(event, item)}>
    <span role="button" tabIndex={0} title="드래그 또는 Alt+↑/↓로 순서 이동" className="icon-button drag-handle" draggable data-handle={item.id} aria-label={`${item.title} 순서 이동`} onKeyDown={event => keyMove(event, item)} onDragStart={event => { dragging.current = item; event.dataTransfer.effectAllowed = 'move'; event.dataTransfer.setData('text/plain', String(item.id)); }} onDragEnd={() => { dragging.current = null; setDrop(null); }}>⋮⋮</span>
    <button className="tree-select" onClick={() => setSelected(item)} aria-label={item.title}><span className={`check ${item.status === 'DONE' ? 'checked' : ''}`} aria-hidden="true">{item.status === 'DONE' ? '✓' : ''}</span><span className="tree-title">{item.title}</span><span className={`priority-badge priority-${item.priority || 'NORMAL'}`} aria-label={`우선순위 ${priorityLabels[item.priority || 'NORMAL']}`}>{priorityLabels[item.priority || 'NORMAL']}</span><span className="tree-meta">{item.dueDate || '기한 없음'}</span></button>
    {children.get(item.id)?.length ? <button type="button" className="icon-button tree-toggle" aria-label={`${item.title} 하위 항목 ${collapsedIds.has(item.id) ? '펼치기' : '접기'}`} aria-expanded={!collapsedIds.has(item.id)} onClick={() => toggleCollapsed(item.id)}><span aria-hidden="true">{collapsedIds.has(item.id) ? '▸' : '▾'}</span></button> : <span className="tree-toggle" aria-hidden="true" />}{!collapsedIds.has(item.id) && treeRows(item.id)}</div>); }
return <div className="tree-list">{treeRows()}</div>;
}
