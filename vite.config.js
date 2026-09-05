import { execFileSync } from 'node:child_process';
import { resolve } from 'node:path';
import { defineConfig } from 'vite';
import { viteStaticCopy } from 'vite-plugin-static-copy';

// script.js kopieras obundlad (se viteStaticCopy nedan) och får därför ingen
// innehållshash i filnamnet som resten av bygget. Cache-bustern i
// promptbanken.html (?v=%VITE_BUILD_ID%) var tidigare en handskriven sträng
// som inte bumpades vid deploy, så återkommande besökare körde gammal JS.
// Här sätts den till aktuell commit i stället: ny URL per deploy, utan att
// någon behöver komma ihåg att uppdatera den. Faller tillbaka på en
// tidsstämpel när git inte finns (t.ex. i en nedladdad zip).
function resolveBuildId() {
    if (process.env.VITE_BUILD_ID) return process.env.VITE_BUILD_ID;
    try {
        return execFileSync('git', ['rev-parse', '--short', 'HEAD'], { stdio: ['ignore', 'pipe', 'ignore'] })
            .toString()
            .trim();
    } catch {
        return `t${Date.now()}`;
    }
}

process.env.VITE_BUILD_ID = resolveBuildId();

export default defineConfig({
  plugins: [
    viteStaticCopy({
      targets: [
        { src: 'prompts.json', dest: '.' },
        { src: 'llms.txt', dest: '.' },
        { src: 'robots.txt', dest: '.' },
        { src: 'sitemap.xml', dest: '.' },
        { src: 'prompts', dest: '.' },
        { src: 'fonts', dest: '.' },
        { src: 'script.js', dest: '.' },
        { src: 'style.css', dest: '.' },
        { src: '.nojekyll', dest: '.' },
        { src: 'public/.assetsignore', dest: '.' },
      ]
    })
  ],
  build: {
    rollupOptions: {
      input: {
        index: resolve(__dirname, 'index.html'),
        '404': resolve(__dirname, '404.html'),
        login: resolve(__dirname, 'login.html'),
        admin: resolve(__dirname, 'admin.html'),
        promptbanken: resolve(__dirname, 'promptbanken.html'),
        help: resolve(__dirname, 'help.html'),
        support: resolve(__dirname, 'support.html'),
        about: resolve(__dirname, 'about.html'),
        planer: resolve(__dirname, 'planer.html'),
        mcp: resolve(__dirname, 'mcp.html'),
        prompts: resolve(__dirname, 'prompts.html'),
        privacy: resolve(__dirname, 'privacy.html'),
        'privacy-en': resolve(__dirname, 'privacy-en.html'),
        'privacy-mcp': resolve(__dirname, 'privacy-mcp.html'),
        'privacy-mcp-en': resolve(__dirname, 'privacy-mcp-en.html'),
        terms: resolve(__dirname, 'terms.html'),
        'local-chat': resolve(__dirname, 'local-chat.html'),
        providers: resolve(__dirname, 'providers.html'),
        invite: resolve(__dirname, 'invite.html'),
        'team-invite': resolve(__dirname, 'team-invite.html'),
        creator: resolve(__dirname, 'creator.html'),
        'creator-profile': resolve(__dirname, 'creator-profile.html'),
        'creator-shares': resolve(__dirname, 'creator-shares.html'),
        delning: resolve(__dirname, 'delning/index.html'),
        'creator-content': resolve(__dirname, 'creator-content.html'),
        'creator-packages': resolve(__dirname, 'creator-packages.html'),
        'oauth-consent': resolve(__dirname, 'oauth/consent/index.html')
      }
    }
  }
});
