// Envoie les rappels push. Appelée toutes les 15 min par pg_cron.
// Authentification : en-tête x-cron-secret vérifié par la fonction SQL reminders_due.
// Le texte est composé ici, dans la langue de l'appareil (fr, ar ; repli fr).
// Compatible avec l'ancien format (title/body déjà rédigés par la base).
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

type Child = { name: string; done: number; total: number; pending: number };
type Item = { endpoint: string; p256dh: string; auth: string; locale?: string; kind?: "child" | "parent";
  left?: number | null; children?: Child[] | null; title?: string; body?: string };

const T: Record<string, { childTitle: string; childBody: (n: number) => string; parentTitle: string;
  line: (c: Child) => string; join: string }> = {
  fr: {
    childTitle: "C'est l'heure de tes routines 🌱",
    childBody: n => `Encore ${n} à faire. Ta plante t'attend !`,
    parentTitle: "Routines du jour 🌱",
    line: c => `${c.name} : ${c.done}/${c.total}` + (c.pending > 0 ? ` (${c.pending} à valider)` : ""),
    join: ", ",
  },
  ar: {
    childTitle: "حان وقت أنشطتنا 🌱",
    childBody: n => `بقي ${n} لننجزه. نبتتنا تنتظرنا!`,
    parentTitle: "أنشطة اليوم 🌱",
    line: c => `${c.name}: ${c.done}/${c.total}` + (c.pending > 0 ? ` (${c.pending} بانتظار التأكيد)` : ""),
    join: "، ",
  },
};

function compose(it: Item): { title: string; body: string } | null {
  if (it.title !== undefined && it.body !== undefined) return it.body ? { title: it.title, body: it.body } : null; // ancien format
  const t = T[it.locale ?? "fr"] ?? T.fr;
  if (it.kind === "child") return it.left && it.left > 0 ? { title: t.childTitle, body: t.childBody(it.left) } : null;
  const list = it.children ?? [];
  return list.length ? { title: t.parentTitle, body: list.map(t.line).join(t.join) } : null;
}

Deno.serve(async (req: Request) => {
  const secret = req.headers.get("x-cron-secret") ?? "";
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, key, { auth: { persistSession: false } });

  const { data, error } = await sb.rpc("reminders_due", { p_secret: secret });
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), { status: 403, headers: { "Content-Type": "application/json" } });
  }

  webpush.setVapidDetails(data.subject, data.vapid_public, data.vapid_private);
  let sent = 0, removed = 0, failed = 0;
  for (const it of (data.items ?? []) as Item[]) {
    const msg = compose(it);
    if (!msg) continue;
    try {
      await webpush.sendNotification(
        { endpoint: it.endpoint, keys: { p256dh: it.p256dh, auth: it.auth } },
        JSON.stringify(msg),
        { TTL: 3600 },
      );
      sent++;
    } catch (e) {
      const code = (e as { statusCode?: number })?.statusCode;
      if (code === 404 || code === 410) {
        await sb.rpc("push_unsubscribe", { p_endpoint: it.endpoint });
        removed++;
      } else {
        failed++;
        console.error("push error", code, String(e));
      }
    }
  }
  return new Response(JSON.stringify({ due: (data.items ?? []).length, sent, removed, failed }), {
    headers: { "Content-Type": "application/json" },
  });
});
