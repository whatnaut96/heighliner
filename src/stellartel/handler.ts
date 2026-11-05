import {  StatusJournal, StatusPayload, } from './stellartel.types.ts';


const CLICKHOUSE_URL = Deno.env.get("CLICKHOUSE_URL");


export async function stellartelHandle(req: Request): Promise<Response> {
  const data = await req.json();
  if (data.event === "Status") return statusHandle(data);
  return new Response("unsupported journal", {
    status: 400,
  });
}

export async function statusHandle(status: StatusJournal): Promise<Response> {
  const payload: StatusPayload = {
    cargo: status.Cargo,
    mass_locked: (status.Flags >> 16) & 1,
    low_fuel: (status.Flags >> 19) & 1,
    overheating: (status.Flags >> 20) & 1,
    in_danger: (status.Flags >> 22) & 1,
    being_interdicted: (status.Flags >> 23) & 1,
    legal_state: status.LegalState,
  };

  const query = "INSERT INTO stellartel.status_metrics FORMAT JSONEachRow";
  const url = `${CLICKHOUSE_URL}?query=${encodeURIComponent(query)}`
  
  return  await fetch(url, {
    method: "POST",
    body: JSON.stringify(payload)
  });
}
