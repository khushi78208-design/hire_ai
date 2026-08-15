import { Router } from "express";
import { asyncHandler } from "../middleware/errorHandler.js";
import { checkDatabase } from "../config/supabase.js";
import { aiClient } from "../services/aiClient.js";

const router = Router();

router.get("/health", (req, res) => {
  res.json({ success: true, data: { status: "ok", service: "backend" } });
});

router.get(
  "/health/ready",
  asyncHandler(async (req, res) => {
    const checks = {};

    try {
      await checkDatabase();
      checks.database = "ok";
    } catch (err) {
      checks.database = `error: ${err.message}`;
    }

    try {
      await aiClient.health();
      checks.aiService = "ok";
    } catch (err) {
      checks.aiService = `error: ${err.message}`;
    }

    const healthy = Object.values(checks).every((v) => v === "ok");
    res.status(healthy ? 200 : 503).json({
      success: healthy,
      data: { status: healthy ? "ready" : "degraded", checks },
    });
  })
);

export default router;
