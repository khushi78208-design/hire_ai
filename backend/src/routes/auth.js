import { Router } from "express";
import bcrypt from "bcryptjs";
import { z } from "zod";

import { supabase } from "../config/supabase.js";
import { asyncHandler } from "../middleware/errorHandler.js";
import { requireAuth } from "../middleware/auth.js";
import { ApiError } from "../utils/ApiError.js";
import {
    signAccessToken,
    generateRefreshToken,
    hashToken,
    refreshExpiryDate,
} from "../utils/jwt.js";

const router = Router();

const registerSchema = z.object({
    email: z.string().email(),
    password: z.string().min(8, "Password must be at least 8 characters"),
    full_name: z.string().min(2, "Name is too short"),
    role: z.enum(["candidate", "hr"]).default("candidate"),
    phone: z.string().optional(),
});

const loginSchema = z.object({
    email: z.string().email(),
    password: z.string().min(1, "Password is required"),
});

// Never send password_hash to the client.
function publicUser(row) {
    return {
        id: row.id,
        email: row.email,
        full_name: row.full_name,
        role: row.role,
        approval_status: row.approval_status,
    };
}

async function issueSession(user, req) {
    const accessToken = signAccessToken(user);
    const refreshToken = generateRefreshToken();

    await supabase.from("refresh_tokens").insert({
        user_id: user.id,
        token_hash: hashToken(refreshToken),
        expires_at: refreshExpiryDate().toISOString(),
        user_agent: req.headers["user-agent"] || null,
    });

    return { accessToken, refreshToken };
}

router.post(
    "/register",
    asyncHandler(async (req, res) => {
        const body = registerSchema.parse(req.body);
        const email = body.email.toLowerCase().trim();

        const { data: existing } = await supabase
            .from("users")
            .select("id")
            .ilike("email", email)
            .maybeSingle();

        if (existing) throw ApiError.conflict("An account with this email already exists");

        const password_hash = await bcrypt.hash(body.password, 12);

        // HR accounts are held for approval so nobody can self-register as a
        // recruiter and start reading candidate data.
        const approval_status = body.role === "hr" ? "pending" : "approved";

        const { data: user, error } = await supabase
            .from("users")
            .insert({
                email,
                password_hash,
                full_name: body.full_name.trim(),
                role: body.role,
                phone: body.phone || null,
                approval_status,
            })
            .select()
            .single();

        if (error) throw ApiError.internal(`Could not create account: ${error.message}`);

        const tokens = await issueSession(user, req);

        res.status(201).json({
            success: true,
            data: { user: publicUser(user), ...tokens },
        });
    })
);

router.post(
    "/login",
    asyncHandler(async (req, res) => {
        const body = loginSchema.parse(req.body);
        const email = body.email.toLowerCase().trim();

        const { data: user } = await supabase
            .from("users")
            .select("*")
            .ilike("email", email)
            .maybeSingle();

        // Same message whether the email is unknown or the password is wrong —
        // otherwise this endpoint tells an attacker which emails are registered.
        const invalid = ApiError.unauthorized("Invalid email or password");

        if (!user || !user.password_hash) throw invalid;

        const ok = await bcrypt.compare(body.password, user.password_hash);
        if (!ok) throw invalid;

        if (!user.is_active) throw ApiError.forbidden("This account has been disabled");

        await supabase
            .from("users")
            .update({ last_login_at: new Date().toISOString() })
            .eq("id", user.id);

        const tokens = await issueSession(user, req);

        res.json({ success: true, data: { user: publicUser(user), ...tokens } });
    })
);

router.get(
    "/me",
    requireAuth,
    asyncHandler(async (req, res) => {
        const { data: user } = await supabase
            .from("users")
            .select("*")
            .eq("id", req.user.id)
            .maybeSingle();

        if (!user) throw ApiError.notFound("User not found");

        res.json({ success: true, data: { user: publicUser(user) } });
    })
);

router.post(
    "/logout",
    requireAuth,
    asyncHandler(async (req, res) => {
        const { refreshToken } = req.body || {};

        if (refreshToken) {
            await supabase
                .from("refresh_tokens")
                .update({ revoked_at: new Date().toISOString() })
                .eq("token_hash", hashToken(refreshToken));
        }

        res.json({ success: true, data: { message: "Logged out" } });
    })
);

export default router;