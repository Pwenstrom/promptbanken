import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import { viteStaticCopy } from 'vite-plugin-static-copy';

export default defineConfig({
  plugins: [
    viteStaticCopy({
      targets: [
        { src: 'prompts.json', dest: '.' },
        { src: 'prompts', dest: '.' },
        { src: 'script.js', dest: '.' },
        { src: 'style.css', dest: '.' },
        { src: '.nojekyll', dest: '.' },
      ]
    })
  ],
  build: {
    rollupOptions: {
      input: {
        index: resolve(__dirname, 'index.html'),
        login: resolve(__dirname, 'login.html'),
        admin: resolve(__dirname, 'admin.html'),
        promptbanken: resolve(__dirname, 'promptbanken.html'),
        help: resolve(__dirname, 'help.html'),
        mcp: resolve(__dirname, 'mcp.html'),
        privacy: resolve(__dirname, 'privacy.html'),
        terms: resolve(__dirname, 'terms.html'),
        'local-chat': resolve(__dirname, 'local-chat.html'),
        providers: resolve(__dirname, 'providers.html')
      }
    }
  }
});
