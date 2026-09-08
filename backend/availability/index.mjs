const ENDPOINT = "https://cbphandlers.setmore.com/handlers/graphql?operation=GetSlots";
const COMPANY_ID = "eb581df2-9fdf-495f-85d0-dbc815793aed";
const SERVICE_ID = "s5fcf71d64953606227d3e7740166772d785cdf32";
const STAFF_ID = "r99f585095ff06863ec494873de9023fdf26d353f";
const TIME_ZONE = "America/New_York";
const DURATION_MINS = 30;
const MAX_RANGE_DAYS = 7;
const MAX_FUTURE_DAYS = 30;
const REQUEST_TIMEOUT_MS = 12000;
const ALLOWED_ORIGIN = process.env.ALLOWED_ORIGIN || "https://christhebarber.denduluru.com";

const QUERY = `query GetSlots($companyId: ID!, $durationMins: Int!, $endDateISO: String!, $serviceIds: [ID!]!, $staffId: ID, $startDateISO: String!, $timeZone: String!) {
  slots(where: {companyId: $companyId, durationMins: $durationMins, endDateISO: $endDateISO, serviceIds: $serviceIds, staffId: $staffId, startDateISO: $startDateISO, timeZone: $timeZone}) {
    displayDateTime
    ms
    staffId
    duration
    isVideoEnabled
    __typename
  }
}`;

function corsHeaders(origin) {
  const allowed = origin === ALLOWED_ORIGIN ? origin : ALLOWED_ORIGIN;
  return {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
    "x-content-type-options": "nosniff",
    "access-control-allow-origin": allowed,
    "vary": "origin"
  };
}
function reply(statusCode, body, origin) {
  return { statusCode, headers: corsHeaders(origin), body: JSON.stringify(body) };
}
function parseBody(event) {
  if (!event?.body) return {};
  if (typeof event.body === "object") return event.body;
  try { return JSON.parse(event.body); } catch { throw new Error("INVALID_JSON"); }
}
function parseDateOnly(value, name) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw new Error(`${name}_MUST_BE_YYYY_MM_DD`);
  const date = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(date.getTime()) || date.toISOString().slice(0,10) !== value) throw new Error(`${name}_IS_INVALID`);
  return date;
}
function dayStart(d) {
  return new Date(
    Date.UTC(
      d.getUTCFullYear(),
      d.getUTCMonth(),
      d.getUTCDate()
    )
  );
}

function todayInBookingTimezone() {
  const parts = new Intl.DateTimeFormat("en-US", {
    timeZone: TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit"
  }).formatToParts(new Date());

  const value = type =>
    parts.find(part => part.type === type)?.value;

  return parseDateOnly(
    `${value("year")}-${value("month")}-${value("day")}`,
    "TODAY"
  );
}

function daysBetween(a, b) {
  return Math.round(
    (dayStart(b) - dayStart(a)) / 86400000
  );
}

