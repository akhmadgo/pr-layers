'use strict';

const API_KEY = 'zeroth_api_endpoint';
const DEFAULT_API = 'http://localhost:8080';

const CATS = {
  logic:     { label: 'Core Logic',  color: '#3B82F6' },
  syntax:    { label: 'Syntax',      color: '#6B7280' },
  aws:       { label: 'AWS',         color: '#F97316' },
  terraform: { label: 'Terraform',   color: '#8B5CF6' },
  ci:        { label: 'CI/CD',       color: '#D97706' },
  tests:     { label: 'Tests',       color: '#16A34A' },
  deps:      { label: 'Deps',        color: '#DB2777' },
  config:    { label: 'Config',      color: '#0891B2' },
};

let cache = {};
let activeFilter = null;

function onPRPage() {
  return /\/pull\/\d+/.test(location.pathname);
}

function extractFiles() {
  const files = [];
  document.querySelectorAll('.file').forEach(el => {
    const header = el.querySelector('.file-header');
    const path = header?.getAttribute('data-path')
              || el.querySelector('[data-path]')?.getAttribute('data-path')
              || el.querySelector('.file-info a')?.getAttribute('title')
              || el.querySelector('.file-info a')?.textContent?.trim();
    if (!path) return;
    const added = [...el.querySelectorAll('.blob-code-addition .blob-code-inner')]
      .slice(0, 20).map(l => `+${l.textContent}`).join('\n').slice(0, 400);
    files.push({ path, patch: added, el });
  });
  return files;
}

function getEndpoint() {
  return new Promise(r =>
    chrome.storage.sync.get([API_KEY], d => r(d[API_KEY] || DEFAULT_API))
  );
}

async function callAPI(files) {
  const endpoint = await getEndpoint();
  const res = await fetch(`${endpoint}/analyze`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      files: files.map(f => ({ path: f.path, patch: f.patch || '' })),
      pr_title: document.querySelector('.js-issue-title, h1.gh-header-title span')
                        ?.textContent?.trim(),
    }),
  });
  if (!res.ok) throw new Error(`Zeroth API ${res.status}`);
  return res.json();
}

function renderBar(byCategory) {
  document.getElementById('zeroth-bar')?.remove();
  const bar = document.createElement('div');
  bar.id = 'zeroth-bar';

  const chips = Object.entries(byCategory)
    .sort((a, b) => b[1] - a[1])
    .map(([cat, count]) => {
      const def = CATS[cat] || { label: cat, color: '#6B7280' };
      const isActive = activeFilter === cat;
      return `<button class="z-chip${isActive ? ' z-active' : ''}" data-cat="${cat}"
        style="--c:${def.color}">
        <span class="z-dot"></span>${def.label}<span class="z-n">${count}</span>
      </button>`;
    }).join('');

  bar.innerHTML = `<div class="z-bar">
    <span class="z-logo">zeroth</span>
    <div class="z-chips">${chips}</div>
    <button class="z-reset${activeFilter ? '' : ' z-hidden'}" id="z-reset">Show all</button>
  </div>`;

  const anchor = document.querySelector('#files, .js-diff-progressive-container');
  anchor?.insertAdjacentElement('beforebegin', bar);

  bar.querySelectorAll('.z-chip').forEach(btn => {
    btn.addEventListener('click', () => {
      activeFilter = activeFilter === btn.dataset.cat ? null : btn.dataset.cat;
      applyFilter();
      renderBar(byCategory);
    });
  });
  document.getElementById('z-reset')?.addEventListener('click', () => {
    activeFilter = null;
    applyFilter();
    renderBar(byCategory);
  });
}

function applyFilter() {
  document.querySelectorAll('.file[data-zcat]').forEach(el => {
    el.classList.toggle('z-hidden', !!(activeFilter && el.dataset.zcat !== activeFilter));
  });
}

function labelFiles(result, fileEls) {
  const byPath = Object.fromEntries(result.files.map(f => [f.path, f]));
  fileEls.forEach(({ path, el }) => {
    const info = byPath[path];
    if (!info) return;
    const { category: cat, color, label } = info;
    el.dataset.zcat = cat;
    el.querySelector('.z-badge')?.remove();
    const header = el.querySelector('.file-header');
    if (!header) return;
    const badge = document.createElement('span');
    badge.className = 'z-badge';
    badge.style.cssText = `background:${color}22;color:${color};border:1px solid ${color}55`;
    badge.textContent = label;
    header.appendChild(badge);
  });
}

function showLoading(fileEls) {
  fileEls.forEach(({ el }) => {
    el.querySelector('.z-badge')?.remove();
    const header = el.querySelector('.file-header');
    if (!header) return;
    const badge = document.createElement('span');
    badge.className = 'z-badge z-loading';
    badge.textContent = '…';
    header.appendChild(badge);
  });
}

let timer = null;

function schedule() {
  clearTimeout(timer);
  timer = setTimeout(run, 900);
}

async function run() {
  if (!onPRPage()) return;
  const fileEls = extractFiles();
  if (!fileEls.length) return;

  const key = fileEls.map(f => f.path).sort().join('|');
  if (cache[key]) {
    labelFiles(cache[key], fileEls);
    renderBar(cache[key].summary?.by_category || {});
    applyFilter();
    return;
  }

  showLoading(fileEls);

  try {
    const result = await callAPI(fileEls);
    cache[key] = result;
    labelFiles(result, fileEls);
    renderBar(result.summary?.by_category || {});
    applyFilter();
  } catch (err) {
    console.warn('[zeroth]', err.message);
    fileEls.forEach(({ el }) => el.querySelector('.z-badge')?.remove());
  }
}

// Watch for GitHub lazy-loading file diffs
new MutationObserver(mutations => {
  const added = mutations.some(m =>
    [...m.addedNodes].some(n => n.nodeType === 1 &&
      (n.classList?.contains('file') || n.querySelector?.('.file')))
  );
  if (added) schedule();
}).observe(document.body, { childList: true, subtree: true });

// Handle GitHub SPA navigation
let lastHref = location.href;
new MutationObserver(() => {
  if (location.href !== lastHref) {
    lastHref = location.href;
    cache = {};
    activeFilter = null;
    document.getElementById('zeroth-bar')?.remove();
    schedule();
  }
}).observe(document, { subtree: true, childList: true });

schedule();
