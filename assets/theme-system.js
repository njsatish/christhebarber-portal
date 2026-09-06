(function(){
'use strict';
var THEMES=['copper','navy-gold','forest-brass','burgundy-cream','slate-blue','midnight-teal'];
var DEFAULT_THEME='copper';
var STORAGE_KEY='christhebarber-theme';
var root=document.documentElement;
var params=new URLSearchParams(location.search);
var requested=params.get('theme');
if(params.get('resetTheme')==='1'){try{localStorage.removeItem(STORAGE_KEY)}catch(e){}}
var stored=null;try{stored=localStorage.getItem(STORAGE_KEY)}catch(e){}
var markup=root.getAttribute('data-theme');
var selected=THEMES.includes(requested)?requested:(THEMES.includes(stored)?stored:(THEMES.includes(markup)?markup:DEFAULT_THEME));
root.setAttribute('data-theme',selected);
if(params.get('rememberTheme')==='1'&&THEMES.includes(requested)){try{localStorage.setItem(STORAGE_KEY,requested)}catch(e){}}
window.CHRIS_THEME={names:THEMES.slice(),current:function(){return root.getAttribute('data-theme')},apply:function(name,persist){if(!THEMES.includes(name))return false;root.setAttribute('data-theme',name);if(persist){try{localStorage.setItem(STORAGE_KEY,name)}catch(e){}}document.dispatchEvent(new CustomEvent('christhemechange',{detail:{theme:name}}));return true},clear:function(){try{localStorage.removeItem(STORAGE_KEY)}catch(e){}root.setAttribute('data-theme',DEFAULT_THEME)}};

function norm(v){return(v||'').replace(/\s+/g,' ').trim().toUpperCase()}
function tv(n,f){return getComputedStyle(root).getPropertyValue(n).trim()||f}
function imp(el,p,v){el.style.setProperty(p,v,'important')}
function applyNavigation(){
 var primary=tv('--theme-primary','#c9793f'),hover=tv('--theme-primary-hover','#b86832'),onPrimary=tv('--theme-on-primary','#111315'),text=tv('--theme-text','#111315');
 var file=(location.pathname.split('/').pop()||'index.html');var map={'index.html':'HOME','about.html':'ABOUT','work.html':'GALLERY','contact.html':'CONTACT','booking.html':'BOOK NOW'};var active=map[file]||'HOME';
 Array.from(document.querySelectorAll('a,button,summary,[role="link"],[role="button"]')).forEach(function(el){var label=norm(el.textContent);if(!['HOME','ABOUT','GALLERY','CONTACT','BOOK NOW','MENU','CLOSE'].includes(label))return;var isActive=label===active||label==='BOOK NOW'||label==='CLOSE'||el.getAttribute('aria-current')==='page';imp(el,'background-color',isActive?primary:'transparent');imp(el,'border-color',isActive?primary:'transparent');imp(el,'color',isActive?onPrimary:(label==='MENU'?primary:text));imp(el,'-webkit-text-fill-color',isActive?onPrimary:(label==='MENU'?primary:text));el.dataset.themeActive=isActive?'true':'false';if(!el.dataset.themeListeners){el.addEventListener('mouseenter',function(){if(el.dataset.themeActive==='true'){imp(el,'background-color',hover);imp(el,'border-color',hover)}});el.addEventListener('mouseleave',applyNavigation);el.dataset.themeListeners='1'}})
}
function applyHours(){var days=['SUNDAY','MONDAY','TUESDAY','WEDNESDAY','THURSDAY','FRIDAY','SATURDAY'];var cards=Array.from(document.querySelectorAll('section,article,div,main')).filter(function(el){var t=norm(el.textContent);return days.every(function(d){return t.includes(d)})}).sort(function(a,b){return a.textContent.length-b.textContent.length});var card=cards[0];if(!card)return;card.classList.add('themed-business-hours-card');var primary=tv('--theme-primary','#c9793f'),dark=tv('--theme-dark','#111315'),onDark=tv('--theme-on-dark','#fff'),muted=tv('--theme-muted-on-dark','#d7ccbc');imp(card,'background-color',dark);imp(card,'color',onDark);card.querySelectorAll('*').forEach(function(el){var own=norm(Array.from(el.childNodes).filter(function(n){return n.nodeType===3}).map(function(n){return n.textContent}).join(' '));if(own.includes('BUSINESS HOURS')||own.includes('CHECK CURRENT OPENINGS')||/10:00\s*AM.*5:00\s*PM/.test(own)){imp(el,'color',primary);imp(el,'-webkit-text-fill-color',primary)}if(own==='CLOSED'){imp(el,'color',muted);imp(el,'-webkit-text-fill-color',muted)}})}
function applyAll(){applyNavigation();applyHours()}
document.addEventListener('DOMContentLoaded',applyAll,{once:true});document.addEventListener('christhemechange',applyAll);window.addEventListener('pageshow',applyAll);setTimeout(applyAll,100);setTimeout(applyAll,600);
})();
