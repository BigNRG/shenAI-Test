import "./style.css";
import type {
  EventName,
  InitializationSettings,
  MeasurementResults,
  RisksFactors,
  ShenaiArguments,
  ShenaiSDK,
} from "@shenai/sdk";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const API_KEY_STORAGE = "shenai-test.apiKey";
const USER_ID_STORAGE = "shenai-test.userId";
const BUILD_TIME_API_KEY = (import.meta.env.VITE_SHENAI_API_KEY as string | undefined) ?? "";
const POLL_INTERVAL_MS = 200;

type Mode = "sdk-ui" | "custom-ui" | "dashboard";

// ---------------------------------------------------------------------------
// DOM helpers
// ---------------------------------------------------------------------------

function $<T extends HTMLElement = HTMLElement>(id: string): T {
  const el = document.getElementById(id);
  if (!el) throw new Error(`Missing element #${id}`);
  return el as T;
}

const views = {
  home: $("home-view"),
  measure: $("measure-view"),
  results: $("results-view"),
};

const ui = {
  back: $<HTMLButtonElement>("back-button"),
  version: $("sdk-version"),
  apiKey: $<HTMLInputElement>("api-key-input"),
  apiKeyToggle: $<HTMLButtonElement>("api-key-toggle"),
  userId: $<HTMLInputElement>("user-id-input"),
  sdkUi: $<HTMLButtonElement>("sdk-ui-button"),
  customUi: $<HTMLButtonElement>("custom-ui-button"),
  dashboard: $<HTMLButtonElement>("dashboard-button"),
  homeStatus: $("home-status"),
  measureLayout: document.querySelector<HTMLElement>(".measure-layout")!,
  customPanel: $("custom-panel"),
  measureStatus: $("measure-status"),
  progress: $<HTMLProgressElement>("measure-progress"),
  liveHr: $("live-hr"),
  liveHrv: $("live-hrv"),
  liveBr: $("live-br"),
  liveBp: $("live-bp"),
  liveStress: $("live-stress"),
  liveSignal: $("live-signal"),
  start: $<HTMLButtonElement>("start-button"),
  stop: $<HTMLButtonElement>("stop-button"),
  showResults: $<HTMLButtonElement>("show-results-button"),
  resultsTable: $<HTMLTableElement>("results-table"),
  pdf: $<HTMLButtonElement>("pdf-button"),
  json: $<HTMLButtonElement>("json-button"),
  home: $<HTMLButtonElement>("home-button"),
  resultsStatus: $("results-status"),
  sessionStatus: $("session-status"),
  log: $("log"),
};

function showView(name: keyof typeof views) {
  for (const [key, el] of Object.entries(views)) el.hidden = key !== name;
  ui.back.hidden = name === "home";
}

function setStatus(el: HTMLElement, text: string, isError = false) {
  el.textContent = text;
  el.classList.toggle("error", isError);
}

function log(message: string) {
  const time = new Date().toLocaleTimeString();
  ui.log.textContent = `[${time}] ${message}\n` + ui.log.textContent;
  console.log("[Shen.AI test]", message);
}

function storageGet(key: string): string {
  try {
    return localStorage.getItem(key) ?? "";
  } catch {
    return "";
  }
}

function storageSet(key: string, value: string) {
  try {
    localStorage.setItem(key, value);
  } catch {
    /* storage unavailable (private mode) - ignore */
  }
}

function fmt(value: number | null | undefined, decimals = 0): string {
  return value === null || value === undefined || Number.isNaN(value) ? "-" : value.toFixed(decimals);
}

// Embind enums are objects with a numeric `value`; find the constant's name.
function enumName(group: object, item: { value: number } | null | undefined): string {
  if (!item) return "-";
  for (const [name, candidate] of Object.entries(group)) {
    if ((candidate as { value?: number })?.value === item.value) return name;
  }
  return String(item.value);
}

function sameEnum(a: { value: number } | null | undefined, b: { value: number }): boolean {
  return !!a && a.value === b.value;
}

// ---------------------------------------------------------------------------
// SDK runtime: created on first use, while the canvas is visible (the SDK takes
// over the canvas at creation), then reused; each session initializes/deinitializes.
// ---------------------------------------------------------------------------

