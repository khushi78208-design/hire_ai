import { Router } from "express";
import { z } from "zod";

import { supabase } from "../config/supabase.js";
import { asyncHandler } from "../middleware/errorHandler.js";
import { requireAuth, requireRole } from "../middleware/auth.js";
import { ApiError } from "../utils/ApiError.js";
import { aiClient } from "../services/aiClient.js";

const router = Router();

async function loadOwnedJob(jobId, user) {
    const { data: job } = await supabase
        .from("jobs")
        .select("*")
        .eq("id", jobId)
        .maybeSingle();

    if (!job) throw ApiError.notFound("Job not found");
    if (job.created_by !== user.id && user.role !== "admin") {
        throw ApiError.forbidden("Not your job posting");
    }
    return job;
}

// ------------------------------------------------------------
// GET /api/v1/assessments/mine   (candidate)
// Must sit above /:id style routes.
// ------------------------------------------------------------
router.get(
    "/mine",
    requireAuth,
    requireRole("candidate"),
    asyncHandler(async (req, res) => {
        // Deliberately excludes questions and correct answers — a candidate
        // must never be able to read the paper before sitting it.
        const { data, error } = await supabase
            .from("assessment_attempts")
            .select(
                "id, application_id, status, score, total, submitted_at, " +
                "assessments:assessment_id (id, title, duration_min, instructions, " +
                "jobs:job_id (title))"
            )
            .eq("candidate_id", req.user.id)
            .order("created_at", { ascending: false });

        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { attempts: data ?? [] } });
    })
);

// ------------------------------------------------------------
// POST /api/v1/assessments/generate   (HR)
// Questions come back for review. Nothing is stored yet.
// ------------------------------------------------------------
router.post(
    "/generate",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const body = z
            .object({
                job_id: z.string().uuid(),
                count: z.coerce.number().int().min(3).max(25).default(10),
            })
            .parse(req.body);

        const job = await loadOwnedJob(body.job_id, req.user);

        const result = await aiClient.generateQuestions({
            jobTitle: job.title,
            skills: job.skills ?? [],
            count: body.count,
            experienceMin: job.experience_min ?? 0,
        });

        const questions = result?.data?.questions;
        if (!questions?.length) {
            throw ApiError.internal("No questions were generated");
        }

        res.json({ success: true, data: { questions } });
    })
);

const saveSchema = z.object({
    job_id: z.string().uuid(),
    title: z.string().min(3).max(200),
    instructions: z.string().max(2000).optional(),
    duration_min: z.coerce.number().int().min(5).max(180).default(20),
    questions: z
        .array(
            z.object({
                id: z.string(),
                question: z.string().min(3),
                options: z.array(z.string()).length(4),
                correct: z.coerce.number().int().min(0).max(3),
                topic: z.string().optional(),
                explanation: z.string().optional(),
            })
        )
        .min(1),
});

// ------------------------------------------------------------
// POST /api/v1/assessments   (HR)
// Saves the reviewed assessment and invites every shortlisted candidate.
// ------------------------------------------------------------
router.post(
    "/",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const body = saveSchema.parse(req.body);
        await loadOwnedJob(body.job_id, req.user);

        const { data: shortlisted } = await supabase
            .from("applications")
            .select("id, candidate_id")
            .eq("job_id", body.job_id)
            .eq("status", "shortlisted");

        if (!shortlisted?.length) {
            throw ApiError.badRequest(
                "No shortlisted candidates for this vacancy yet"
            );
        }

        const { data: assessment, error } = await supabase
            .from("assessments")
            .insert({
                job_id: body.job_id,
                created_by: req.user.id,
                title: body.title,
                instructions: body.instructions ?? null,
                duration_min: body.duration_min,
                questions: body.questions,
                status: "sent",
            })
            .select()
            .single();

        if (error) throw ApiError.internal(error.message);

        // One invite per shortlisted candidate. The unique index makes a repeat
        // send harmless rather than duplicating attempts.
        const { error: attemptError } = await supabase
            .from("assessment_attempts")
            .upsert(
                shortlisted.map((a) => ({
                    assessment_id: assessment.id,
                    application_id: a.id,
                    candidate_id: a.candidate_id,
                    status: "pending",
                })),
                { onConflict: "assessment_id,candidate_id", ignoreDuplicates: true }
            );

        if (attemptError) throw ApiError.internal(attemptError.message);

        await supabase.from("audit_logs").insert({
            actor_id: req.user.id,
            action: "assessment_sent",
            entity_type: "assessment",
            entity_id: assessment.id,
            metadata: {
                job_id: body.job_id,
                candidates: shortlisted.length,
                questions: body.questions.length,
            },
        });

        res.status(201).json({
            success: true,
            data: { assessment, sentTo: shortlisted.length },
        });
    })
);

