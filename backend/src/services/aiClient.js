import { request } from "undici";
import { env } from "../config/env.js";
import { ApiError } from "../utils/ApiError.js";

/**
 * The only place in the codebase that talks to the FastAPI AI service.
 * Every call carries the shared internal secret; the AI service rejects
 * anything without it. Flutter never calls the AI service directly.
 */
async function call(path, { method = "POST", body, timeoutMs } = {}) {
  const url = `${env.AI_SERVICE_URL}${path}`;
  const timeout = timeoutMs || env.AI_SERVICE_TIMEOUT_MS;

  let response;
  try {
    response = await request(url, {
      method,
      headers: {
        "content-type": "application/json",
        "x-internal-secret": env.AI_SERVICE_SECRET,
      },
      body: body ? JSON.stringify(body) : undefined,
      headersTimeout: timeout,
      bodyTimeout: timeout,
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
    const detail = payload?.detail;
    const message =
      (typeof detail === "object" ? detail?.message : detail) ||
      "AI service error";

    // 422 means the input was unusable (unreadable resume) — that is the
    // user's problem to fix, not a server fault.
    throw new ApiError(response.statusCode === 422 ? 400 : 502, message);
  }

  return payload;
}

export const aiClient = {
  health: () => call("/health", { method: "GET" }),

  matchResume: ({ job, application, resumeBase64, resumeFilename }) =>
    call("/analysis/match", {
      body: {
        job,
        application,
        resume_base64: resumeBase64,
        resume_filename: resumeFilename,
      },
      // LLM calls are slow; the default 30s is not enough headroom.
      timeoutMs: 90000,
    }),
  refineJob: (message, draft) =>
    call("/agent/refine-job", { body: { message, draft }, timeoutMs: 60000 }),

  draftJob: (message) =>
    call("/agent/draft-job", { body: { message }, timeoutMs: 60000 }),

  agentAnswer: (message, context) =>
    call("/agent/answer", { body: { message, context }, timeoutMs: 60000 }),

  generateQuestions: ({ jobTitle, skills, count, experienceMin }) =>
    call("/assessment/generate", {
      body: {
        job_title: jobTitle,
        skills,
        count,
        experience_min: experienceMin,
      },
      timeoutMs: 180000, // 3 minutes — plenty of time for LLM
    }),
};