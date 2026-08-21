import { Router } from "express";
import { z } from "zod";

import { supabase } from "../config/supabase.js";
import { asyncHandler } from "../middleware/errorHandler.js";
import { requireAuth, requireRole } from "../middleware/auth.js";
import { ApiError } from "../utils/ApiError.js";

const router = Router();

// GET /api/v1/applications/me  (candidate's own applications)
router.get(
    "/me",
    requireAuth,
    requireRole("candidate"),
    asyncHandler(async (req, res) => {
        // Deliberately excludes ai_evaluations. The AI score is an internal
        // screening aid — showing it to candidates invites disputes and
        // demoralises people over a number a human may well override.
        const { data, error } = await supabase
            .from("applications")
            .select(
                "id, status, status_note, status_updated_at, created_at, " +
                "jobs:job_id (id, title, location, status)"
            )
            .eq("candidate_id", req.user.id)
            .order("created_at", { ascending: false });

        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { applications: data ?? [] } });
    })
);

// ------------------------------------------------------------
// GET /api/v1/applications/all
// Every application across this recruiter's postings, for the
// "All vacancies" view.
// ------------------------------------------------------------
router.get(
    "/all",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const { data: jobs } = await supabase
            .from("jobs")
            .select("id, title")
            .eq("created_by", req.user.id);

        const jobIds = (jobs ?? []).map((j) => j.id);
        if (jobIds.length === 0) {
            return res.json({ success: true, data: { applications: [] } });
        }

        const { data, error } = await supabase
            .from("applications")
            .select(
                "*, users:candidate_id (id, full_name, email), jobs:job_id (id, title)"
            )
            .in("job_id", jobIds)
            .order("created_at", { ascending: false });

        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { applications: data ?? [] } });
    })
);

const statusSchema = z.object({
    status: z.enum([
        "applied",
        "shortlisted",
        "on_hold",
        "interview",
        "selected",
        "rejected",
    ]),
    status_note: z.string().max(500).optional(),
});

// PATCH /api/v1/applications/:id/status  (HR, own job postings only)
router.patch(
    "/:id/status",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const body = statusSchema.parse(req.body);

        const { data: application } = await supabase
            .from("applications")
            .select("id, status, jobs:job_id (id, created_by)")
            .eq("id", req.params.id)
            .maybeSingle();

        if (!application) throw ApiError.notFound("Application not found");

        const job = application.jobs;
        if (!job) throw ApiError.notFound("Job not found");
        if (job.created_by !== req.user.id && req.user.role !== "admin") {
            throw ApiError.forbidden("Not your job posting");
        }

        const { data, error } = await supabase
            .from("applications")
            .update({
                status: body.status,
                status_note: body.status_note ?? null,
                status_updated_at: new Date().toISOString(),
                status_updated_by: req.user.id,
            })
            .eq("id", req.params.id)
            .select()
            .single();

        if (error) throw ApiError.internal(error.message);

        // Hiring decisions need a paper trail: who changed what, and when.
        await supabase.from("audit_logs").insert({
            actor_id: req.user.id,
            action: "application_status_changed",
            entity_type: "application",
            entity_id: application.id,
            metadata: {
                from: application.status,
                to: body.status,
                note: body.status_note ?? null,
            },
        });

        res.json({ success: true, data: { application: data } });
    })
);

export default router;