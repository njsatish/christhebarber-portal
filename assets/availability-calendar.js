(() => {
  const API_ENDPOINT = "https://pjw8t599rb.execute-api.us-east-1.amazonaws.com/api/v1/availability";
  const SERVICE_ID = "s5fcf71d64953606227d3e7740166772d785cdf32";
  const STAFF_ID = "r99f585095ff06863ec494873de9023fdf26d353f";
  const MAX_FUTURE_DAYS = 60;
  const root = document.querySelector("[data-availability-calendar]");
  if (!root) return;

  const refs = {
    dateStrip: root.querySelector("[data-date-strip]"), status: root.querySelector("[data-status]"),
    slotPanel: root.querySelector("[data-slot-panel]"), slotGrid: root.querySelector("[data-slot-grid]"),
    selectedDateLabel: root.querySelector("[data-selected-date-label]"), summary: root.querySelector("[data-summary]"),
    summaryDate: root.querySelector("[data-summary-date]"), summaryTime: root.querySelector("[data-summary-time]"),
    continueButton: root.querySelector("[data-continue]"), prev: root.querySelector("[data-prev-week]"),
    next: root.querySelector("[data-next-week]"), rangeLabel: root.querySelector("[data-range-label]")
  };
  const state = { rangeStart: startOfDay(new Date()), slots: [], selectedDate: null, selectedSlot: null, loading: false };
  function startOfDay(d){ return new Date(d.getFullYear(),d.getMonth(),d.getDate()); }
  function addDays(d,n){ const x=new Date(d);x.setDate(x.getDate()+n);return x; }
  function iso(d){ return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,"0")}-${String(d.getDate()).padStart(2,"0")}`; }
  function displayDate(d, opts){ return new Intl.DateTimeFormat("en-US",opts).format(d); }
  function setStatus(message, type = "") {
    refs.status.hidden = false;
    refs.status.style.display = "";
    refs.status.className =
      `availability-status ${type}`.trim();
    refs.status.textContent = message;
  }

  function hideStatus() {
    refs.status.hidden = true;
    refs.status.style.display = "none";
    refs.status.className = "availability-status";
    refs.status.textContent = "";
  }
  function buildBookingUrl(ms){ const u=new URL("https://christhebarber.setmore.com/book");u.searchParams.set("step","user-details");u.searchParams.set("products",SERVICE_ID);u.searchParams.set("type","service");u.searchParams.set("staff",STAFF_ID);u.searchParams.set("slot",ms);u.searchParams.set("staffSelected","true");return u.toString(); }
  function groupSlots(){ return state.slots.reduce((m,s)=>{(m[s.date]??=[]).push(s);return m;},{}); }
  function renderDates(){
    const grouped=groupSlots(); refs.dateStrip.replaceChildren();
    for(let i=0;i<7;i++){ const d=addDays(state.rangeStart,i), key=iso(d), count=(grouped[key]||[]).length;
      const b=document.createElement("button");b.type="button";b.className=`date-button${state.selectedDate===key?" is-selected":""}${count?"":" no-slots"}`;b.setAttribute("role","listitem");b.setAttribute("aria-pressed",String(state.selectedDate===key));
      b.innerHTML=`<span>${displayDate(d,{weekday:"short"})}</span><strong>${d.getDate()}</strong><small>${count?`${count} time${count===1?"":"s"}`:"No times"}</small>`;
      b.addEventListener("click",()=>selectDate(key));refs.dateStrip.appendChild(b);
    }
    const end=addDays(state.rangeStart,6);refs.rangeLabel.textContent=`${displayDate(state.rangeStart,{month:"short",day:"numeric"})} – ${displayDate(end,{month:"short",day:"numeric"})}`;
    refs.prev.disabled=state.rangeStart<=startOfDay(new Date());refs.next.disabled=addDays(state.rangeStart,7)>addDays(startOfDay(new Date()),MAX_FUTURE_DAYS);
  }
  function selectDate(key) {
    state.selectedDate = key;
    state.selectedSlot = null;
    refs.summary.hidden = true;
    hideStatus();
    renderDates();
    renderSlots();
  }
  function renderSlots(){
    const day=state.slots.filter(s=>s.date===state.selectedDate);refs.slotGrid.replaceChildren();
    if(!state.selectedDate){ refs.slotPanel.hidden=true;return; }
    refs.slotPanel.hidden=false;const d=new Date(`${state.selectedDate}T12:00:00`);refs.selectedDateLabel.textContent=displayDate(d,{weekday:"long",month:"long",day:"numeric"});
    if(!day.length){ setStatus("No openings are currently listed for this date. Choose another day or use Setmore directly.");refs.slotPanel.hidden=true;return; }
    hideStatus();
    for(const slot of day){ const b=document.createElement("button");b.type="button";b.className="slot-button";b.textContent=slot.timeLabel;b.addEventListener("click",()=>selectSlot(slot,b));refs.slotGrid.appendChild(b); }
  }
  function selectSlot(slot,button){ state.selectedSlot=slot;refs.slotGrid.querySelectorAll("button").forEach(b=>b.classList.remove("is-selected"));button.classList.add("is-selected");button.setAttribute("aria-pressed","true");refs.summaryDate.textContent=slot.dateLabel;refs.summaryTime.textContent=slot.timeLabel;refs.summary.hidden=false;refs.summary.scrollIntoView({behavior:"smooth",block:"nearest"}); }
  async function loadRange(){
    if(state.loading)return;state.loading=true;state.selectedDate=null;state.selectedSlot=null;refs.summary.hidden=true;refs.slotPanel.hidden=true;renderDates();setStatus("Checking Chris's latest availability…","is-loading");
    const start=iso(state.rangeStart),end=iso(addDays(state.rangeStart,6));
    try{ const c=new AbortController(),timer=setTimeout(()=>c.abort(),15000);const r=await fetch(API_ENDPOINT,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({startDate:start,endDate:end}),signal:c.signal});clearTimeout(timer);const data=await r.json();if(!r.ok)throw new Error(data.error||`HTTP_${r.status}`);state.slots=Array.isArray(data.slots)?data.slots:[];renderDates();
      const first=state.slots[0]?.date;if(first){selectDate(first);}else{setStatus("No openings were found in this seven-day period. Try the next week or check Setmore directly.");}
    }catch(e){console.error("Availability request failed",e);state.slots=[];renderDates();setStatus("Live availability is temporarily unavailable. Please check current times directly on Setmore.","is-error");}
    finally{state.loading=false;}
  }
  async function continueToSetmore(){
    if(!state.selectedSlot||state.loading)return;state.loading=true;refs.continueButton.disabled=true;refs.continueButton.textContent="Checking time…";
    try{ const r=await fetch(API_ENDPOINT,{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({startDate:state.selectedSlot.date,endDate:state.selectedSlot.date})});const data=await r.json();const active=Array.isArray(data.slots)&&data.slots.some(s=>s.timestampMs===state.selectedSlot.timestampMs);if(!r.ok||!active){state.selectedSlot=null;refs.summary.hidden=true;await loadRange();setStatus("That time is no longer available. Please choose another opening.","is-error");return;}window.location.assign(buildBookingUrl(state.selectedSlot.timestampMs));}
    catch(e){setStatus("We could not recheck that time. Please use the direct Setmore link.","is-error");}
    finally{state.loading=false;refs.continueButton.disabled=false;refs.continueButton.textContent="Continue securely on Setmore";}
  }
  refs.prev.addEventListener("click",()=>{state.rangeStart=addDays(state.rangeStart,-7);if(state.rangeStart<startOfDay(new Date()))state.rangeStart=startOfDay(new Date());loadRange();});
  refs.next.addEventListener("click",()=>{state.rangeStart=addDays(state.rangeStart,7);loadRange();});refs.continueButton.addEventListener("click",continueToSetmore);loadRange();
})();