// The SDK is loaded at runtime from public/shenai-sdk (copied by scripts/copy-sdk.mjs)
// instead of being bundled: Vite's dev-server dependency optimizer rewrites the
// package and breaks the SDK's module worker, which makes initialization hang.
const SDK_MODULE_URL = "/shenai-sdk/index.mjs";
const INIT_TIMEOUT_MS = 45_000;

async function importSdk(): Promise<(args: ShenaiArguments) => Promise<ShenaiSDK>> {
  // Absolute URL so Vite's dev server doesn't rewrite the import (it treats "/..." paths as its own modules).
  const mod = await import(/* @vite-ignore */ new URL(SDK_MODULE_URL, window.location.origin).href);
  return mod.default;
}

let sdkPromise: Promise<ShenaiSDK> | null = null;
let sdk: ShenaiSDK | null = null;
let mode: Mode | null = null;
let pollTimer: number | undefined;
let lastResults: MeasurementResults | null = null;
let cameraError: string | null = null;
let diagTimer: number | undefined;

function loadSdk(): Promise<ShenaiSDK> {
  if (!sdkPromise) {
    setStatus(ui.sessionStatus, "Loading Shen.AI SDK runtime...");
    log("Loading SDK runtime from /shenai-sdk/ ...");
    sdkPromise = importSdk().then((CreateShenaiSDK) => CreateShenaiSDK({
      // Load the WASM + worker files from public/shenai-sdk (copied by scripts/copy-sdk.mjs).
      locateFile: (filename: string) => "/shenai-sdk/" + filename,
      wasmLoadingProgressCallback: (p: number) => setStatus(ui.sessionStatus, `Loading SDK runtime... ${Math.round(p)}%`),
    }).then((instance) => {
      sdk = instance;
      ui.version.textContent = `SDK ${instance.getVersion()}`;
      setStatus(ui.sessionStatus, "SDK runtime loaded.");
      log(`SDK runtime loaded, version ${instance.getVersion()}`);
      (window as unknown as { shenai: ShenaiSDK }).shenai = instance; // handy for console debugging
      return instance;
    }));
    sdkPromise.catch((err) => {
      sdkPromise = null;
      setStatus(ui.homeStatus, `Failed to load SDK: ${err}`, true);
      log(`Failed to load SDK: ${err}`);
    });
  }
  return sdkPromise;
}

function exampleRiskFactors(s: ShenaiSDK): RisksFactors {
  return {
    age: 45,
    cholesterol: 190,
    cholesterolHdl: 52,
    sbp: 128,
    dbp: 82,
    isSmoker: false,
    hypertensionTreatment: s.HypertensionTreatment.NO,
    hasDiabetes: false,
    bodyHeight: 172,
    bodyWeight: 74,
    gender: s.Gender.FEMALE,
    physicalActivity: s.PhysicalActivity.MODERATELY,
    country: "US",
    race: s.Race.WHITE,
  };
}

