// 보이는 텍스트와 조작 가능한 요소를 뽑고, 각 요소에 data-agent-id 를 붙인다.
({ maxText, maxElements }) => {
  const SEL = 'a[href],button,input:not([type=hidden]),textarea,select,summary,'
    + '[role=button],[role=link],[role=checkbox],[role=radio],[role=tab],[role=menuitem],'
    + '[role=option],[role=switch],[role=textbox],[role=combobox],[contenteditable=""],[contenteditable=true],[onclick]';
  document.querySelectorAll('[data-agent-id]').forEach(e => e.removeAttribute('data-agent-id'));
  const vh = window.innerHeight, vw = window.innerWidth;
  const visible = el => {
    const r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    const s = getComputedStyle(el);
    if (s.visibility === 'hidden' || s.display === 'none' || parseFloat(s.opacity) === 0) return false;
    return !el.closest('[aria-hidden="true"]');
  };
  const clean = t => (t || '').replace(/\s+/g, ' ').trim();
  const labelOf = el => {
    let t = clean(el.getAttribute('aria-label'));
    if (!t && el.labels && el.labels.length) t = clean(el.labels[0].innerText);
    if (!t && !['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName)) t = clean(el.innerText);
    if (!t) t = clean(el.getAttribute('placeholder'));
    if (!t) t = clean(el.getAttribute('title'));
    if (!t) t = clean(el.getAttribute('alt'));
    if (!t) { const img = el.querySelector && el.querySelector('img[alt]'); if (img) t = clean(img.alt); }
    if (!t) t = clean(el.getAttribute('name') || el.id);
    return t.length > 90 ? t.slice(0, 90) + '…' : t;
  };
  const inView = [], below = [], seen = new Set();
  for (const el of document.querySelectorAll(SEL)) {
    if (!visible(el)) continue;
    const parent = el.parentElement && el.parentElement.closest(SEL);
    if (parent && seen.has(parent) && !['INPUT', 'TEXTAREA', 'SELECT'].includes(el.tagName)) continue;
    seen.add(el);
    const r = el.getBoundingClientRect();
    (r.bottom >= 0 && r.top <= vh && r.right >= 0 && r.left <= vw ? inView : below).push(el);
  }
  const elements = [];
  let id = 0;
  for (const el of inView.concat(below).slice(0, maxElements)) {
    id++;
    el.setAttribute('data-agent-id', String(id));
    const tag = el.tagName.toLowerCase();
    const e = { id, tag, label: labelOf(el) };
    const role = el.getAttribute('role'); if (role) e.role = role;
    if (tag === 'input') {
      e.type = el.type || 'text';
      if (el.type === 'checkbox' || el.type === 'radio') e.checked = el.checked;
      else if (el.type !== 'password') e.value = clean(el.value).slice(0, 60);
    }
    if (tag === 'textarea') e.value = clean(el.value).slice(0, 60);
    if (tag === 'select') {
      e.value = el.options[el.selectedIndex] ? clean(el.options[el.selectedIndex].text) : '';
      e.options = Array.from(el.options).slice(0, 15).map(o => clean(o.text));
    }
    if (tag === 'a') {
      const h = el.getAttribute('href') || '';
      if (h && !h.startsWith('javascript')) e.href = h.length > 120 ? h.slice(0, 120) + '…' : h;
    }
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') e.disabled = true;
    const r = el.getBoundingClientRect();
    if (!(r.bottom >= 0 && r.top <= vh)) e.offscreen = true;
    elements.push(e);
  }
  let text = document.body ? document.body.innerText : '';
  text = text.replace(/[ \t]+/g, ' ').replace(/\n\s*\n+/g, '\n').trim();
  if (text.length > maxText) text = text.slice(0, maxText) + '\n…(이하 생략, scroll 후 다시 확인)';
  return {
    url: location.href, title: document.title, text, elements,
    scrollY: Math.round(window.scrollY), scrollHeight: document.documentElement.scrollHeight, viewportHeight: vh,
  };
}
