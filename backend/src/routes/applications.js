import { Router } from "express";
import { supabase } from "../config/supabase.js";
import { asyncHandler } from "../middleware/errorHandler.js";
import { requireAuth, requireRole } from "../middleware/auth.js";
import { ApiError } from "../utils/ApiError.js";

const router = Router();

// GET /api/v1/applications/me
router.get(
    "/me",
    requireAuth,
    requireRole("candidate"),
    asyncHandler(async (req, res) => {
        const { data, error } = await supabase
            .from("applications")
            .select("*, jobs:job_id (id, title, location, status)")
            .eq("candidate_id", req.user.id)
            .order("created_at", { ascending: false });

        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { applications: data ?? [] } });
    })
);

export default router;