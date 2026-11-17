// Creates the plugin's real bridge object the way its loader does, before the engine starts.
import { BRIDGE_GLOBAL_NAME, GodotSDK } from "./sdk/libs/sdk.js";
window[BRIDGE_GLOBAL_NAME] = new GodotSDK();
window.__bridgeReadyResolve();
console.log("[harness] bridge", BRIDGE_GLOBAL_NAME, "ready on", window[BRIDGE_GLOBAL_NAME].platform);
