import { Router } from "express";
import multer from "multer";
import { randomUUID } from "crypto";

import { supabase } from "../config/supabase.js";
import { asyncHandler } from "../middleware/errorHandler.js";
import { requireAuth, requireRole } from "../middleware/auth.js";
import { ApiError } from "../utils/ApiError.js";

const router = Router();

const ALLOWED = {
    "application/pdf": "pdf",
    "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
    "application/msword": "doc",
};

// Memory storage: the file goes straight to Supabase, never touches disk.
const upload = multer({
    storage: multer.memoryStorage(),
    limits: { fileSize: 5 * 1024 * 1024 },
    fileFilter: (req, file, cb) => {
        if (!ALLOWED[file.mimetype]) {
            return cb(new Error("Only PDF and Word documents are allowed"));
        }
        cb(null, true);
    },
});

// POST /api/v1/upload/resume
router.post(
    "/resume",
    requireAuth,
    requireRole("candidate"),
    (req, res, next) => {
        upload.single("resume")(req, res, (err) => {
            if (err) {
                if (err.code === "LIMIT_FILE_SIZE") {
                    return next(ApiError.badRequest("Resume must be under 5 MB"));
                }
                return next(ApiError.badRequest(err.message));
            }
            next();
        });
    },
    asyncHandler(async (req, res) => {
        if (!req.file) throw ApiError.badRequest("No file received");

        const ext = ALLOWED[req.file.mimetype];
        // Path is namespaced by user id so one candidate can never guess
        // or overwrite another's file.
        const path = `${req.user.id}/${randomUUID()}.${ext}`;

        const { error } = await supabase.storage
            .from("resumes")
            .upload(path, req.file.buffer, {
                contentType: req.file.mimetype,
                upsert: false,
            });

        if (error) throw ApiError.internal(`Upload failed: ${error.message}`);

        res.status(201).json({
            success: true,
            data: { path, filename: req.file.originalname },
        });
    })
);

// GET /api/v1/upload/resume-url?path=...
// Private bucket, so every view needs a fresh short-lived signed URL.
router.get(
    "/resume-url",
    requireAuth,
    asyncHandler(async (req, res) => {
        const { path } = req.query;
        if (!path) throw ApiError.badRequest("path is required");

        // A candidate may only read their own file; HR reads any (they can only
        // reach paths through applications on their own jobs).
        if (req.user.role === "candidate" && !String(path).startsWith(req.user.id)) {
            throw ApiError.forbidden("Not your file");
        }

        const { data, error } = await supabase.storage
            .from("resumes")
            .createSignedUrl(String(path), 300);

        if (error) throw ApiError.internal(error.message);

        res.json({ success: true, data: { url: data.signedUrl } });
    })
);

export default router;