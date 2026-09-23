// 요소의 이름표(버튼 문구 등). 민감한 동작인지 판단할 때 쓴다.
(id) => {
  const el = document.querySelector(`[data-agent-id="${id}"]`);
  if (!el) return { ok: false };
  const label = [el.getAttribute('aria-label'), el.innerText, el.value, el.getAttribute('title'), el.getAttribute('alt')]
    .filter(Boolean).join(' ').replace(/\s+/g, ' ').trim().slice(0, 200);
  const form = el.form || el.closest('form');
  const formSubmitLabels = form
    ? Array.from(form.querySelectorAll('button,[type=submit]'))
        .map(b => b.getAttribute('aria-label') || b.innerText || b.value || '').join(' ').replace(/\s+/g, ' ').slice(0, 200)
    : '';
  return { ok: true, label, tag: el.tagName.toLowerCase(), type: el.type || '', formSubmitLabels };
}
