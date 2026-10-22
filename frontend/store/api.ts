import type { AuthResponse } from '../types/api';

let accessToken: string | null = null;
let refreshing: Promise<boolean> | null = null;
let initialRefresh: Promise<AuthResponse | null> | null = null;
export function setAccessToken(token: string | null) { accessToken = token; }
export function clearAccessToken() { accessToken = null; }

export function refreshSession(): Promise<AuthResponse | null> {
  if (!initialRefresh) initialRefresh = fetch('/api/auth/refresh', { method: 'POST', credentials: 'include', headers: { 'X-Requested-With': 'XMLHttpRequest' } })
    .then(async response => { if (!response.ok) return null; const auth = await response.json() as AuthResponse; accessToken = auth.accessToken; return auth; })
    .catch(() => null).finally(() => { initialRefresh = null; });
  return initialRefresh;
}

async function refresh(): Promise<boolean> {
  if (!refreshing) refreshing = fetch('/api/auth/refresh', { method: 'POST', credentials: 'include', headers: { 'X-Requested-With': 'XMLHttpRequest' } })
    .then(async response => { if (!response.ok) return false; const auth = await response.json() as AuthResponse; accessToken = auth.accessToken; return true; })
    .catch(() => false).finally(() => { refreshing = null; });
  return refreshing;
}

export async function api<T>(path: string, init: RequestInit = {}, retry = true): Promise<T> {
  const headers = new Headers(init.headers);
  headers.set('X-Requested-With', 'XMLHttpRequest');
  if (accessToken) headers.set('Authorization', `Bearer ${accessToken}`);
  if (init.body && !(init.body instanceof FormData) && !headers.has('Content-Type')) headers.set('Content-Type', 'application/json');
  const response = await fetch(path, { ...init, headers, credentials: 'include' });
  if (response.status === 401 && retry && !path.includes('/api/auth/')) {
    if (await refresh()) return api<T>(path, init, false);
    clearAccessToken();
  }
  if (response.status === 204) return undefined as T;
  if (!response.ok) {
    const error = await response.json().catch(() => ({ message: '요청을 처리하지 못했습니다. 다시 시도해 주세요.', code: 'NETWORK_ERROR' })) as { message?: string; code?: string };
    throw Object.assign(new Error(error.message || '요청을 처리하지 못했습니다.'), { status: response.status, code: error.code });
  }
  return response.json() as Promise<T>;
}

export async function apiBlob(path: string): Promise<Blob> {
  const headers = new Headers({ 'X-Requested-With': 'XMLHttpRequest' });
  if (accessToken) headers.set('Authorization', `Bearer ${accessToken}`);
  let response = await fetch(path, { headers, credentials: 'include' });
  if (response.status === 401 && await refresh()) {
    headers.set('Authorization', `Bearer ${accessToken}`);
    response = await fetch(path, { headers, credentials: 'include' });
  }
  if (!response.ok) {
    const error = await response.json().catch(() => ({ message: '파일을 내려받지 못했습니다.' })) as { message?: string };
    throw new Error(error.message || '파일을 내려받지 못했습니다.');
  }
  return response.blob();
}