function buildRange(startText,endText) {
  const start=parseDateOnly(startText,"START_DATE");
  const end=parseDateOnly(endText,"END_DATE");
  const today=todayInBookingTimezone();
  const range=daysBetween(start,end);
  if (start<today) throw new Error("START_DATE_IS_IN_THE_PAST");
  if (range<0) throw new Error("END_DATE_PRECEDES_START_DATE");
  if (range>MAX_RANGE_DAYS) throw new Error("DATE_RANGE_EXCEEDS_7_DAYS");
  if (daysBetween(today,end)>MAX_FUTURE_DAYS) throw new Error("END_DATE_EXCEEDS_30_DAY_LIMIT");
  return {
    startISO:new Date(start.getTime()-5*3600000).toISOString(),
    endISO:new Date(end.getTime()+29*3600000-1).toISOString()
  };
}
function localParts(ms) {
  const d=new Date(Number(ms));
  const parts=new Intl.DateTimeFormat("en-US",{timeZone:TIME_ZONE,year:"numeric",month:"2-digit",day:"2-digit"}).formatToParts(d);
  const get=t=>parts.find(p=>p.type===t)?.value;
  const date=`${get("year")}-${get("month")}-${get("day")}`;
  return {
    date,
    dateLabel:new Intl.DateTimeFormat("en-US",{timeZone:TIME_ZONE,weekday:"long",month:"long",day:"numeric",year:"numeric"}).format(d),
    timeLabel:new Intl.DateTimeFormat("en-US",{timeZone:TIME_ZONE,hour:"numeric",minute:"2-digit",hour12:true}).format(d)
  };
}
function normalize(raw,start,end) {
  const found=new Map();
  for (const x of Array.isArray(raw)?raw:[]) {
    const ms=String(x?.ms??"");
    if (!/^\d{13}$/.test(ms)) continue;
    const p=localParts(ms);
    if (p.date<start || p.date>end) continue;
    found.set(ms,{timestampMs:ms,date:p.date,dateLabel:p.dateLabel,timeLabel:p.timeLabel});
  }
  return [...found.values()].sort((a,b)=>Number(a.timestampMs)-Number(b.timestampMs));
}
async function fetchSlots(startISO,endISO) {
  const controller=new AbortController();
  const timer=setTimeout(()=>controller.abort(),REQUEST_TIMEOUT_MS);
  try {
    const r=await fetch(ENDPOINT,{
      method:"POST",
      headers:{accept:"application/json","content-type":"application/json","user-agent":"ChrisTheBarber-Availability/1.0"},
      body:JSON.stringify({operationName:"GetSlots",variables:{companyId:COMPANY_ID,durationMins:DURATION_MINS,endDateISO:endISO,serviceIds:[SERVICE_ID],staffId:STAFF_ID,startDateISO:startISO,timeZone:TIME_ZONE},query:QUERY}),
      redirect:"error",signal:controller.signal
    });
    const text=await r.text();
    let data; try { data=JSON.parse(text); } catch { throw new Error(`UPSTREAM_NON_JSON_${r.status}`); }
    if (!r.ok) throw new Error(`UPSTREAM_HTTP_${r.status}`);
    if (Array.isArray(data?.errors)&&data.errors.length) throw new Error("UPSTREAM_GRAPHQL_ERROR");
    if (!Array.isArray(data?.data?.slots)) throw new Error("UPSTREAM_RESPONSE_CHANGED");
    return data.data.slots;
  } finally { clearTimeout(timer); }
}
export const handler=async event=>{
  const origin=event?.headers?.origin || event?.headers?.Origin || "";
  const requestId=event?.requestContext?.requestId || "unknown";
  if (origin && origin!==ALLOWED_ORIGIN) return reply(403,{error:"ORIGIN_NOT_ALLOWED"},origin);
  try {
    const body=parseBody(event);
    const startDate=body.startDate;
    const endDate=body.endDate || startDate;
    const range=buildRange(startDate,endDate);
    const slots=normalize(await fetchSlots(range.startISO,range.endISO),startDate,endDate);
    console.log(JSON.stringify({event:"availability_ok",requestId,slotCount:slots.length}));
    return reply(200,{timezone:TIME_ZONE,durationMinutes:DURATION_MINS,startDate,endDate,slotCount:slots.length,slots,fallbackBookingUrl:`https://christhebarber.setmore.com/book?step=time-slot&products=${SERVICE_ID}&type=service&staff=${STAFF_ID}&staffSelected=true`},origin);
  } catch(e) {
    const m=e?.name==="AbortError"?"UPSTREAM_TIMEOUT":String(e?.message||"UNKNOWN_ERROR");
    console.error(JSON.stringify({event:"availability_failed",requestId,error:m}));
    const client=/^(INVALID_|START_|END_|DATE_)/.test(m);
    return reply(client?400:502,{error:client?m:"AVAILABILITY_TEMPORARILY_UNAVAILABLE",fallbackBookingUrl:`https://christhebarber.setmore.com/book?step=time-slot&products=${SERVICE_ID}&type=service&staff=${STAFF_ID}&staffSelected=true`},origin);
  }
};
