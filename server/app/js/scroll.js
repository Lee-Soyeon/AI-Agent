(dir) => {
  const h = window.innerHeight * 0.8;
  if (dir === 'top') window.scrollTo(0, 0);
  else if (dir === 'bottom') window.scrollTo(0, document.documentElement.scrollHeight);
  else window.scrollBy(0, dir === 'up' ? -h : h);
  return { ok: true, scrollY: Math.round(window.scrollY) };
}
