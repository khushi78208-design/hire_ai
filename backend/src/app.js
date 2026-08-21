import express from "express";
import cors from "cors";
import healthRouter from "./routes/health.js";
import authRouter from "./routes/auth.js";
import jobsRouter from "./routes/jobs.js";
import applicationsRouter from "./routes/applications.js";
import uploadRouter from "./routes/upload.js";
import analysisRouter from "./routes/analysis.js";
import agentRouter from "./routes/agent.js";
import { errorHandler, notFoundHandler } from "./middleware/errorHandler.js";

const app = express();

app.use(cors());
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Routes
app.use("/api/v1", healthRouter);
app.use("/api/v1/auth", authRouter);
app.use("/api/v1/jobs", jobsRouter);
app.use("/api/v1/applications", applicationsRouter);
app.use("/api/v1/upload", uploadRouter);
app.use("/api/v1/analysis", analysisRouter);
app.use("/api/v1/agent", agentRouter);

// 404 & Error Handler
app.use(notFoundHandler);
app.use(errorHandler);

export default app;