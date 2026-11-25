// Envoie les rappels push. Appelée toutes les 15 min par pg_cron.
// Authentification : en-tête x-cron-secret vérifié par la fonction SQL reminders_due.
// Le texte est composé ici, dans la langue de l'appareil (fr, ar, en ; repli en).
// Compatible avec l'ancien format (title/body déjà rédigés par la base).
import webpush from "npm:web-push@3.6.7";
import { createClient } from "npm:@supabase/supabase-js@2";

type Child = { name: string; done: number; total: number; pending: number; family?: string | null };
type Item = { endpoint: string; p256dh: string; auth: string; locale?: string; kind?: "child" | "parent" | "routine";
  left?: number | null; children?: Child[] | null; kids?: { name: string; left: number }[] | null; title?: string; body?: string;
  mode?: "device" | "here"; child?: string; common?: boolean; at?: string; routines?: { title: string; emoji?: string }[] };

const T: Record<string, { childTitle: string; childBody: (n: number) => string; parentTitle: string;
  line: (c: Child) => string; join: string; kidLine: (k: { name: string; left: number }) => string;
  routineTitle: (mode: string, common: boolean, child: string) => string }> = {
  fr: {
    childTitle: "C'est l'heure de tes routines 🌱",
    childBody: n => `Encore ${n} à faire. Ta plante t'attend !`,
    parentTitle: "Routines du jour 🌱",
    line: c => (c.family ? `${c.family} · ` : "") + `${c.name} : ${c.done}/${c.total}` + (c.pending > 0 ? ` (${c.pending} à valider)` : ""),
    join: ", ",
    kidLine: k => `${k.name} : encore ${k.left}`,
    routineTitle: (mode, common, child) => mode === "here" ? `⏰ C'est l'heure pour ${child} !` : common ? `⏰ ${child}, c'est l'heure !` : "⏰ C'est l'heure !",
  },
  ar: {
    childTitle: "حان وقت أنشطتنا 🌱",
    childBody: n => `بقي ${n} لننجزه. نبتتنا تنتظرنا!`,
    parentTitle: "أنشطة اليوم 🌱",
    line: c => (c.family ? `${c.family} · ` : "") + `${c.name}: ${c.done}/${c.total}` + (c.pending > 0 ? ` (${c.pending} بانتظار التأكيد)` : ""),
    join: "، ",
    kidLine: k => `${k.name}: بقي ${k.left}`,
    routineTitle: (mode, common, child) => mode === "here" ? `⏰ حان الوقت لـ ${child}!` : common ? `⏰ ${child}، حان الوقت!` : "⏰ حان الوقت!",
  },
  en: {
    childTitle: "Time for your routines 🌱",
    childBody: n => `${n} still to do. Your plant is waiting for you!`,
    parentTitle: "Today's routines 🌱",
    line: c => (c.family ? `${c.family} · ` : "") + `${c.name}: ${c.done}/${c.total}` + (c.pending > 0 ? ` (${c.pending} to approve)` : ""),
    join: ", ",
    kidLine: k => `${k.name}: ${k.left} to do`,
    routineTitle: (mode, common, child) => mode === "here" ? `⏰ Time for ${child}!` : common ? `⏰ ${child}, it's time!` : "⏰ It's time!",
  },
};

function compose(it: Item): { title: string; body: string } | null {
  if (it.title !== undefined && it.body !== undefined) return it.body ? { title: it.title, body: it.body } : null; // ancien format
  const t = T[it.locale ?? "en"] ?? T.en;   // DEC-36 : sans langue connue, anglais
  if (it.kind === "routine") {
    const list = it.routines ?? [];
    if (!list.length) return null;
    return { title: t.routineTitle(it.mode ?? "device", !!it.common, it.child ?? ""),
      body: list.map(r => `${r.emoji ?? ""} ${r.title}`.trim()).join(t.join) };
  }
  if (it.kind === "child" && it.kids) {   // appareil commun : une notification, le reste à faire de chaque enfant (R11-04 CA3)
    const kids = it.kids.filter(k => k.left > 0);
    return kids.length ? { title: t.childTitle, body: kids.map(t.kidLine).join(t.join) } : null;
  }
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

  // ADR-45 : clés dans les secrets de la fonction ; repli sur l'ancienne réponse de la base tant qu'elle les renvoie (migration en cours)
  const vPriv = Deno.env.get("VAPID_PRIVATE_KEY") ?? data.vapid_private;
  const vSubj = Deno.env.get("VAPID_SUBJECT") ?? data.subject;
  if (!vPriv || !vSubj) {
    return new Response(JSON.stringify({ error: "vapid_missing" }), { status: 500, headers: { "Content-Type": "application/json" } });
  }
  webpush.setVapidDetails(vSubj, data.vapid_public, vPriv);
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
