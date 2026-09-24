// 주문·결제·예약 완료 페이지인지 판단한다 (결제를 사용자에게 넘긴 뒤 자동으로 이어가기 위해).
() => {
  const kw = /(주문이?\s*완료|결제가?\s*완료|주문\s*완료|구매\s*완료|예매\s*완료|예약\s*완료|예약이\s*확정|order\s*(is\s*)?(complete|confirmed|placed)|thank you for your order)/i;
  const heads = Array.from(document.querySelectorAll('h1,h2,h3,[class*=complete],[class*=Complete],[class*=success],[class*=Success]'))
    .map(e => e.innerText || '').join(' ').slice(0, 2000);
  const url = location.href;
  const urlHint = /(complete|success|done|finish|result)/i.test(url) && /(order|pay|checkout|reserv|book|ticket)/i.test(url);
  const body = document.body ? document.body.innerText.slice(0, 3000) : '';
  return kw.test(document.title || '') || kw.test(heads) || (urlHint && kw.test(body));
}
