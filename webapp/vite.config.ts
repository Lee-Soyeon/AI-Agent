import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

// 레시피 카탈로그는 앱·서버와 같은 파일(../server/app/tasks.json)을 쓴다.
export default defineConfig({
  plugins: [react()],
  server: { port: 8792, fs: { allow: ['..'] } },
});
