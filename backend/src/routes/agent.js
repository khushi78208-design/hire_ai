import { Router } from "express";
import { z } from "zod";

import { supabase } from "../config/supabase.js";
import { asyncHandler } from "../middleware/errorHandler.js";
import { requireAuth, requireRole } from "../middleware/auth.js";
import { ApiError } from "../utils/ApiError.js";
import { aiClient } from "../services/aiClient.js";

const router = Router();

const messageSchema = z.object({
    message: z.string().min(1, "Say something first").max(2000),
    // Present when the recruiter is editing a draft that is already on screen.
    draft: z.record(z.any()).optional(),
});

/**
 * Everything the assistant is allowed to see: this recruiter's own jobs,
 * their applications and the AI scores. Nothing from any other recruiter
 * ever enters the prompt, so it cannot leak what it never received.
 */
async function buildContext(userId) {
    const { data: jobs } = await supabase
        .from("jobs")
        .select("id, title, location, status, skills, experience_min, openings")
        .eq("created_by", userId);

    const jobIds = (jobs ?? []).map((j) => j.id);
    if (jobIds.length === 0) return { jobs: [], candidates: [] };

    const { data: applications } = await supabase
        .from("applications")
        .select(
            "id, job_id, full_name, qualification, experience_years, current_city, status"
        )
        .in("job_id", jobIds);

    const { data: evaluations } = await supabase
        .from("ai_evaluations")
        .select(
            "application_id, overall_score, recommendation, matched_skills, missing_skills, summary"
        )
        .in("job_id", jobIds);

    const scores = new Map((evaluations ?? []).map((e) => [e.application_id, e]));
    const jobTitles = new Map((jobs ?? []).map((j) => [j.id, j.title]));

    const candidates = (applications ?? []).map((a) => {
        const evaluation = scores.get(a.id);
        return {
            name: a.full_name,
            job: jobTitles.get(a.job_id),
            qualification: a.qualification,
            experience_years: a.experience_years,
            city: a.current_city,
            status: a.status,
            ai_score: evaluation?.overall_score ?? null,
            recommendation: evaluation?.recommendation ?? null,
            matched_skills: evaluation?.matched_skills ?? [],
            missing_skills: evaluation?.missing_skills ?? [],
            ai_summary: evaluation?.summary ?? null,
        };
    });

    return { jobs, candidates };
}

/**
 * Draft requests read like instructions; everything else is a question.
 * A wrong guess here is cheap — the recruiter just gets the other kind
 * of reply and can rephrase.
 */
function looksLikeDraftRequest(text) {
    const t = text.toLowerCase();
    const verbs = ["create", "make", "post", "add", "draft", "open", "hire", "need", "banao", "chahiye"];
    const nouns = ["vacancy", "job", "position", "role", "opening", "posting", "developer", "engineer", "designer", "manager", "analyst", "executive"];

    return verbs.some((v) => t.includes(v)) && nouns.some((n) => t.includes(n));
}

// ------------------------------------------------------------
// POST /api/v1/agent/chat   (HR only)
// ------------------------------------------------------------
router.post(
    "/chat",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const { message, draft: currentDraft } = messageSchema.parse(req.body);

        // A draft on screen means the next message is almost always an edit to
        // it — routing it anywhere else would silently discard their work.
        if (currentDraft) {
            const result = await aiClient.refineJob(message, currentDraft);
            const draft = result?.data;
            if (!draft) throw ApiError.internal("The assistant returned nothing");

            return res.json({ success: true, data: { type: "draft", draft } });
        }

        if (looksLikeDraftRequest(message)) {
            const result = await aiClient.draftJob(message);
            const draft = result?.data;

            if (!draft) throw ApiError.internal("The assistant returned nothing");

            // A draft is a proposal, not a row. Nothing is written until the
            // recruiter presses the button in the preview card.
            return res.json({
                success: true,
                data: { type: "draft", draft },
            });
        }

        const context = await buildContext(req.user.id);
        const result = await aiClient.agentAnswer(message, context);

        res.json({
            success: true,
            data: { type: "answer", answer: result?.data?.answer ?? "" },
        });
    })
);

export default router;