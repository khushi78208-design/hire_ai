import { supabase } from "../config/supabase.js";

/**
 * Notifications are a side effect, never the point of a request. A failure
 * here is logged and swallowed so it can't take down the action that
 * triggered it — a candidate's application must not fail because the bell
 * could not be updated.
 */
async function insert(rows) {
    if (!rows.length) return;

    const { error } = await supabase.from("notifications").insert(rows);
    if (error) console.error("[notify]", error.message);
}

export const notify = {
    /** Every candidate hears about a newly published vacancy. */
    async newVacancy(job) {
        const { data: candidates } = await supabase
            .from("users")
            .select("id")
            .eq("role", "candidate")
            .eq("is_active", true);

        await insert(
            (candidates ?? []).map((c) => ({
                user_id: c.id,
                type: "new_vacancy",
                title: "New vacancy posted",
                body: `${job.title}${job.location ? ` · ${job.location}` : ""}`,
                entity_type: "job",
                entity_id: job.id,
            }))
        );
    },

    /** The recruiter who owns the posting hears about each application. */
    async newApplication({ job, applicantName }) {
        if (!job?.created_by) return;

        await insert([
            {
                user_id: job.created_by,
                type: "new_application",
                title: "New application",
                body: `${applicantName || "Someone"} applied to ${job.title}`,
                entity_type: "application",
                entity_id: job.id,
            },
        ]);
    },
};