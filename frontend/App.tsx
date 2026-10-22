import AuthPage from './pages/AuthPage';
import ChecklistPage from './pages/ChecklistPage';
import { WorkspaceProvider, useWorkspace } from './store/WorkspaceContext';
function WorkspaceRouter() {
  const { user } = useWorkspace();
  return user ? <ChecklistPage /> : <AuthPage />;
}
export default function App() {
  return <WorkspaceProvider><WorkspaceRouter /></WorkspaceProvider>;
}
