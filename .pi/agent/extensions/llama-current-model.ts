// Start Pi on whichever llama.cpp model the router already has loaded (else the one asleep), so opening Pi never
// forces a model swap. Only overrides Pi's configured default: an explicit --model/--models, or a resumed/continued
// session, is left alone. If the router is down, or the model is missing from Pi's catalog, nothing changes.
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PROVIDER = "llama.cpp";
const PINNED_BY_USER = /^(--model(=.*)?|--models(=.*)?|-c|--continue|-r|--resume|--session(=.*)?|--session-id(=.*)?|--fork(=.*)?)$/;

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (event, ctx) => {
    if (event.reason !== "startup") return;
    if (ctx.model?.provider !== PROVIDER) return;
    if (process.argv.slice(2).some((arg) => PINNED_BY_USER.test(arg))) return;

    const base = (process.env.LLAMA_BASE_URL ?? "http://127.0.0.1:9931").replace(/\/+$/, "");
    let wanted: string | undefined;
    try {
      const res = await fetch(`${base}/models`, { signal: AbortSignal.timeout(1500) });
      const data: { id: string; status?: { value?: string } }[] = (await res.json()).data ?? [];
      wanted = (data.find((m) => m.status?.value === "loaded") ?? data.find((m) => m.status?.value === "sleeping"))?.id;
    } catch {
      return;
    }
    if (!wanted || wanted === ctx.model.id) return;

    const model = ctx.modelRegistry.find(PROVIDER, wanted);
    if (model) await pi.setModel(model);
  });
}
