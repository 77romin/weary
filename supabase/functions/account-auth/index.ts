import { createClient } from "npm:@supabase/supabase-js@2";

const jsonHeaders = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
};

type RequestBody = {
  action?: "sign_in" | "availability";
  identifier?: string;
  password?: string;
  email?: string;
  handle?: string;
  nickname?: string;
};

function environmentKey(jsonName: string, legacyName: string): string {
  const dictionary = Deno.env.get(jsonName);
  if (dictionary) {
    const parsed = JSON.parse(dictionary) as Record<string, string>;
    if (parsed.default) return parsed.default;
  }
  const legacy = Deno.env.get(legacyName);
  if (!legacy) throw new Error(`Missing ${jsonName}`);
  return legacy;
}

function response(body: Record<string, unknown>, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return response({ error: "method_not_allowed" }, 405);
  }

  try {
    const body = await request.json() as RequestBody;
    const url = Deno.env.get("SUPABASE_URL");
    if (!url) throw new Error("Missing SUPABASE_URL");

    const publishableKey = environmentKey("SUPABASE_PUBLISHABLE_KEYS", "SUPABASE_ANON_KEY");
    const secretKey = environmentKey("SUPABASE_SECRET_KEYS", "SUPABASE_SERVICE_ROLE_KEY");
    const admin = createClient(url, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    if (body.action === "availability") {
      const email = body.email?.trim().toLowerCase() ?? "";
      const handle = body.handle?.trim().toLowerCase() ?? "";
      const nickname = body.nickname?.trim() ?? "";
      if (!email || !handle || !nickname) {
        return response({ error: "invalid_input" }, 400);
      }

      const { data, error } = await admin.rpc("check_account_availability", {
        p_email: email,
        p_handle: handle,
        p_nickname: nickname,
      });
      if (error) throw error;
      return response(data as Record<string, boolean>);
    }

    if (body.action === "sign_in") {
      const identifier = body.identifier?.trim().toLowerCase() ?? "";
      const password = body.password ?? "";
      if (!identifier || !password) {
        return response({ error: "invalid_credentials" }, 400);
      }

      let email = identifier;
      if (!identifier.includes("@")) {
        if (!/^[a-z0-9._]{3,20}$/.test(identifier)) {
          return response({ error: "invalid_credentials" }, 400);
        }
        const { data, error } = await admin.rpc("login_email_for_handle", {
          p_handle: identifier,
        });
        if (error) throw error;
        if (typeof data !== "string" || !data) {
          return response({ error: "invalid_credentials" }, 400);
        }
        email = data;
      }

      const auth = createClient(url, publishableKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await auth.auth.signInWithPassword({ email, password });
      if (error || !data.session) {
        return response({ error: "invalid_credentials" }, 400);
      }

      return response({
        accessToken: data.session.access_token,
        refreshToken: data.session.refresh_token,
      });
    }

    return response({ error: "invalid_action" }, 400);
  } catch (error) {
    console.error(error);
    return response({ error: "server_error" }, 500);
  }
});