function settingsFor(s: ShenaiSDK, m: Mode): InitializationSettings {
  const common: InitializationSettings = {
    precisionMode: s.PrecisionMode.RELAXED,
    operatingMode: s.OperatingMode.MEASURE,
    measurementPreset: s.MeasurementPreset.THIRTY_SECONDS_ALL_METRICS,
    cameraMode: s.CameraMode.FACING_USER,
    uiVersion: s.UiVersion.V2,
    enableHealthRisks: true,
    saveHealthRisksFactors: true,
    risksFactors: exampleRiskFactors(s),
    eventCallback: (event: EventName) => onSdkEvent(event),
    onCameraError: () => {
      const err = enumName(s.CameraError, s.getLastCameraError());
      cameraError = `Camera error: ${err}. Allow camera access for this site and make sure no other app is using the camera.`;
      log(`Camera error: ${err}`);
      setStatus(ui.sessionStatus, cameraError, true);
    },
  };

  switch (m) {
    case "sdk-ui":
      return {
        ...common,
        onboardingMode: s.OnboardingMode.SHOW_ONCE,
        showUserInterface: true,
        showFacePositioningOverlay: true,
        showVisualWarnings: true,
        enableCameraSwap: true,
        showFaceMask: true,
        showBloodFlow: true,
        enableStartAfterSuccess: false,
        enableSummaryScreen: true,
        showResultsFinishButton: true,
        showHealthIndicesFinishButton: true,
        showSignalQualityIndicator: true,
        showSignalTile: true,
        showStartStopButton: true,
        showInfoButton: true,
        showDisclaimer: true,
        enableMeasurementsDashboard: false,
        uiFlowScreens: [s.Screen.MEASUREMENT, s.Screen.RESULTS, s.Screen.HEALTH_RISKS],
      };
    case "dashboard":
      return {
        ...common,
        onboardingMode: s.OnboardingMode.HIDDEN,
        showUserInterface: true,
        enableSummaryScreen: false,
        showResultsFinishButton: false,
        showHealthIndicesFinishButton: false,
        showStartStopButton: false,
        showInfoButton: false,
        showDisclaimer: false,
        uiFlowScreens: [s.Screen.DASHBOARD],
      };
    case "custom-ui":
      // The SDK only renders the camera preview + face mask; our own panel
      // shows state, progress and live metrics via polling.
      return {
        ...common,
        onboardingMode: s.OnboardingMode.HIDDEN,
        showUserInterface: false,
        showFacePositioningOverlay: false,
        showVisualWarnings: false,
        enableCameraSwap: false,
        showFaceMask: true,
        showBloodFlow: false,
        enableStartAfterSuccess: false,
        enableSummaryScreen: false,
        showResultsFinishButton: false,
        showHealthIndicesFinishButton: false,
        showSignalQualityIndicator: false,
        showSignalTile: false,
        showStartStopButton: false,
        showInfoButton: false,
        showDisclaimer: false,
      };
  }
}

async function openMode(m: Mode) {
  const apiKey = ui.apiKey.value.trim();
  if (!apiKey) {
    setStatus(ui.homeStatus, "Enter your Shen.AI API key first.", true);
    ui.apiKey.focus();
    return;
  }
  storageSet(API_KEY_STORAGE, apiKey);
  storageSet(USER_ID_STORAGE, ui.userId.value.trim());
  setButtonsEnabled(false);

  // The canvas must be visible (laid out, non-zero size) before the SDK runtime
  // is created: the SDK takes over the canvas and transfers it to its worker.
  mode = m;
  lastResults = null;
  cameraError = null;
  ui.customPanel.hidden = m !== "custom-ui";
  ui.measureLayout.classList.toggle("with-panel", m === "custom-ui");
  showView("measure");
  resetLivePanel();
  setStatus(ui.homeStatus, "");
  await nextFrame();

  let s: ShenaiSDK;
  try {
    s = await loadSdk();
  } catch {
    setButtonsEnabled(true);
    mode = null;
    showView("home");
    return;
  }
  if (mode !== m) return; // user pressed Back while the runtime was loading

  if (s.isInitialized()) s.deinitialize();
  const canvas = document.getElementById("mxcanvas");
  const rect = canvas?.getBoundingClientRect();
  log(`Initializing SDK in "${m}" mode (canvas ${Math.round(rect?.width ?? 0)}x${Math.round(rect?.height ?? 0)}, isolated=${window.crossOriginIsolated})`);

  setStatus(ui.sessionStatus, "Initializing SDK (activating license)...");
  let settled = false;
  const timeout = window.setTimeout(() => {
    if (settled) return;
    settled = true;
    log(`Initialization timed out after ${INIT_TIMEOUT_MS / 1000}s`);
    closeSession();
    setStatus(
      ui.homeStatus,
      "Initialization timed out. Check the browser console for errors and that the page is cross-origin isolated.",
      true,
    );
  }, INIT_TIMEOUT_MS);

  s.initialize(apiKey, ui.userId.value.trim(), settingsFor(s, m), (result) => {
    if (settled) return;
    settled = true;
    window.clearTimeout(timeout);
    if (mode !== m) return; // session was closed while initializing
    setButtonsEnabled(true);
    setStatus(ui.sessionStatus, "");
    if (!sameEnum(result, s.InitializationResult.OK)) {
      const name = enumName(s.InitializationResult, result);
      log(`Initialization failed: ${name}`);
      closeSession();
      setStatus(ui.homeStatus, `Initialization failed: ${name}. Check the API key and network.`, true);
      return;
    }
    log("SDK initialized (license activated)");
    setStatus(ui.homeStatus, "");
    if (cameraError) setStatus(ui.sessionStatus, cameraError, true);
    startDiagnostics(s);
    if (m === "sdk-ui") {
      s.resetMeasurementSession();
      s.setScreen(s.Screen.MEASUREMENT);
    }
    if (m === "custom-ui") startPolling();
  });
}

