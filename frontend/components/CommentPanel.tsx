import { useWorkspace } from '../store/WorkspaceContext';

export default function CommentPanel() {
  const { user, selected, comments, setError, busy, replyTo, setReplyTo, downloadAttachment, submitComment, toggleImportance } = useWorkspace();
  if (!user || !selected) return null;
  return (<div className="comments">
    <h3>댓글 <span>{comments.length}</span></h3>
    {comments.filter(comment => comment.parentId === null).map(comment => <article className={`comment ${comment.important ? 'important-comment' : ''}`} key={comment.id}>
      <div className="comment-head"><b>{comment.important && <span className="important-tag">중요</span>}{comment.author.name}</b><time>{new Date(comment.createdAt).toLocaleString('ko-KR')}</time></div>
      {comment.body && <p>{comment.body}</p>}
      {comment.attachments.map(file => <button className="file-link" key={file.id} onClick={() => downloadAttachment(file)}>↓ {file.filename} · {Math.ceil(file.size / 1024)}KB</button>)}
      {selected.editable && <div className="comment-tools"><button className="reply-button" onClick={() => setReplyTo(comment.id)}>답글</button><button className="text-button" disabled={busy} onClick={() => void toggleImportance(comment)}>{comment.important ? '중요 해제' : '중요 댓글로 등록'}</button></div>}
      {comments.filter(reply => reply.parentId === comment.id).map(reply => <div className="reply" key={reply.id}><b>{reply.author.name}</b><p>{reply.body}</p>{reply.attachments.map(file => <button className="file-link" key={file.id} onClick={() => downloadAttachment(file)}>↓ {file.filename} · {Math.ceil(file.size / 1024)}KB</button>)}</div>)}
    </article>)}
    {selected.editable ? <form className="comment-form" onSubmit={submitComment}>
      <textarea name="body" maxLength={10000} placeholder={replyTo ? '답글을 입력하세요' : '댓글을 입력하세요'} aria-label={replyTo ? '답글 내용' : '댓글 내용'} />
      {replyTo ? <button type="button" className="text-button" onClick={() => setReplyTo(null)}>답글 취소</button> : <label className="check-label comment-important-option"><input type="checkbox" name="important" />중요 댓글로 등록</label>}
      <div className="comment-actions"><label className="attach-button">파일 첨부<input type="file" name="files" multiple onChange={event => { const total = [...(event.target.files || [])].reduce((sum, file) => sum + file.size, 0); if (total > 500000000) { setError('첨부 파일 합계는 500,000,000바이트 이하여야 합니다.'); event.target.value = ''; } }} /></label><button className="primary" disabled={busy}>등록</button></div>
      <small>첨부 파일 합계 최대 500MB</small>
    </form> : <p className="permission-note">이 항목은 읽기 전용입니다.</p>}
  </div>);
}