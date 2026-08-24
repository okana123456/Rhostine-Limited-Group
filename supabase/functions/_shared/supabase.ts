import { createClient } from "npm:@supabase/supabase-js@2";

export function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Supabase function environment is incomplete");
  return createClient(url, key, { auth: { persistSession: false } });
}

export async function requireBusinessAdmin(req) {
  const authorization = req.headers.get("Authorization") || "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("Authentication required");

  const admin = adminClient();
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) throw new Error("Invalid authentication session");

  const { data: staff, error: staffError } = await admin
    .from("rh_staff")
    .select("id,business_id,role,status")
    .eq("auth_user_id", authData.user.id)
    .eq("status", "active")
    .maybeSingle();
  if (staffError || !staff || staff.role !== "admin") throw new Error("Administrator access required");

  return { admin, user: authData.user, staff };
}
