import 'dart:convert';

/// 헤드리스 웹뷰에 주입하는 JavaScript.
///
/// 페이지의 보이는 텍스트와 조작 가능한 요소 목록을 뽑아내고, 각 요소에 `data-agent-id` 를 붙여
/// LLM 이 id 로 클릭/입력할 수 있게 한다. id 는 스냅샷을 새로 찍을 때마다 다시 매겨진다.
class DomScripts {
  static String snapshot({int maxText = 5000, int maxElements = 180}) =>
      '''
(function(maxText, maxElements){
  const SEL = 'a[href],button,input:not([type=hidden]),textarea,select,summary,'
    + '[role=button],[role=link],[role=checkbox],[role=radio],[role=tab],[role=menuitem],'
    + '[role=option],[role=switch],[role=textbox],[role=combobox],[contenteditable=""],[contenteditable=true],[onclick]';
  document.querySelectorAll('[data-agent-id]').forEach(e => e.removeAttribute('data-agent-id'));
  const vh = window.innerHeight, vw = window.innerWidth;
  function visible(el){
    const r = el.getBoundingClientRect();
    if (r.width < 1 || r.height < 1) return false;
    const s = getComputedStyle(el);
    if (s.visibility === 'hidden' || s.display === 'none' || parseFloat(s.opacity) === 0) return false;
    return !el.closest('[aria-hidden="true"]');
  }
  function clean(t){ return (t || '').replace(/\\s+/g, ' ').trim(); }
  function labelOf(el){
    let t = clean(el.getAttribute('aria-label'));
    if (!t && el.labels && el.labels.length) t = clean(el.labels[0].innerText);
    if (!t && el.tagName !== 'INPUT' && el.tagName !== 'TEXTAREA' && el.tagName !== 'SELECT') t = clean(el.innerText);
    if (!t) t = clean(el.getAttribute('placeholder'));
    if (!t) t = clean(el.getAttribute('title'));
    if (!t) t = clean(el.getAttribute('alt'));
    if (!t) { const img = el.querySelector && el.querySelector('img[alt]'); if (img) t = clean(img.alt); }
    if (!t) t = clean(el.getAttribute('name') || el.id);
    return t.length > 90 ? t.slice(0, 90) + '…' : t;
  }
  const inView = [], below = [];
  const seen = new Set();
  for (const el of document.querySelectorAll(SEL)) {
    if (!visible(el)) continue;
    // 클릭 가능한 조상 안에 중복으로 잡히는 자식은 건너뛴다.
    const parent = el.parentElement && el.parentElement.closest(SEL);
    if (parent && seen.has(parent) && !['INPUT','TEXTAREA','SELECT'].includes(el.tagName)) continue;
    seen.add(el);
    const r = el.getBoundingClientRect();
    (r.bottom >= 0 && r.top <= vh && r.right >= 0 && r.left <= vw ? inView : below).push(el);
  }
  const picked = inView.concat(below).slice(0, maxElements);
  const elements = [];
  let id = 0;
  for (const el of picked) {
    id++;
    el.setAttribute('data-agent-id', String(id));
    const tag = el.tagName.toLowerCase();
    const e = { id, tag, label: labelOf(el) };
    const role = el.getAttribute('role'); if (role) e.role = role;
    if (tag === 'input') { e.type = (el.type || 'text'); if (el.type === 'checkbox' || el.type === 'radio') e.checked = el.checked; else if (el.type !== 'password') e.value = clean(el.value).slice(0, 60); }
    if (tag === 'textarea') e.value = clean(el.value).slice(0, 60);
    if (tag === 'select') { e.value = el.options[el.selectedIndex] ? clean(el.options[el.selectedIndex].text) : ''; e.options = Array.from(el.options).slice(0, 15).map(o => clean(o.text)); }
    if (tag === 'a') { const h = el.getAttribute('href') || ''; if (h && !h.startsWith('javascript')) e.href = h.length > 120 ? h.slice(0, 120) + '…' : h; }
    if (el.disabled || el.getAttribute('aria-disabled') === 'true') e.disabled = true;
    const r = el.getBoundingClientRect();
    if (!(r.bottom >= 0 && r.top <= vh)) e.offscreen = true;
    elements.push(e);
  }
  let text = document.body ? document.body.innerText : '';
  text = text.replace(/[ \\t]+/g, ' ').replace(/\\n\\s*\\n+/g, '\\n').trim();
  if (text.length > maxText) text = text.slice(0, maxText) + '\\n…(이하 생략, scroll 후 다시 확인)';
  return JSON.stringify({
    url: location.href, title: document.title, text, elements,
    scrollY: Math.round(window.scrollY), scrollHeight: document.documentElement.scrollHeight, viewportHeight: vh
  });
})($maxText, $maxElements)
''';

