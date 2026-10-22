import { useWorkspace } from '../store/WorkspaceContext';
import { refreshSession } from '../store/api';
export default function AuthPage() {
  const { authMode, setAuthMode, email, setEmail, password, setPassword, name, setName, error, setError, busy, enter, submitAuth } = useWorkspace();

  return (<main className="auth-screen"><section className="auth-card"><a className="brand" href="/" aria-label="체크리스트 홈"><span className="brand-mark">✓</span>체크리스트</a><h1>{authMode === 'login' ? '로그인' : '계정 만들기'}</h1><p>팀의 업무를 한곳에서 확인하고 정리하세요.</p>{error && <div className="alert" role="alert">{error} <button onClick={() => { setError(''); void refreshSession().then(auth => { if (auth) return enter(auth); }); }}>다시 시도</button></div>}
    <form onSubmit={submitAuth}>{authMode === 'register' && <label>이름<input required value={name} onChange={event => setName(event.target.value)} autoComplete="name" /></label>}<label>이메일<input required type="email" value={email} onChange={event => setEmail(event.target.value)} autoComplete="email" /></label><label>비밀번호<input required type="password" minLength={8} maxLength={72} value={password} onChange={event => setPassword(event.target.value)} autoComplete={authMode === 'login' ? 'current-password' : 'new-password'} /></label><button className="primary full" disabled={busy}>{authMode === 'login' ? '로그인' : '가입하기'}</button></form>
    <button className="text-button" onClick={() => { setAuthMode(authMode === 'login' ? 'register' : 'login'); setError(''); }}>{authMode === 'login' ? '처음이신가요? 계정 만들기' : '이미 계정이 있나요? 로그인'}</button></section></main>);
}
