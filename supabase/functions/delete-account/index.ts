// =====================================================================
// delete-account - full self-serve account deletion (App Store 5.1.1(v);
// Fence 5: photos are private, user-deletable — deleting the account is
// the strongest form of that promise).
//
// The caller's JWT identifies the account; nothing in the body is trusted.
// Order matters: storage objects do NOT cascade from auth.users, so the
// user's photo folder is emptied first, then the auth user is deleted —
// public.users references auth.users ON DELETE CASCADE and every user
// table cascades from public.users, so one delete wipes the rest.
// =====================================================================

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const PHOTO_BUCKET = "meal-photos";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "content-type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "auth required" }, 401);

  // Resolve the caller from their own token — the only account this
  // function can ever delete is the one that asked.
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  const uid = userData?.user?.id;
  if (userError || !uid) return json({ error: "invalid session" }, 401);

  const service = createClient(supabaseUrl, serviceKey);

  // 1) Empty the user's photo folder (layout: meal-photos/<uid>/<uuid>.jpg).
  //    Paginate defensively; a heavy logger can exceed one page.
  try {
    for (let page = 0; page < 50; page++) {
      const { data: objects, error: listError } = await service.storage
        .from(PHOTO_BUCKET)
        .list(uid, { limit: 100 });
      if (listError) throw new Error(`storage list failed: ${listError.message}`);
      if (!objects || objects.length === 0) break;
      const paths = objects.map((o) => `${uid}/${o.name}`);
      const { error: removeError } = await service.storage.from(PHOTO_BUCKET).remove(paths);
      if (removeError) throw new Error(`storage remove failed: ${removeError.message}`);
      if (objects.length < 100) break;
    }
  } catch (err) {
    // Photos failing to delete must not strand the account deletion — the
    // auth delete below is the binding action; orphaned objects in a
    // private bucket are unreachable by anyone and can be swept later.
    console.error(`delete-account: photo cleanup for ${uid}: ${err}`);
  }

  // 2) Delete the auth user; public.users + every user table cascade.
  const { error: deleteError } = await service.auth.admin.deleteUser(uid);
  if (deleteError) {
    return json({ error: `account deletion failed: ${deleteError.message}` }, 500);
  }

  return json({ ok: true });
});
