import { Router } from "express";

import { supabase } from "../config/supabase.js";
import { asyncHandler } from "../middleware/errorHandler.js";
import { requireAuth } from "../middleware/auth.js";
import { ApiError } from "../utils/ApiError.js";

const router = Router();

// GET /api/v1/notifications
router.get(
    "/",
    requireAuth,
    asyncHandler(async (req, res) => {
        // Twenty is more than anyone scrolls; older items are noise, not history.
        const { data, error } = await supabase
            .from("notifications")
            .select("*")
            .eq("user_id", req.user.id)
            .order("created_at", { ascending: false })
            .limit(20);

        if (error) throw ApiError.internal(error.message);

        const items = data ?? [];
        const unread = items.filter((n) => n.read_at === null).length;

        res.json({ success: true, data: { notifications: items, unread } });
    })
);

// POST /api/v1/notifications/read
router.post(
    "/read",
    requireAuth,
    asyncHandler(async (req, res) => {
        // Opening the bell marks everything read — per-item read state is more
        // bookkeeping than it is worth here.
        const { error } = await supabase
            .from("notifications")
            .update({ read_at: new Date().toISOString() })
            .eq("user_id", req.user.id)
            .is("read_at", null);

        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { message: "Marked as read" } });
    })
);

export default router;