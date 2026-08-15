import { request } from "undici";
import { env } from "../config/env.js";
import { ApiError } from "../utils/ApiError.js";

async function call(path, { method = "POST", body } = {}) {
  const url = `${env.AI_SERVICE_URL}${path}`;

  let response;
  try {
    response = await request(url, {
      method,
      headers: {
        "content-type": "application/json",
        "x-internal-secret": env.AI_SERVICE_SECRET,
      },
      body: body ? JSON.stringify(body) : undefined,
      headersTimeout: env.AI_SERVICE_TIMEOUT_MS,
      bodyTimeout: env.AI_SERVICE_TIMEOUT_MS,
    });
  } catch (err) {
    throw new ApiError(503, "AI service unavailable", { cause: err.message });
  }

  const text = await response.body.text();
  let payload;
  try {
    payload = text ? JSON.parse(text) : {};
  } catch {
    throw new ApiError(502, "AI service returned a non-JSON response");
  }

  if (response.statusCode >= 400) {
    throw new ApiError(
      response.statusCode === 422 ? 400 : 502,
      payload?.detail?.message || payload?.detail || "AI service error"
    );
  }

  return payload;
}

export const aiClient = {
  health: () => call("/health", { method: "GET" }),
};
