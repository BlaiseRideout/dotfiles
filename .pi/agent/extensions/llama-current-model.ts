// Start Pi on the llama.cpp model the router already has resident (loaded, else asleep, else the one last used), so
// opening Pi never forces a model swap. The choice is made by `llama-current-model`, the same helper llama-ask and the
// opencode wrapper use. It only overrides Pi's configured default: an explicit --model/--models, or a resumed or
// continued session, is left alone. If the helper fails or the model is missing from Pi's catalog, nothing changes.
import { execFile } from "node:child_process";
import { homedir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const PROVIDER = "llama.cpp";
const HELPER = join(homedir(), ".local/bin/llama-current-model");
const PINNED_BY_USER = /^(--model(=.*)?|--models(=.*)?|-c|--continue|-r|--resume|--session(=.*)?|--session-id(=.*)?|--fork(=.*)?)$/;

function currentModel(): Promise<string | undefined> {
  return new Promise((resolve) => {
    execFile(HELPER, { timeout: 4000 }, (error, stdout) => resolve(error ? undefined : stdout.trim() || undefined));
  });
}

export default function (pi: ExtensionAPI) {
  pi.on("session_start", async (event, ctx) => {
    if (event.reason !== "startup") return;
    if (ctx.model?.provider !== PROVIDER) return;
    if (process.argv.slice(2).some((arg) => PINNED_BY_USER.test(arg))) return;

    const wanted = await currentModel();
    if (!wanted || wanted === ctx.model.id) return;

    const model = ctx.modelRegistry.find(PROVIDER, wanted);
    if (model) await pi.setModel(model);
  });
}
