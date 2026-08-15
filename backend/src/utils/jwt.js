import jwt from "jsonwebtoken";
import crypto from "crypto";
import { env } from "../config/env.js";

export function signAccessToken(user) {
    return jwt.sign(
        { sub: user.id, email: user.email, role: user.role },
        env.JWT_SECRET,
        { expiresIn: env.JWT_ACCESS_EXPIRES_IN }
    );
}

export function verifyAccessToken(token) {
    return jwt.verify(token, env.JWT_SECRET);
}

// Refresh token is a random string, not a JWT. We store only its hash,
// so a database leak cannot be replayed to mint new sessions.
export function generateRefreshToken() {
    return crypto.randomBytes(48).toString("hex");
}

export function hashToken(token) {
    return crypto.createHash("sha256").update(token).digest("hex");
}

export function refreshExpiryDate() {
    const days = parseInt(env.JWT_REFRESH_EXPIRES_IN) || 7;
    return new Date(Date.now() + days * 24 * 60 * 60 * 1000);
}