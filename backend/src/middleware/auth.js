import { verifyAccessToken } from "../utils/jwt.js";
import { ApiError } from "../utils/ApiError.js";

export function requireAuth(req, res, next) {
    const header = req.headers.authorization || "";

    if (!header.startsWith("Bearer ")) {
        return next(ApiError.unauthorized("Missing or malformed token"));
    }

    try {
        const payload = verifyAccessToken(header.slice(7));
        req.user = { id: payload.sub, email: payload.email, role: payload.role };
        next();
    } catch (err) {
        if (err.name === "TokenExpiredError") {
            return next(ApiError.unauthorized("Token expired"));
        }
        next(ApiError.unauthorized("Invalid token"));
    }
}

// The Flutter app hides buttons it shouldn't show, but THIS is what actually
// enforces it — a candidate calling POST /jobs gets 403 here regardless.
export function requireRole(...roles) {
    return (req, res, next) => {
        if (!req.user) return next(ApiError.unauthorized());
        if (!roles.includes(req.user.role)) {
            return next(ApiError.forbidden("You do not have access to this resource"));
        }
        next();
    };
}