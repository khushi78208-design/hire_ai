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
    // A sleeping free instance answers with Render's HTML holding page
    // rather than JSON. Name the real cause instead of the symptom.
    const waking = response.statusCode >= 500 || text.includes("<html");
    console.error(
      "[aiClient] non-JSON from",
      path,
      response.statusCode,
      text.slice(0, 300)
    );

    throw new ApiError(
      waking ? 503 : 502,
      waking
        ? "The AI service is starting up. Try again in a few seconds."
        : "AI service returned an unexpected response"
    );
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

/**
 * A sleeping free instance answers with a 502 page for the first ~50
 * seconds while it boots. Two patient retries turn that from a visible
 * failure into a merely slow response.
 */
async function callWithWake(path, options) {
  for (let attempt = 0; attempt < 3; attempt++) {
    try {
      return await call(path, options);
    } catch (err) {
      const lastTry = attempt === 2;
      if (err.statusCode !== 503 || lastTry) throw err;

      console.log(`[aiClient] instance waking, retrying ${path}`);
      await new Promise((r) => setTimeout(r, 15000));
    }
  }
}

export const aiClient = {
  // The wake ping is fire-and-forget, so it takes the plain call — a retry
  // here would just hold a connection open for nothing.
  health: () => call("/health", { method: "GET" }),

  matchResume: ({ job, application, resumeBase64, resumeFilename }) =>
    callWithWake("/analysis/match", {
      body: {
        job,
        application,
        resume_base64: resumeBase64,
        resume_filename: resumeFilename,
      },
      // LLM calls are slow; the default 30s is not enough headroom.
      timeoutMs: 90000,
    }),

  draftJob: (message) =>
    callWithWake("/agent/draft-job", { body: { message }, timeoutMs: 60000 }),

  refineJob: (message, draft) =>
    callWithWake("/agent/refine-job", {
      body: { message, draft },
      timeoutMs: 60000,
    }),

  agentAnswer: (message, context) =>
    callWithWake("/agent/answer", {
      body: { message, context },
      timeoutMs: 60000,
    }),

  // Generating ten questions takes longer than a single completion.
  generateQuestions: ({ jobTitle, skills, count, experienceMin }) =>
    callWithWake("/assessment/generate", {
      body: {
        job_title: jobTitle,
        skills,
        count,
        experience_min: experienceMin,
      },
      timeoutMs: 180000,
    }),
};