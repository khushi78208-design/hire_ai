import { createClient } from "@supabase/supabase-js";
import { env } from "./env.js";

export const supabase = createClient(
  env.SUPABASE_URL,
  env.SUPABASE_SERVICE_ROLE_KEY,
  { auth: { persistSession: false, autoRefreshToken: false } }
);

export async function checkDatabase() {
  const { error } = await supabase.from("users").select("id").limit(1);
  if (error) throw new Error(`Supabase check failed: ${error.message}`);
  return true;
}