function closeSession() {
  stopPolling();
  stopDiagnostics();
  endSdkSession();
  mode = null;
  setStatus(ui.sessionStatus, "");
  setButtonsEnabled(true);
  showView("home");
}

function endSdkSession() {
  // Keep the runtime (and the canvas it owns) alive across sessions; only
  // deinitialize. Deferred because this can run inside an SDK callback.
  const s = sdk;
  window.setTimeout(() => {
    try {
      if (s?.isInitialized()) {
        s.deinitialize();
        log("SDK deinitialized");
      }
    } catch (err) {
      log(`Error while deinitializing SDK: ${err}`);
    }
  }, 0);
}

function nextFrame(): Promise<void> {
  return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => resolve())));
}

// Periodically log camera/face/measurement state so problems are visible in the event log.
function startDiagnostics(s: ShenaiSDK) {
  stopDiagnostics();
  let last = "";
  const tick = () => {
    if (!s.isInitialized()) return;
    const line =
      `camera=${enumName(s.CameraMode, s.getCameraMode())}` +
      ` cameraError=${enumName(s.CameraError, s.getLastCameraError())}` +
      ` face=${enumName(s.FaceState, s.getFaceState())}` +
      ` state=${enumName(s.MeasurementState, s.getMeasurementState())}` +
      ` screen=${enumName(s.Screen, s.getScreen())}`;
    if (line !== last) log(line);
    last = line;
  };
  tick();
  diagTimer = window.setInterval(tick, 2000);
}

function stopDiagnostics() {
  if (diagTimer !== undefined) window.clearInterval(diagTimer);
  diagTimer = undefined;
}

function onSdkEvent(event: EventName) {
  log(`Event: ${event}`);
  if (!sdk) return;
  if (event === "MEASUREMENT_FINISHED") {
    lastResults = sdk.getMeasurementResults();
    if (mode === "custom-ui") ui.showResults.hidden = !lastResults;
  }
  if (event === "USER_FLOW_FINISHED") {
    lastResults = sdk.getMeasurementResults() ?? lastResults;
    if (mode === "sdk-ui" && lastResults) {
      showResults();
    } else {
      closeSession();
    }
  }
}

// ---------------------------------------------------------------------------
// Custom UI: poll SDK state + realtime metrics
// ---------------------------------------------------------------------------

function isRunning(s: ShenaiSDK): boolean {
  const st = s.getMeasurementState();
  return [
    s.MeasurementState.WAITING_FOR_FACE,
    s.MeasurementState.RUNNING_SIGNAL_SHORT,
    s.MeasurementState.RUNNING_SIGNAL_GOOD,
    s.MeasurementState.RUNNING_SIGNAL_BAD,
    s.MeasurementState.RUNNING_SIGNAL_BAD_DEVICE_UNSTABLE,
    s.MeasurementState.FINALIZING,
  ].some((candidate) => sameEnum(st, candidate));
}

function statusText(s: ShenaiSDK): string {
  const state = s.getMeasurementState();
  if (sameEnum(state, s.MeasurementState.FINISHED)) return "Measurement finished";
  if (sameEnum(state, s.MeasurementState.FAILED)) return "Measurement failed - try again";
  if (sameEnum(state, s.MeasurementState.FINALIZING)) return "Finalizing...";
  const condition = s.getCurrentViolatedMeasurementEnvironmentCondition();
  if (condition) {
    const C = s.MeasurementEnvironmentCondition;
    if (sameEnum(condition, C.FACE_POSITION)) return "Center your face in the frame";
    if (sameEnum(condition, C.FOREHEAD_VISIBLE)) return "Uncover your forehead";
    if (sameEnum(condition, C.GLASSES_NOT_DETECTED)) return "Remove your glasses";
    if (sameEnum(condition, C.SUFFICIENT_LIGHT_LEVEL)) return "Move to brighter light";
    if (sameEnum(condition, C.EVEN_LIGHTING)) return "Use even lighting";
    if (sameEnum(condition, C.NO_BACKLIGHT)) return "Avoid backlight";
    if (sameEnum(condition, C.FACE_STABLE)) return "Keep your face still";
    if (sameEnum(condition, C.DEVICE_STABLE)) return "Keep the device still";
  }
  if (sameEnum(state, s.MeasurementState.WAITING_FOR_FACE)) return "Waiting for face...";
  if (isRunning(s)) return `Measuring (${enumName(s.MeasurementState, state)})`;
  return `Face: ${enumName(s.FaceState, s.getFaceState())} - press Start`;
}