// ------------------------------------------------------------
// GET /api/v1/assessments/results/:jobId   (HR)
// ------------------------------------------------------------
router.get(
    "/results/:jobId",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        await loadOwnedJob(req.params.jobId, req.user);

        const { data: assessments } = await supabase
            .from("assessments")
            .select("id")
            .eq("job_id", req.params.jobId);

        const ids = (assessments ?? []).map((a) => a.id);
        if (!ids.length) {
            return res.json({ success: true, data: { attempts: [] } });
        }

        const { data, error } = await supabase
            .from("assessment_attempts")
            .select("*")
            .in("assessment_id", ids);

        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { attempts: data ?? [] } });
    })
);

// ------------------------------------------------------------
// POST /api/v1/assessments/attempts/:id/start   (candidate)
// Hands over the questions, minus the answer key.
// ------------------------------------------------------------
router.post(
    "/attempts/:id/start",
    requireAuth,
    requireRole("candidate"),
    asyncHandler(async (req, res) => {
        const { data: attempt } = await supabase
            .from("assessment_attempts")
            .select("*, assessments:assessment_id (*)")
            .eq("id", req.params.id)
            .maybeSingle();

        if (!attempt) throw ApiError.notFound("Assessment not found");
        if (attempt.candidate_id !== req.user.id) {
            throw ApiError.forbidden("Not your assessment");
        }
        if (attempt.status === "submitted") {
            throw ApiError.badRequest("You have already submitted this assessment");
        }

        const assessment = attempt.assessments;

        // The clock starts on first open and is never extended — reopening a
        // half-finished attempt must not buy more time.
        const startedAt = attempt.started_at ?? new Date().toISOString();

        if (!attempt.started_at) {
            await supabase
                .from("assessment_attempts")
                .update({ status: "in_progress", started_at: startedAt })
                .eq("id", attempt.id);
        }

        const questions = (assessment.questions ?? []).map((q) => ({
            id: q.id,
            question: q.question,
            options: q.options,
        }));

        res.json({
            success: true,
            data: {
                attemptId: attempt.id,
                title: assessment.title,
                instructions: assessment.instructions,
                durationMin: assessment.duration_min,
                startedAt,
                questions,
            },
        });
    })
);

// ------------------------------------------------------------
// POST /api/v1/assessments/attempts/:id/submit   (candidate)
// ------------------------------------------------------------
router.post(
    "/attempts/:id/submit",
    requireAuth,
    requireRole("candidate"),
    asyncHandler(async (req, res) => {
        const body = z
            .object({
                answers: z.record(z.coerce.number().int().min(0).max(3)),
                tab_switches: z.coerce.number().int().min(0).default(0),
            })
            .parse(req.body);

        const { data: attempt } = await supabase
            .from("assessment_attempts")
            .select("*, assessments:assessment_id (questions)")
            .eq("id", req.params.id)
            .maybeSingle();

        if (!attempt) throw ApiError.notFound("Assessment not found");
        if (attempt.candidate_id !== req.user.id) {
            throw ApiError.forbidden("Not your assessment");
        }
        if (attempt.status === "submitted") {
            throw ApiError.conflict("Already submitted");
        }

        const questions = attempt.assessments?.questions ?? [];

        // Scoring happens here, never on the client — the answer key never
        // leaves the server.
        let score = 0;
        for (const q of questions) {
            if (body.answers[q.id] === q.correct) score += 1;
        }

        const { data, error } = await supabase
            .from("assessment_attempts")
            .update({
                status: "submitted",
                submitted_at: new Date().toISOString(),
                answers: body.answers,
                score,
                total: questions.length,
                tab_switches: body.tab_switches,
            })
            .eq("id", attempt.id)
            .select()
            .single();

        if (error) throw ApiError.internal(error.message);

        res.json({
            success: true,
            data: { score: data.score, total: data.total },
        });
    })
);

export default router;