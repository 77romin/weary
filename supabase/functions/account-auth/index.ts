import { createClient } from "npm:@supabase/supabase-js@2";

const jsonHeaders = {
  "Content-Type": "application/json; charset=utf-8",
  "Cache-Control": "no-store",
  "X-Content-Type-Options": "nosniff",
  "Referrer-Policy": "no-referrer",
};

const encoder = new TextEncoder();
const maxRequestBytes = 4_096;

type RequestBody = {
  action?: "sign_in" | "availability";
  identifier?: string;
  password?: string;
  email?: string;
  handle?: string;
  nickname?: string;
};

function environmentKey(jsonName: string): string {
  const dictionary = Deno.env.get(jsonName);
  if (dictionary) {
    const parsed = JSON.parse(dictionary) as Record<string, string>;
    if (parsed.default) return parsed.default;
  }
  throw new Error(`Missing ${jsonName}`);
}

function response(
  body: Record<string, unknown>,
  status = 200,
  additionalHeaders: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...jsonHeaders, ...additionalHeaders },
  });
}

function clientAddress(request: Request): string {
  return request.headers.get("cf-connecting-ip")?.trim()
    || request.headers.get("x-real-ip")?.trim()
    || request.headers.get("x-forwarded-for")?.split(",")[0]?.trim()
    || "unknown";
}

async function subjectHash(secret: string, value: string): Promise<string> {
  const input = encoder.encode(`${secret}:${value}`);
  const digest = await crypto.subtle.digest("SHA-256", input);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function consumeRateLimit(
  admin: ReturnType<typeof createClient>,
  scope: string,
  subject: string,
  limit: number,
  windowSeconds: number,
  hashSecret: string,
): Promise<boolean> {
  const { data, error } = await admin.rpc("consume_account_auth_rate_limit", {
    p_scope: scope,
    p_subject_hash: await subjectHash(hashSecret, subject),
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error) throw error;
  return data === true;
}

async function waitForMinimumDuration(startedAt: number, minimumMilliseconds: number) {
  const remaining = minimumMilliseconds - (Date.now() - startedAt);
  if (remaining > 0) await new Promise((resolve) => setTimeout(resolve, remaining));
}

Deno.serve(async (request) => {
  const startedAt = Date.now();
  if (request.method !== "POST") {
    return response({ error: "method_not_allowed" }, 405);
  }

  const contentLength = Number(request.headers.get("content-length") ?? "0");
  if (Number.isFinite(contentLength) && contentLength > maxRequestBytes) {
    return response({ error: "invalid_input" }, 413);
  }

  try {
    let body: RequestBody;
    try {
      body = await request.json() as RequestBody;
    } catch {
      return response({ error: "invalid_input" }, 400);
    }
    const url = Deno.env.get("SUPABASE_URL");
    if (!url) throw new Error("Missing SUPABASE_URL");

    const publishableKey = environmentKey("SUPABASE_PUBLISHABLE_KEYS");
    const secretKey = environmentKey("SUPABASE_SECRET_KEYS");
    const admin = createClient(url, secretKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const address = clientAddress(request);

    if (body.action === "availability") {
      const email = body.email?.trim().toLowerCase() ?? "";
      const handle = body.handle?.trim().toLowerCase() ?? "";
      const nickname = body.nickname?.trim() ?? "";
      if (
        !/^\S+@\S+\.\S+$/.test(email) || email.length > 254
        || !/^[a-z0-9._]{3,20}$/.test(handle)
        || nickname.length < 2 || nickname.length > 30
      ) {
        return response({ error: "invalid_input" }, 400);
      }

      const ipAllowed = await consumeRateLimit(
        admin, "availability_ip", address, 15, 600, secretKey,
      );
      const requestAllowed = await consumeRateLimit(
        admin, "availability_request", `${address}:${email}:${handle}:${nickname}`, 5, 600, secretKey,
      );
      if (!ipAllowed || !requestAllowed) {
        await waitForMinimumDuration(startedAt, 350);
        return response({ error: "rate_limited" }, 429, { "Retry-After": "600" });
      }

      const { data, error } = await admin.rpc("check_account_availability", {
        p_email: email,
        p_handle: handle,
        p_nickname: nickname,
      });
      if (error) throw error;
      await waitForMinimumDuration(startedAt, 350);
      return response(data as Record<string, boolean>);
    }

    if (body.action === "sign_in") {
      const identifier = body.identifier?.trim().toLowerCase() ?? "";
      const password = body.password ?? "";
      if (!identifier || identifier.length > 254 || !password || password.length > 256) {
        return response({ error: "invalid_credentials" }, 400);
      }

      const ipAllowed = await consumeRateLimit(
        admin, "sign_in_ip", address, 20, 600, secretKey,
      );
      const identifierAllowed = await consumeRateLimit(
        admin, "sign_in_identifier", identifier, 8, 900, secretKey,
      );
      if (!ipAllowed || !identifierAllowed) {
        await waitForMinimumDuration(startedAt, 500);
        return response({ error: "invalid_credentials" }, 429, { "Retry-After": "900" });
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
          await waitForMinimumDuration(startedAt, 500);
          return response({ error: "invalid_credentials" }, 400);
        }
        email = data;
      }

      const auth = createClient(url, publishableKey, {
        auth: { persistSession: false, autoRefreshToken: false },
      });
      const { data, error } = await auth.auth.signInWithPassword({ email, password });
      if (error || !data.session) {
        await waitForMinimumDuration(startedAt, 500);
        return response({ error: "invalid_credentials" }, 400);
      }

      await waitForMinimumDuration(startedAt, 500);
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
