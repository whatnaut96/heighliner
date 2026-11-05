import {stellartelHandle} from '@/stellartel/handler.ts';

const stellartelPattern = new URLPattern({pathname: "/api/stellartel"});;

async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  if (stellartelPattern.test(url)) {
    
    return await stellartelHandle(req);
  }
  return new Response("unsupported route", {status: 404})
}

if (import.meta.main) {
  Deno.serve(handler);
}
