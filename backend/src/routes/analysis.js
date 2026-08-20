import { Router } from "express";

import { supabase } from "../config/supabase.js";
import { asyncHandler } from "../middleware/errorHandler.js";
import { requireAuth, requireRole } from "../middleware/auth.js";
import { ApiError } from "../utils/ApiError.js";
import { aiClient } from "../services/aiClient.js";

const router = Router();

/** HR may only touch applications that belong to their own job postings. */
async function loadOwnedApplication(applicationId, user) {
    const { data: application } = await supabase
        .from("applications")
        .select("*, jobs:job_id (*)")
        .eq("id", applicationId)
        .maybeSingle();

    if (!application) throw ApiError.notFound("Application not found");

    const job = application.jobs;
    if (!job) throw ApiError.notFound("Job not found");

    if (job.created_by !== user.id && user.role !== "admin") {
        throw ApiError.forbidden("Not your job posting");
    }

    return { application, job };
}

// ------------------------------------------------------------
// POST /api/v1/analysis/applications/:id
// Runs the AI screening for one application.
// ------------------------------------------------------------
router.post(
    "/applications/:id",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const { application, job } = await loadOwnedApplication(
            req.params.id,
            req.user
        );

        if (!application.resume_path) {
            throw ApiError.badRequest("This application has no resume attached");
        }

        const { data: file, error: dlError } = await supabase.storage
            .from("resumes")
            .download(application.resume_path);

        if (dlError || !file) {
            throw ApiError.internal("Could not read the resume file");
        }

        const buffer = Buffer.from(await file.arrayBuffer());

        const result = await aiClient.matchResume({
            job,
            application,
            resumeBase64: buffer.toString("base64"),
            resumeFilename: application.resume_filename || "resume.pdf",
        });

        const data = result?.data;
        if (!data) throw ApiError.internal("AI service returned no analysis");

        // Upsert: re-running an analysis replaces the previous one but never
        // touches the recruiter's own decision on the application.
        const { data: saved, error } = await supabase
            .from("ai_evaluations")
            .upsert(
                {
                    application_id: application.id,
                    job_id: job.id,
                    overall_score: data.overall_score,
                    skill_score: data.skill_score,
                    experience_score: data.experience_score,
                    education_score: data.education_score,
                    project_score: data.project_score,
                    recommendation: data.recommendation,
                    matched_skills: data.matched_skills,
                    missing_skills: data.missing_skills,
                    strengths: data.strengths,
                    concerns: data.concerns,
                    summary: data.summary,
                    location_note: data.location_note,
                    model: data.model,
                    raw_response: data,
                },
                { onConflict: "application_id" }
            )
            .select()
            .single();

        if (error) throw ApiError.internal(`Could not save analysis: ${error.message}`);

        await supabase.from("audit_logs").insert({
            actor_id: req.user.id,
            action: "ai_analysis_run",
            entity_type: "application",
            entity_id: application.id,
            metadata: { score: data.overall_score, model: data.model },
        });

        res.json({ success: true, data: { evaluation: saved } });
    })
);

// ------------------------------------------------------------
// GET /api/v1/analysis/jobs/:jobId
// Every stored evaluation for one job, for the applicants list.
// ------------------------------------------------------------
router.get(
    "/jobs/:jobId",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const { data: job } = await supabase
            .from("jobs")
            .select("created_by")
            .eq("id", req.params.jobId)
            .maybeSingle();

        if (!job) throw ApiError.notFound("Job not found");
        if (job.created_by !== req.user.id && req.user.role !== "admin") {
            throw ApiError.forbidden("Not your job posting");
        }

        const { data, error } = await supabase
            .from("ai_evaluations")
            .select("*")
            .eq("job_id", req.params.jobId);

        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { evaluations: data ?? [] } });
    })
);
// ------------------------------------------------------------
// GET /api/v1/analysis/dashboard
// One call powers the whole HR dashboard — counts, attention items
// and the per-vacancy breakdown.
// ------------------------------------------------------------
router.get(
    "/dashboard",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const { data: jobs, error: jobsError } = await supabase
            .from("jobs")
            .select("id, title, status")
            .eq("created_by", req.user.id);

        if (jobsError) throw ApiError.internal(jobsError.message);

        const jobIds = (jobs ?? []).map((j) => j.id);

        if (jobIds.length === 0) {
            return res.json({
                success: true,
                data: {
                    totals: { applications: 0, applied: 0, shortlisted: 0, on_hold: 0, interview: 0, selected: 0, rejected: 0 },
                    unanalysed: 0,
                    stale: 0,
                    jobs: [],
                },
            });
        }

        const { data: applications, error: appsError } = await supabase
            .from("applications")
            .select("id, job_id, status, status_updated_at, created_at")
            .in("job_id", jobIds);

        if (appsError) throw ApiError.internal(appsError.message);

        const { data: evaluations } = await supabase
            .from("ai_evaluations")
            .select("application_id")
            .in("job_id", jobIds);

        const scored = new Set((evaluations ?? []).map((e) => e.application_id));

        const empty = () => ({
            applied: 0,
            shortlisted: 0,
            on_hold: 0,
            interview: 0,
            selected: 0,
            rejected: 0,
        });

        const totals = { applications: 0, ...empty() };
        const perJob = new Map(
            (jobs ?? []).map((j) => [
                j.id,
                { id: j.id, title: j.title, status: j.status, total: 0, ...empty() },
            ])
        );

        let unanalysed = 0;
        let stale = 0;

        // "Stale" means shortlisted and then left alone — the single most
        // common way a good candidate quietly goes cold.
        const fiveDaysAgo = Date.now() - 5 * 24 * 60 * 60 * 1000;

        for (const app of applications ?? []) {
            const status = app.status ?? "applied";
            const bucket = perJob.get(app.job_id);

            totals.applications += 1;
            if (status in totals) totals[status] += 1;

            if (bucket) {
                bucket.total += 1;
                if (status in bucket) bucket[status] += 1;
            }

            if (!scored.has(app.id)) unanalysed += 1;

            if (status === "shortlisted") {
                const since = app.status_updated_at ?? app.created_at;
                if (since && new Date(since).getTime() < fiveDaysAgo) stale += 1;
            }
        }

        res.json({
            success: true,
            data: {
                totals,
                unanalysed,
                stale,
                jobs: [...perJob.values()].sort((a, b) => b.total - a.total),
            },
        });
    })
);
export default router;