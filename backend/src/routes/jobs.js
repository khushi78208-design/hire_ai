import { Router } from "express";
import { z } from "zod";

import { supabase } from "../config/supabase.js";
import { asyncHandler } from "../middleware/errorHandler.js";
import { requireAuth, requireRole } from "../middleware/auth.js";
import { ApiError } from "../utils/ApiError.js";
import { notify } from "../services/notify.js";

const router = Router();

const jobSchema = z.object({
    title: z.string().min(3, "Title is too short"),
    description: z.string().min(20, "Describe the role in a bit more detail"),
    requirements: z.string().optional(),
    skills: z.array(z.string()).default([]),
    location: z.string().optional(),
    employment_type: z
        .enum(["full_time", "part_time", "contract", "internship"])
        .default("full_time"),
    experience_min: z.coerce.number().int().min(0).default(0),
    experience_max: z.coerce.number().int().min(0).optional(),
    salary_min: z.coerce.number().int().min(0).optional(),
    salary_max: z.coerce.number().int().min(0).optional(),
    openings: z.coerce.number().int().min(1).default(1),
    deadline: z.string().optional(),
    status: z.enum(["draft", "open", "closed"]).default("draft"),
});

// POST /api/v1/jobs  (HR only)
router.post(
    "/",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const body = jobSchema.parse(req.body);

        const { data, error } = await supabase
            .from("jobs")
            .insert({ ...body, created_by: req.user.id })
            .select()
            .single();

        if (error) throw ApiError.internal(`Could not create job: ${error.message}`);

        // A job created straight as "open" is published in one step.
        if (data.status === "open") {
            notify.newVacancy(data);
        }

        res.status(201).json({ success: true, data: { job: data } });
    })
);

// GET /api/v1/jobs
// Candidates see published jobs only. HR sees their own, drafts included.
router.get(
    "/",
    requireAuth,
    asyncHandler(async (req, res) => {
        const { search, location, mine } = req.query;

        let query = supabase
            .from("jobs")
            .select("*")
            .order("created_at", { ascending: false });

        if (req.user.role === "hr" && mine === "true") {
            query = query.eq("created_by", req.user.id);
        } else {
            query = query.eq("status", "open");
        }

        if (search) query = query.ilike("title", `%${search}%`);
        if (location) query = query.ilike("location", `%${location}%`);

        const { data, error } = await query;
        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { jobs: data ?? [] } });
    })
);

// GET /api/v1/jobs/:id
router.get(
    "/:id",
    requireAuth,
    asyncHandler(async (req, res) => {
        const { data: job } = await supabase
            .from("jobs")
            .select("*")
            .eq("id", req.params.id)
            .maybeSingle();

        if (!job) throw ApiError.notFound("Job not found");

        // A draft belongs to its author until it is published.
        if (job.status !== "open" && job.created_by !== req.user.id) {
            throw ApiError.notFound("Job not found");
        }

        let hasApplied = false;
        if (req.user.role === "candidate") {
            const { data: existing } = await supabase
                .from("applications")
                .select("id")
                .eq("job_id", job.id)
                .eq("candidate_id", req.user.id)
                .maybeSingle();
            hasApplied = !!existing;
        }

        res.json({ success: true, data: { job, hasApplied } });
    })
);

// PATCH /api/v1/jobs/:id  (HR, own jobs only)
router.patch(
    "/:id",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const body = jobSchema.partial().parse(req.body);

        const { data: job } = await supabase
            .from("jobs")
            .select("created_by, status")
            .eq("id", req.params.id)
            .maybeSingle();

        if (!job) throw ApiError.notFound("Job not found");
        if (job.created_by !== req.user.id && req.user.role !== "admin") {
            throw ApiError.forbidden("You can only edit jobs you created");
        }

        const { data, error } = await supabase
            .from("jobs")
            .update(body)
            .eq("id", req.params.id)
            .select()
            .single();

        if (error) throw ApiError.internal(error.message);

        // Fires when a draft becomes public, not on every edit of a live job.
        if (body.status === "open" && job.status !== "open") {
            notify.newVacancy(data);
        }

        res.json({ success: true, data: { job: data } });
    })
);

// POST /api/v1/jobs/:id/apply  (candidate only)
const applySchema = z.object({
    full_name: z.string().min(2, "Enter your full name"),
    email: z.string().email("Enter a valid email"),
    phone: z.string().min(10, "Enter a valid mobile number"),
    qualification: z.string().min(2, "Enter your qualification"),
    experience_years: z.coerce.number().int().min(0),
    current_city: z.string().min(2, "Enter your current city"),
    willing_to_relocate: z.boolean().default(false),
    resume_path: z.string().min(1, "Resume is required"),
    resume_filename: z.string().optional(),
    cover_note: z.string().optional(),
});

router.post(
    "/:id/apply",
    requireAuth,
    requireRole("candidate"),
    asyncHandler(async (req, res) => {
        const body = applySchema.parse(req.body);

        const { data: job } = await supabase
            .from("jobs")
            .select("id, status, title, created_by")
            .eq("id", req.params.id)
            .maybeSingle();

        if (!job) throw ApiError.notFound("Job not found");
        if (job.status !== "open") {
            throw ApiError.badRequest("This job is no longer accepting applications");
        }

        const { data: existing } = await supabase
            .from("applications")
            .select("id")
            .eq("job_id", job.id)
            .eq("candidate_id", req.user.id)
            .maybeSingle();

        if (existing) throw ApiError.conflict("You have already applied to this job");

        // The uploaded file is namespaced by user id, so this also proves the
        // candidate is submitting their own resume and not someone else's path.
        if (!body.resume_path.startsWith(req.user.id)) {
            throw ApiError.forbidden("Invalid resume reference");
        }

        const { data, error } = await supabase
            .from("applications")
            .insert({
                job_id: job.id,
                candidate_id: req.user.id,
                status: "applied",
                ...body,
            })
            .select()
            .single();

        if (error) throw ApiError.internal(error.message);

        notify.newApplication({ job, applicantName: body.full_name });

        res.status(201).json({ success: true, data: { application: data } });
    })
);

// GET /api/v1/jobs/:id/applications  (HR, own jobs only)
router.get(
    "/:id/applications",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const { data: job } = await supabase
            .from("jobs")
            .select("created_by")
            .eq("id", req.params.id)
            .maybeSingle();

        if (!job) throw ApiError.notFound("Job not found");
        if (job.created_by !== req.user.id && req.user.role !== "admin") {
            throw ApiError.forbidden("Not your job posting");
        }

        const { data, error } = await supabase
            .from("applications")
            .select("*, users:candidate_id (id, full_name, email)")
            .eq("job_id", req.params.id)
            .order("created_at", { ascending: false });

        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { applications: data ?? [] } });
    })
);

// DELETE /api/v1/jobs/:id  (HR, own jobs only)
router.delete(
    "/:id",
    requireAuth,
    requireRole("hr", "admin"),
    asyncHandler(async (req, res) => {
        const { data: job } = await supabase
            .from("jobs")
            .select("created_by")
            .eq("id", req.params.id)
            .maybeSingle();

        if (!job) throw ApiError.notFound("Job not found");
        if (job.created_by !== req.user.id && req.user.role !== "admin") {
            throw ApiError.forbidden("You can only delete jobs you created");
        }

        const { error } = await supabase.from("jobs").delete().eq("id", req.params.id);
        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { message: "Job deleted" } });
    })
);

export default router;