const KEY = 'zeroth_api_endpoint';
const ep = document.getElementById('ep');
const ok = document.getElementById('ok');

chrome.storage.sync.get([KEY], d => { ep.value = d[KEY] || 'http://localhost:8080'; });

document.getElementById('save').addEventListener('click', () => {
  chrome.storage.sync.set({ [KEY]: ep.value.trim() }, () => {
    ok.style.display = 'block';
    setTimeout(() => { ok.style.display = 'none'; }, 1600);
  });
});