function resetLivePanel() {
  ui.progress.value = 0;
  for (const el of [ui.liveHr, ui.liveHrv, ui.liveBr, ui.liveBp, ui.liveStress, ui.liveSignal]) el.textContent = "-";
  ui.showResults.hidden = true;
  setStatus(ui.measureStatus, "Ready");
}

function renderLive(r: MeasurementResults | null, hr10s: number | null) {
  ui.liveHr.textContent = r ? fmt(r.heart_rate_bpm) : fmt(hr10s);
  ui.liveHrv.textContent = fmt(r?.hrv_sdnn_ms, 1);
  ui.liveBr.textContent = fmt(r?.breathing_rate_bpm, 1);
  ui.liveBp.textContent =
    r?.systolic_blood_pressure_mmhg != null && r?.diastolic_blood_pressure_mmhg != null
      ? `${fmt(r.systolic_blood_pressure_mmhg)}/${fmt(r.diastolic_blood_pressure_mmhg)}`
      : "-";
  ui.liveStress.textContent = fmt(r?.stress_index, 1);
}

function poll() {
  const s = sdk;
  if (!s || !s.isInitialized() || mode !== "custom-ui") return;
  const running = isRunning(s);
  const finished = sameEnum(s.getMeasurementState(), s.MeasurementState.FINISHED);

  setStatus(ui.measureStatus, cameraError ?? statusText(s), !!cameraError);
  ui.progress.value = s.getMeasurementProgressPercentage();
  ui.liveSignal.textContent = fmt(s.getCurrentSignalQualityMetric(), 1);
  ui.start.disabled = running;
  ui.stop.disabled = !running;

  if (finished) {
    lastResults = s.getMeasurementResults() ?? lastResults;
    renderLive(lastResults, null);
    ui.showResults.hidden = !lastResults;
  } else if (running) {
    renderLive(s.getRealtimeMetrics(10), s.getHeartRate10s());
  }
}

function startPolling() {
  stopPolling();
  poll();
  pollTimer = window.setInterval(poll, POLL_INTERVAL_MS);
}

function stopPolling() {
  if (pollTimer !== undefined) window.clearInterval(pollTimer);
  pollTimer = undefined;
}

// ---------------------------------------------------------------------------
// Results
// ---------------------------------------------------------------------------

