import app from "./app.js";
import { env } from "./config/env.js";

// Binding to 0.0.0.0 instead of the default makes the API reachable from
// other devices on the same network — a phone cannot see 127.0.0.1.
const server = app.listen(env.PORT, "0.0.0.0", () => {
  console.log(`Server is running on port ${env.PORT} in ${env.NODE_ENV} mode.`);
});

function shutdown(signal) {
  console.log(`[backend] ${signal} received, closing server`);
  server.close(() => process.exit(0));
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));