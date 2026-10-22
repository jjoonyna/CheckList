import { createContext, useContext, useEffect, useState, useRef, type FormEvent, type ReactNode } from 'react';
import { api, apiBlob, clearAccessToken, refreshSession, setAccessToken } from './api';
import type { AuthResponse, Comment, GithubIssue, Item, ItemPriority, User } from '../types/api';
export type Filters = { scope: 'all' | 'mine'; status: 'all' | 'open' | 'done'; period: string; q: string; from: string; to: string };
const initialFilters: Filters = { scope: 'all', status: 'all', period: 'thisMonth', q: '', from: new Date().toLocaleDateString('sv-SE').slice(0, 7) + '-01', to: new Date().toLocaleDateString('sv-SE') };
function useWorkspaceState() {
  const [user, setUser] = useState<User | null>(null);
  const [authMode, setAuthMode] = useState<'login' | 'register'>('login');
  const [email, setEmail] = useState(''); const [password, setPassword] = useState(''); const [name, setName] = useState('');
  const [items, setItems] = useState<Item[]>([]); const [users, setUsers] = useState<User[]>([]); const [selected, setSelected] = useState<Item | null>(null);
  const selectedIdRef=useRef<number|null>(null);selectedIdRef.current=selected?.id ?? null;
  const [comments, setComments] = useState<Comment[]>([]); const [filters, setFilters] = useState(initialFilters);
  const [error, setError] = useState(''); const [busy, setBusy] = useState(false); const [replyTo, setReplyTo] = useState<number | null>(null);
  const [showEditor, setShowEditor] = useState(false); const [showGithub, setShowGithub] = useState(false); const [issues, setIssues] = useState<GithubIssue[]>([]);
  const [editingId, setEditingId] = useState<number | null>(null);
  const [issuePage, setIssuePage] = useState(1); const [hasMoreIssues, setHasMoreIssues] = useState(false);
  const [repository, setRepository] = useState(''); const [token, setToken] = useState(''); const [chosenIssues, setChosenIssues] = useState<number[]>([]); const [parentId, setParentId] = useState(''); const [githubParentId, setGithubParentId] = useState('');
  const [draft, setDraft] = useState({ title: '', description: '', dueDate: '', priority: 'NORMAL' as ItemPriority, assigneeId: '', editorIds: [] as number[] });

  async function loadItems(next = filters) {
    const params = new URLSearchParams({ scope: next.scope, status: next.status, period: next.period });
    if (next.period === 'custom') { if (!next.from || !next.to) return; params.set('from', next.from); params.set('to', next.to); }
    if (next.q.trim()) params.set('q', next.q.trim());
    try { setItems(await api<Item[]>(`/api/items?${params}`)); setError(''); } catch (reason) { showError(reason); }
  }
  async function enter(auth: AuthResponse) { setAccessToken(auth.accessToken); setUser(auth.user); setError(''); const people = await api<User[]>('/api/users'); setUsers(people); }
  useEffect(() => { let alive = true; void refreshSession().then(async auth => { if (alive && auth) await enter(auth); }); return () => { alive = false; }; }, []);
  useEffect(() => { if (user) loadItems().catch(showError); }, [filters.scope, filters.status, filters.period, filters.q, filters.from, filters.to, user]);
  useEffect(() => { let alive = true; setReplyTo(null); setComments([]); if (!selected || !user) return () => { alive = false; }; api<Comment[]>(`/api/items/${selected.id}/comments`).then(value => { if (alive) setComments(value); }).catch(showError); return () => { alive = false; }; }, [selected?.id, user]);
  function showError(reason: unknown) { setError(reason instanceof Error ? reason.message : '요청을 처리하지 못했습니다. 다시 시도해 주세요.'); }
  function downloadAttachment(file: { id: number; filename: string }) { void apiBlob(`/api/attachments/${file.id}/download`).then(blob => { const url = URL.createObjectURL(blob); const link = document.createElement('a'); link.href = url; link.download = file.filename; link.click(); window.setTimeout(() => URL.revokeObjectURL(url), 1000); }).catch(showError); }

  async function submitAuth(event: FormEvent) {
    event.preventDefault(); setBusy(true); setError('');
    try { const path = authMode === 'login' ? '/api/auth/login' : '/api/auth/register'; await enter(await api<AuthResponse>(path, { method: 'POST', body: JSON.stringify(authMode === 'login' ? { email, password } : { email, password, name }) })); }
    catch (reason) { showError(reason); } finally { setBusy(false); }
  }
  async function logout() { setError(''); try { await api('/api/auth/logout', { method: 'POST' }); clearAccessToken(); setUser(null); setSelected(null); setItems([]); setComments([]); setReplyTo(null); setAuthMode('login'); setEmail(''); setPassword(''); } catch (reason) { showError(reason); } }
  async function reload() { setError(''); try { await loadItems(); if (selected) { const latest = (await api<Item[]>(`/api/items?scope=${filters.scope}&status=all&period=${filters.period}${filters.period === 'custom' ? '&from=' + filters.from + '&to=' + filters.to : ''}`)).find(item => item.id === selected.id) || null; setSelected(latest); if (latest) setComments(await api<Comment[]>(`/api/items/${latest.id}/comments`)); } } catch (reason) { showError(reason); } }
  async function toggleStatus(item: Item) { setError(''); try { const updated = await api<Item>(`/api/items/${item.id}/status`, { method: 'PATCH', body: JSON.stringify({ status: item.status === 'DONE' ? 'OPEN' : 'DONE', version: item.version }) }); setItems(old => old.map(row => row.id === item.id ? updated : row)); setSelected(updated); await loadItems(); } catch (reason) { const issue = reason as Error & { status?: number }; showError(issue.status === 409 ? new Error('다른 사람이 변경했습니다. 최신 내용을 불러온 뒤 다시 시도해 주세요.') : reason); } }
  function openCreate(parent: Item | null) { setError(''); setEditingId(null); setDraft({ title: '', description: '', dueDate: '', priority: 'NORMAL' as ItemPriority, assigneeId: '', editorIds: parent ? parent.editorIds : [user!.id] }); setParentId(parent ? String(parent.id) : ''); setShowEditor(true); }
  function openEdit(item: Item) { setError(''); setEditingId(item.id); setDraft({ title: item.title, description: item.description, dueDate: item.dueDate || '', priority: item.priority || 'NORMAL', assigneeId: item.assigneeId ? String(item.assigneeId) : '', editorIds: item.editorIds }); setParentId(item.parentId ? String(item.parentId) : ''); setShowEditor(true); }
  async function saveItem(event: FormEvent) { event.preventDefault(); if (!draft.title.trim()) return; setBusy(true); try { const parent = parentId ? items.find(item => item.id === Number(parentId)) : null; const payload = { title: draft.title.trim(), description: draft.description, priority: draft.priority, dueDate: draft.dueDate || null, assigneeId: draft.assigneeId ? Number(draft.assigneeId) : null, ...(parentId ? { parentId: Number(parentId) } : { parentId: null, editorIds: draft.editorIds }), ...(selected && draft.title === selected.title ? { version: selected.version } : {}) };
      const editing = editingId === null ? null : items.find(item => item.id === editingId) || null;
      const result = editing ? await api<Item>(`/api/items/${editing.id}`, { method: 'PATCH', body: JSON.stringify({ ...payload, parentId: editing.parentId, version: editing.version }) }) : await api<Item>('/api/items', { method: 'POST', body: JSON.stringify(payload) });
      void parent; setShowEditor(false); await loadItems(); setSelected(result);
    } catch (reason) { const issue = reason as Error & { status?: number }; showError(issue.status === 409 ? new Error('최신 항목을 불러왔습니다. 변경 내용을 확인해 주세요.') : reason); if (issue.status === 409) void reload(); } finally { setBusy(false); } }
  async function submitComment(event: FormEvent<HTMLFormElement>) { event.preventDefault(); if (!selected) return; const form = event.currentTarget; const data = new FormData(form); const files = data.getAll('files').filter((value): value is File => value instanceof File && value.size > 0); if (files.reduce((sum, file) => sum + file.size, 0) > 500000000) { setError('첨부 파일 합계는 500,000,000바이트 이하여야 합니다.'); return; }
    const body = String(data.get('body') || ''); if (!body.trim() && !files.length) return; const upload = new FormData(); upload.set('body', body); upload.set('important', !replyTo && data.get('important') === 'on' ? 'true' : 'false'); if (replyTo) upload.set('parentId', String(replyTo)); files.forEach(file => upload.append('files', file)); setBusy(true); try { await api<Comment>(`/api/items/${selected.id}/comments`, { method: 'POST', body: upload }); form.reset(); setReplyTo(null); setComments(await api<Comment[]>(`/api/items/${selected.id}/comments`)); } catch (reason) { showError(reason); } finally { setBusy(false); } }
  async function toggleImportance(comment: Comment) {
    if (!selected) return;const itemId=selected.id;setBusy(true);setError('');
    try { await api<Comment>(`/api/comments/${comment.id}/importance`,{method:'PATCH',body:JSON.stringify({important:!comment.important})});const rows=await api<Comment[]>(`/api/items/${itemId}/comments`);if(selectedIdRef.current===itemId)setComments(rows); }
    catch(reason){showError(reason);}finally{setBusy(false);}
  }
  function closeGithub() { setShowGithub(false); setToken(''); setRepository(''); setIssues([]); setIssuePage(1); setHasMoreIssues(false); setChosenIssues([]); setGithubParentId(''); }
  async function fetchIssues(event: { preventDefault: () => void }, page = 1) { event.preventDefault(); setBusy(true); try { const result = await api<{ issues: GithubIssue[]; hasNext: boolean; page: number }>('/api/github/issues', { method: 'POST', body: JSON.stringify({ repository, ...(token ? { token } : {}), page, state: 'open' }) }); setIssues(result.issues); setIssuePage(result.page); setHasMoreIssues(result.hasNext); setError(''); } catch (reason) { showError(reason); } finally { setBusy(false); } }
  async function importIssues() { setBusy(true); try { await api('/api/github/import', { method: 'POST', body: JSON.stringify({ repository, ...(token ? { token } : {}), issueNumbers: chosenIssues, ...(githubParentId ? { parentId: Number(githubParentId) } : {}) }) }); closeGithub(); await loadItems(); } catch (reason) { showError(reason); } finally { setBusy(false); } }


  return { user, setUser, authMode, setAuthMode, email, setEmail, password, setPassword, name, setName, items, setItems, users, setUsers, selected, setSelected, comments, setComments, filters, setFilters, error, setError, busy, setBusy, replyTo, setReplyTo, showEditor, setShowEditor, showGithub, setShowGithub, issues, setIssues, editingId, setEditingId, issuePage, setIssuePage, hasMoreIssues, setHasMoreIssues, repository, setRepository, token, setToken, chosenIssues, setChosenIssues, parentId, setParentId, githubParentId, setGithubParentId, draft, setDraft, loadItems, enter, showError, downloadAttachment, submitAuth, logout, reload, toggleStatus, openCreate, openEdit, saveItem, submitComment, toggleImportance, closeGithub, fetchIssues, importIssues };
}
const WorkspaceContext = createContext<ReturnType<typeof useWorkspaceState> | null>(null);
export function WorkspaceProvider({ children }: { children: ReactNode }) {
  const state = useWorkspaceState();
  return <WorkspaceContext.Provider value={state}>{children}</WorkspaceContext.Provider>;
}
export function useWorkspace() {
  const state = useContext(WorkspaceContext);
  if (!state) throw new Error('업무 공간 상태가 초기화되지 않았습니다.');
  return state;
}
