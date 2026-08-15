import express from "express";
import cors from "cors";
import healthRouter from "./routes/health.js";
import authRouter from "./routes/auth.js";
import { errorHandler, notFoundHandler } from "./middleware/errorHandler.js";

const app = express();

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Routes
app.use("/api/v1", healthRouter);
app.use("/api/v1/auth", authRouter);

// 404 & Error Handler
app.use(notFoundHandler);
app.use(errorHandler);

export default app;