// 입력창에 값을 넣는다 (React 등이 감지하도록 네이티브 setter 사용). select 는 옵션 선택.
({ id, text, submit }) => {
  const el = document.querySelector(`[data-agent-id="${id}"]`);
  if (!el) return { ok: false, error: '요소를 찾을 수 없습니다. read_page 로 새 id 를 확인하세요.' };
  el.scrollIntoView({ block: 'center' });
  if (el.type === 'password') return { ok: false, error: 'password' };
  el.focus();
  if (el.tagName === 'SELECT') {
    const opts = Array.from(el.options);
    const opt = opts.find(o => o.text.trim() === text.trim() || o.value === text) || opts.find(o => o.text.includes(text));
    if (!opt) return { ok: false, error: '일치하는 옵션이 없습니다.' };
    el.value = opt.value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
    return { ok: true, selected: opt.text };
  }
  if (el.isContentEditable) {
    el.innerText = text;
    el.dispatchEvent(new InputEvent('input', { bubbles: true, data: text, inputType: 'insertText' }));
  } else {
    const proto = el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, text);
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  }
  if (submit) {
    const ev = { key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true, cancelable: true };
    el.dispatchEvent(new KeyboardEvent('keydown', ev));
    el.dispatchEvent(new KeyboardEvent('keypress', ev));
    el.dispatchEvent(new KeyboardEvent('keyup', ev));
    if (el.form) { if (el.form.requestSubmit) el.form.requestSubmit(); else el.form.submit(); }
  }
  return { ok: true };
}