function showResults() {
  stopPolling();
  const r = lastResults;
  if (!r || !sdk) {
    closeSession();
    return;
  }
  // Keep the SDK initialized (PDF export needs the session) but stop the camera.
  sdk.setCameraMode(sdk.CameraMode.OFF);

  const q = r.quality_metrics;
  const rows: Array<[string, string] | string> = [
    "Vitals",
    ["Heart rate", `${fmt(r.heart_rate_bpm)} bpm`],
    ["HRV SDNN", `${fmt(r.hrv_sdnn_ms, 1)} ms`],
    ["HRV lnRMSSD", `${fmt(r.hrv_lnrmssd_ms, 2)} ms`],
    ["Breathing rate", `${fmt(r.breathing_rate_bpm, 1)} brpm`],
    ["Systolic BP", `${fmt(r.systolic_blood_pressure_mmhg)} mmHg`],
    ["Diastolic BP", `${fmt(r.diastolic_blood_pressure_mmhg)} mmHg`],
    ["Cardiac stress", fmt(r.stress_index, 1)],
    ["PNS activity", fmt(r.parasympathetic_activity, 1)],
    ["Cardiac workload", `${fmt(r.cardiac_workload_mmhg_per_sec, 1)} mmHg/s`],
    "Body",
    ["Age estimate", `${fmt(r.age_years)} years`],
    ["BMI", `${fmt(r.bmi_kg_per_m2, 1)} kg/m²`],
    ["BMI category", enumName(sdk.BmiCategory, r.bmi_category)],
    ["Weight", `${fmt(r.weight_kg, 1)} kg`],
    ["Height", `${fmt(r.height_cm, 1)} cm`],
    "Signal",
    ["Average signal quality", `${fmt(r.average_signal_quality, 1)} dB`],
    ["PPG quality index", fmt(q?.ppg_quality_index, 1)],
    ["BCG quality index", fmt(q?.bcg_quality_index, 1)],
    ["Heartbeats detected", String(r.heartbeats?.length ?? 0)],
    ["Measurement ID", sdk.getMeasurementID() || "-"],
  ];

  ui.resultsTable.replaceChildren(
    ...rows.map((row) => {
      const tr = document.createElement("tr");
      if (typeof row === "string") {
        tr.className = "section";
        const td = document.createElement("td");
        td.colSpan = 2;
        td.textContent = row;
        tr.append(td);
      } else {
        for (const text of row) {
          const td = document.createElement("td");
          td.textContent = text;
          tr.append(td);
        }
      }
      return tr;
    }),
  );
  setStatus(ui.resultsStatus, "");
  showView("results");
  log("Showing results");
}

// ---------------------------------------------------------------------------
// Wiring
// ---------------------------------------------------------------------------

function setButtonsEnabled(enabled: boolean) {
  ui.sdkUi.disabled = ui.customUi.disabled = ui.dashboard.disabled = !enabled;
}

ui.apiKey.value = storageGet(API_KEY_STORAGE) || BUILD_TIME_API_KEY;
ui.userId.value = storageGet(USER_ID_STORAGE);
ui.apiKeyToggle.addEventListener("click", () => {
  const show = ui.apiKey.type === "password";
  ui.apiKey.type = show ? "text" : "password";
  ui.apiKeyToggle.textContent = show ? "Hide" : "Show";
});

ui.sdkUi.addEventListener("click", () => openMode("sdk-ui"));
ui.customUi.addEventListener("click", () => openMode("custom-ui"));
ui.dashboard.addEventListener("click", () => openMode("dashboard"));
ui.back.addEventListener("click", closeSession);
ui.home.addEventListener("click", closeSession);

ui.start.addEventListener("click", () => {
  if (!sdk?.isInitialized()) return;
  resetLivePanel();
  lastResults = null;
  sdk.resetMeasurementSession();
  sdk.setCameraMode(sdk.CameraMode.FACING_USER);
  sdk.setOperatingMode(sdk.OperatingMode.MEASURE);
  sdk.startMeasurement();
  log("Measurement started");
});
ui.stop.addEventListener("click", () => {
  if (!sdk?.isInitialized()) return;
  sdk.stopMeasurement();
  log("Measurement stopped");
});
ui.showResults.addEventListener("click", showResults);

ui.pdf.addEventListener("click", () => {
  if (!sdk?.isInitialized()) return;
  setStatus(ui.resultsStatus, "Requesting PDF report...");
  sdk.getMeasurementResultsPdfUrl((url) => {
    if (url) {
      window.open(url, "_blank", "noopener");
      setStatus(ui.resultsStatus, "PDF opened in a new tab.");
    } else {
      setStatus(ui.resultsStatus, "PDF could not be generated.", true);
    }
  });
});
ui.json.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(JSON.stringify(lastResults, null, 2));
    setStatus(ui.resultsStatus, "Results JSON copied to clipboard.");
  } catch {
    setStatus(ui.resultsStatus, "Clipboard unavailable - see console.", true);
    console.log(lastResults);
  }
});

window.addEventListener("error", (e) => log(`Error: ${e.message || e.type}`));
window.addEventListener("unhandledrejection", (e) => log(`Unhandled rejection: ${String(e.reason)}`));

if (!window.crossOriginIsolated) {
  setStatus(
    ui.homeStatus,
    "Warning: page is not cross-origin isolated (COOP/COEP headers missing). The SDK needs SharedArrayBuffer.",
    true,
  );
}

showView("home");
