import { ThemeProvider } from '@montage-ui/core';
import { createRoot } from 'react-dom/client';

import App from './App';

import '@montage-ui/core/global.css';
import './theme.css';

createRoot(document.getElementById('app')!).render(
  <ThemeProvider>
    <App />
  </ThemeProvider>,
);
