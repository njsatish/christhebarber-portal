const b=document.querySelector('#menu'),n=document.querySelector('#nav');b.addEventListener('click',()=>{const o=b.getAttribute('aria-expanded')!=='true';b.setAttribute('aria-expanded',o);b.textContent=o?'CLOSE':'MENU';n.classList.toggle('open',o)});n.querySelectorAll('a').forEach(a=>a.addEventListener('click',()=>{b.setAttribute('aria-expanded','false');b.textContent='MENU';n.classList.remove('open')}));document.querySelector('#year').textContent=new Date().getFullYear();



/* RUNTIME ACTIVE NAVIGATION START */
(() => {
  const nav = document.querySelector('.site-header nav[aria-label="Primary navigation"]') ||
    document.querySelector('.site-header nav');
  if (!nav) return;

  const aliases = {
    '/': '/index.html',
    '': '/index.html',
    '/book/': '/booking.html',
    '/reviews.html': '/index.html',
    '/policy.html': '/booking.html'
  };

  let current = window.location.pathname || '/index.html';
  current = aliases[current] || current;
  if (current.endsWith('/')) current += 'index.html';

  const links = [...nav.querySelectorAll('a[href]')];
  links.forEach((link) => {
    link.classList.remove('cfm-active-page', 'nav-current');
    link.removeAttribute('aria-current');

    let target;
    try {
      target = new URL(link.getAttribute('href'), window.location.origin).pathname;
    } catch {
      return;
    }
    target = aliases[target] || target;
    if (target.endsWith('/')) target += 'index.html';

    if (target === current) {
      link.classList.add('cfm-active-page');
      link.setAttribute('aria-current', 'page');
    }
  });
})();
/* RUNTIME ACTIVE NAVIGATION END */