  static String _find(int id) => "document.querySelector('[data-agent-id=\"$id\"]')";

  /// 요소의 이름표(버튼 문구 등)를 돌려준다. 민감한 동작인지 판단할 때 쓴다.
  static String describe(int id) =>
      '''
(function(){
  const el = ${_find(id)};
  if (!el) return JSON.stringify({ok:false});
  const t = [el.getAttribute('aria-label'), el.innerText, el.value, el.getAttribute('title'), el.getAttribute('alt')]
    .filter(Boolean).join(' ').replace(/\\s+/g,' ').trim().slice(0, 200);
  const form = el.form || el.closest('form');
  const submitLabel = form ? Array.from(form.querySelectorAll('button,[type=submit]'))
      .map(b => (b.getAttribute('aria-label') || b.innerText || b.value || '')).join(' ').replace(/\\s+/g,' ').slice(0,200) : '';
  return JSON.stringify({ok:true, label:t, tag:el.tagName.toLowerCase(), type:(el.type||''), formSubmitLabels: submitLabel});
})()
''';

  static String click(int id) =>
      '''
(function(){
  const el = ${_find(id)};
  if (!el) return JSON.stringify({ok:false, error:'요소를 찾을 수 없습니다. read_page 로 새 id 를 확인하세요.'});
  el.scrollIntoView({block:'center', inline:'center'});
  if (el.tagName === 'A' && el.getAttribute('target')) el.setAttribute('target', '_self');
  const r = el.getBoundingClientRect();
  const opts = {bubbles:true, cancelable:true, view:window, clientX:r.left + r.width/2, clientY:r.top + r.height/2};
  try { el.dispatchEvent(new PointerEvent('pointerdown', opts)); } catch(e) {}
  el.dispatchEvent(new MouseEvent('mousedown', opts));
  try { el.dispatchEvent(new PointerEvent('pointerup', opts)); } catch(e) {}
  el.dispatchEvent(new MouseEvent('mouseup', opts));
  if (typeof el.focus === 'function') el.focus();
  el.click();
  return JSON.stringify({ok:true});
})()
''';

  static String typeText(int id, String text, {bool submit = false}) =>
      '''
(function(text, submit){
  const el = ${_find(id)};
  if (!el) return JSON.stringify({ok:false, error:'요소를 찾을 수 없습니다. read_page 로 새 id 를 확인하세요.'});
  el.scrollIntoView({block:'center'});
  if (el.type === 'password') return JSON.stringify({ok:false, error:'password'});
  el.focus();
  if (el.tagName === 'SELECT') {
    const opt = Array.from(el.options).find(o => o.text.trim() === text.trim() || o.value === text)
             || Array.from(el.options).find(o => o.text.includes(text));
    if (!opt) return JSON.stringify({ok:false, error:'일치하는 옵션이 없습니다.'});
    el.value = opt.value;
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
    return JSON.stringify({ok:true, selected: opt.text});
  }
  if (el.isContentEditable) {
    el.innerText = text;
    el.dispatchEvent(new InputEvent('input', {bubbles:true, data:text, inputType:'insertText'}));
  } else {
    const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value').set;
    setter.call(el, text); // React 등 프레임워크가 값 변경을 감지하도록 네이티브 setter 사용
    el.dispatchEvent(new Event('input', {bubbles:true}));
    el.dispatchEvent(new Event('change', {bubbles:true}));
  }
  if (submit) {
    const ev = {key:'Enter', code:'Enter', keyCode:13, which:13, bubbles:true, cancelable:true};
    el.dispatchEvent(new KeyboardEvent('keydown', ev));
    el.dispatchEvent(new KeyboardEvent('keypress', ev));
    el.dispatchEvent(new KeyboardEvent('keyup', ev));
    const form = el.form;
    if (form) { if (form.requestSubmit) form.requestSubmit(); else form.submit(); }
  }
  return JSON.stringify({ok:true});
})(${jsonEncode(text)}, $submit)
''';

  static String scroll(String direction) =>
      '''
(function(dir){
  const h = window.innerHeight * 0.8;
  if (dir === 'top') window.scrollTo(0, 0);
  else if (dir === 'bottom') window.scrollTo(0, document.documentElement.scrollHeight);
  else window.scrollBy(0, dir === 'up' ? -h : h);
  return JSON.stringify({ok:true, scrollY: Math.round(window.scrollY)});
})(${jsonEncode(direction)})
''';

  static const readyState = 'document.readyState';
}
