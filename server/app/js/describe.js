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
  const attrs = [el.getAttribute('autocomplete'), el.name, el.id, el.getAttribute('placeholder'),
    el.getAttribute('aria-label'), el.labels && el.labels[0] ? el.labels[0].innerText : ''].filter(Boolean).join(' ');
  // 카드번호·CVC·유효기간·결제 비밀번호 칸은 에이전트가 입력하지 못하게 표시한다
  const paymentField = /^cc-/i.test(el.getAttribute('autocomplete') || '') ||
    /(card.?(num|no)|카드\s*번호|cvc|cvv|보안\s*코드|유효\s*기간|expir|카드\s*비밀번호|결제\s*비밀번호)/i.test(attrs);
  return { ok: true, label, tag: el.tagName.toLowerCase(), type: el.type || '', formSubmitLabels, paymentField };
}
