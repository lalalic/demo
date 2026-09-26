/**
 * Demo Runtime — spotlight, TTS, captions, and event timeline for AI-driven demos.
 * Loaded in Electron renderer. Exposes window.demo for agent-browser control.
 */

interface DemoEvent {
  t: number;
  type: string;
  text?: string;
  selector?: string;
  duration?: number;
}

class DemoRuntime {
  private overlay: HTMLDivElement | null = null;
  private tooltip: HTMLDivElement | null = null;
  private captionBar: HTMLDivElement | null = null;
  private stepBadge: HTMLDivElement | null = null;
  private cursorEl: HTMLDivElement | null = null;
  private activeEl: HTMLElement | null = null;
  private events: DemoEvent[] = [];
  private recording = false;
  private startTime = 0;
  private stepCount = 0;
  private pauseResolve: (() => void) | null = null;
  private paused = false;

  // ─── Initialization ───

  private ensureOverlay() {
    if (this.overlay) return;
    this.overlay = document.createElement("div");
    this.overlay.id = "__demo_overlay";
    Object.assign(this.overlay.style, {
      position: "fixed", inset: "0", background: "rgba(0,0,0,0.55)",
      zIndex: "999998", pointerEvents: "none",
      transition: "clip-path 300ms ease, opacity 300ms ease", opacity: "0",
    });
    document.body.appendChild(this.overlay);
  }

  private ensureTooltip() {
    if (this.tooltip) return;
    this.tooltip = document.createElement("div");
    this.tooltip.id = "__demo_tooltip";
    Object.assign(this.tooltip.style, {
      position: "fixed", maxWidth: "300px", padding: "10px 14px",
      background: "#111", color: "#fff", borderRadius: "8px",
      fontSize: "13px", lineHeight: "1.4", zIndex: "1000000",
      pointerEvents: "none", opacity: "0", transition: "opacity 200ms ease",
      boxShadow: "0 4px 12px rgba(0,0,0,0.4)",
    });
    document.body.appendChild(this.tooltip);
  }

  private ensureCaptionBar() {
    if (this.captionBar) return;
    this.captionBar = document.createElement("div");
    this.captionBar.id = "__demo_caption";
    Object.assign(this.captionBar.style, {
      position: "fixed", bottom: "40px", left: "50%", transform: "translateX(-50%)",
      maxWidth: "70%", padding: "12px 24px",
      background: "rgba(0,0,0,0.75)", color: "#fff",
      borderRadius: "12px", fontSize: "16px", lineHeight: "1.5",
      textAlign: "center", zIndex: "1000001", pointerEvents: "none",
      opacity: "0", transition: "opacity 250ms ease",
      backdropFilter: "blur(8px)", fontFamily: "-apple-system, system-ui, sans-serif",
    });
    document.body.appendChild(this.captionBar);
  }

  private ensureStepBadge() {
    if (this.stepBadge) return;
    this.stepBadge = document.createElement("div");
    this.stepBadge.id = "__demo_step";
    Object.assign(this.stepBadge.style, {
      position: "fixed", top: "20px", left: "20px",
      padding: "6px 16px", background: "rgba(88,166,255,0.9)",
      color: "#fff", borderRadius: "20px", fontSize: "13px",
      fontWeight: "600", zIndex: "1000001", pointerEvents: "none",
      opacity: "0", transition: "opacity 250ms ease",
      fontFamily: "-apple-system, system-ui, sans-serif",
    });
    document.body.appendChild(this.stepBadge);
  }

  private ensureCursor() {
    if (this.cursorEl) return;
    this.cursorEl = document.createElement("div");
    this.cursorEl.id = "__demo_cursor";
    Object.assign(this.cursorEl.style, {
      position: "fixed", width: "20px", height: "20px",
      borderRadius: "50%", background: "rgba(255,100,100,0.7)",
      border: "2px solid rgba(255,255,255,0.8)",
      zIndex: "1000002", pointerEvents: "none",
      opacity: "0", transition: "left 400ms ease, top 400ms ease, opacity 200ms ease",
      boxShadow: "0 0 8px rgba(255,100,100,0.5)",
    });
    document.body.appendChild(this.cursorEl);
  }

  private logEvent(event: Omit<DemoEvent, "t">) {
    if (!this.recording) return;
    this.events.push({ t: Date.now() - this.startTime, ...event });
  }

  private resolveEl(selector: string): HTMLElement | null {
    // Support agent-browser @ref format (e.g., @e5, @e12)
    if (selector.startsWith("@")) {
      const refId = selector.slice(1); // "e5"
      // 1. Check data-demo-ref (set by mapRefs or tagRef)
      const tagged = document.querySelector(`[data-demo-ref="${refId}"]`) as HTMLElement;
      if (tagged) return tagged;
      // 2. Check data-ref (external injection)
      const ext = document.querySelector(`[data-ref="${refId}"]`) as HTMLElement;
      if (ext) return ext;
      // 3. No fallback — ref must be mapped first
      console.warn(`[DEMO] @${refId} not mapped. Call demo.mapRefs() or demo.tagRef("${refId}", "cssSelector") first.`);
      return null;
    }
    return document.querySelector(selector);
  }

  // ─── Ref Mapping ───

  /** Explicitly tag a DOM element with a ref ID for @ref resolution */
  tagRef(refId: string, cssSelector: string) {
    const el = document.querySelector(cssSelector);
    if (el) {
      el.setAttribute("data-demo-ref", refId.startsWith("e") ? refId : `e${refId}`);
    } else {
      console.warn(`[DEMO] tagRef: no element found for "${cssSelector}"`);
    }
  }

  /**
   * Map agent-browser snapshot refs to DOM elements.
   * Call after `agent-browser snapshot -i --json`, passing the refs object.
   * Best-effort: matches by ARIA role + accessible name in DOM tree order.
   */
  mapRefs(refs: Record<string, { role: string; name: string }>) {
    // Clear old mappings
    document.querySelectorAll("[data-demo-ref]").forEach(el =>
      el.removeAttribute("data-demo-ref")
    );

    // Collect all elements in DOM tree order
    const allEls: HTMLElement[] = [];
    const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
    let node: Node | null;
    while ((node = walker.nextNode())) allEls.push(node as HTMLElement);

    const used = new Set<HTMLElement>();

    // Sort refs by numeric order (e1, e2, ... e245)
    const sorted = Object.entries(refs).sort((a, b) => {
      const na = parseInt(a[0].replace(/\D/g, "")) || 0;
      const nb = parseInt(b[0].replace(/\D/g, "")) || 0;
      return na - nb;
    });

    for (const [refId, info] of sorted) {
      const el = this.findByRoleAndName(allEls, info.role, info.name, used);
      if (el) {
        el.setAttribute("data-demo-ref", refId);
        used.add(el);
      }
    }
    console.log(`[DEMO] mapRefs: mapped ${used.size}/${sorted.length} refs`);
  }

  private findByRoleAndName(
    elements: HTMLElement[], role: string, name: string, used: Set<HTMLElement>
  ): HTMLElement | null {
    // Normalize: collapse whitespace for comparison
    const normName = name.replace(/\s+/g, " ").trim();
    for (const el of elements) {
      if (used.has(el)) continue;
      if (!this.matchesRole(el, role)) continue;
      const accName = this.getAccessibleName(el);
      const normAccName = accName.replace(/\s+/g, " ").trim();
      // Exact match (normalized) or prefix match for truncated names
      if (normAccName === normName || (normName.length > 10 && normAccName.startsWith(normName))) {
        return el;
      }
    }
    return null;
  }

  private matchesRole(el: HTMLElement, role: string): boolean {
    const explicit = el.getAttribute("role");
    if (explicit === role) return true;
    const tag = el.tagName.toLowerCase();
    switch (role) {
      case "button": return tag === "button" || (tag === "input" && (el as HTMLInputElement).type === "button");
      case "textbox": return tag === "textarea" || (tag === "input" && ["text","email","search","tel","url","","number"].includes((el as HTMLInputElement).type || ""));
      case "heading": return /^h[1-6]$/.test(tag);
      case "link": return tag === "a";
      case "generic": return ["div","span","section","article","main","aside","nav","header","footer","p"].includes(tag);
      case "listitem": return tag === "li";
      case "list": return tag === "ul" || tag === "ol";
      case "img": case "image": return tag === "img";
      case "code": return tag === "code" || tag === "pre";
      case "paragraph": return tag === "p";
      default: return false;
    }
  }

  private getAccessibleName(el: HTMLElement): string {
    // WAI-ARIA accessible name computation order:
    // 1. aria-label, 2. subtree content (textContent), 3. placeholder, 4. title
    return el.getAttribute("aria-label") ||
           el.textContent?.trim() ||
           (el as HTMLInputElement).placeholder ||
           el.title ||
           "";
  }

  // ─── Public API ───

  /** Start recording the event timeline */
  startRecording() {
    this.events = [];
    this.recording = true;
    this.startTime = Date.now();
    this.stepCount = 0;
    this.logEvent({ type: "recording-start" });
    console.log("[DEMO] Recording started");
  }

  /** Stop recording, return the event timeline */
  stopRecording(): DemoEvent[] {
    this.logEvent({ type: "recording-stop" });
    this.recording = false;
    this.clear();
    console.log(`[DEMO] Recording stopped — ${this.events.length} events`);
    return [...this.events];
  }

  /** Get the recorded events without stopping */
  getEvents(): DemoEvent[] {
    return [...this.events];
  }

  /** Announce a narrative step (shown as badge) */
  step(title: string) {
    this.stepCount++;
    this.ensureStepBadge();
    this.stepBadge!.textContent = `Step ${this.stepCount}: ${title}`;
    this.stepBadge!.style.opacity = "1";
    this.logEvent({ type: "step", text: title });
    console.log(`[DEMO STEP ${this.stepCount}] ${title}`);
  }

  /** Dim background, spotlight a specific element */
  spotlight(selector: string, text?: string) {
    const el = this.resolveEl(selector);
    if (!el) { console.warn(`[DEMO] spotlight: element not found: ${selector}`); return; }

    this.activeEl = el;
    el.scrollIntoView({ behavior: "smooth", block: "center" });

    this.ensureOverlay();
    const r = el.getBoundingClientRect();
    const pad = 8;
    this.overlay!.style.opacity = "1";
    this.overlay!.style.clipPath = `
      polygon(
        0 0, 100% 0, 100% 100%, 0 100%,
        0 ${r.top - pad}px,
        ${r.left - pad}px ${r.top - pad}px,
        ${r.left - pad}px ${r.bottom + pad}px,
        ${r.right + pad}px ${r.bottom + pad}px,
        ${r.right + pad}px ${r.top - pad}px,
        0 ${r.top - pad}px
      )
    `;

    // Pulse effect on the element
    el.style.transition = "box-shadow 200ms ease";
    el.style.boxShadow = "0 0 0 3px rgba(88,166,255,0.6)";

    if (text) this.annotate(selector, text);
    this.logEvent({ type: "spotlight", selector, text });
  }

  /** Brief green highlight pulse on an element */
  highlight(selector: string) {
    const el = this.resolveEl(selector);
    if (!el) return;

    el.style.transition = "box-shadow 150ms ease";
    el.style.boxShadow = "0 0 0 3px #4ade80";
    setTimeout(() => { el.style.boxShadow = ""; }, 800);
    this.logEvent({ type: "highlight", selector });
  }

  /** Show a tooltip near an element */
  annotate(selector: string, text: string) {
    const el = this.resolveEl(selector);
    if (!el) return;

    this.ensureTooltip();
    const r = el.getBoundingClientRect();
    this.tooltip!.textContent = text;
    this.tooltip!.style.opacity = "1";

    // Position below element, fallback to above if near bottom
    const tipHeight = 60;
    if (r.bottom + tipHeight + 20 > window.innerHeight) {
      this.tooltip!.style.left = `${r.left}px`;
      this.tooltip!.style.top = `${r.top - tipHeight - 10}px`;
    } else {
      this.tooltip!.style.left = `${r.left}px`;
      this.tooltip!.style.top = `${r.bottom + 10}px`;
    }
    this.logEvent({ type: "annotate", selector, text });
  }

  /** Show caption text (bottom bar, no speech) */
  caption(text: string) {
    this.ensureCaptionBar();
    this.captionBar!.textContent = text;
    this.captionBar!.style.opacity = "1";
    this.logEvent({ type: "caption", text });
  }

  /** Hide caption bar */
  hideCaption() {
    if (this.captionBar) this.captionBar.style.opacity = "0";
  }

  /** Speak text via TTS + show caption. Returns promise that resolves when speech ends. */
  async say(text: string): Promise<void> {
    this.caption(text);
    const duration = await this.speak(text);
    this.logEvent({ type: "say", text, duration });
    // Keep caption visible for 500ms after speech
    await this.wait(500);
    this.hideCaption();
  }

  /** Animate cursor to an element */
  async cursorTo(selector: string): Promise<void> {
    const el = this.resolveEl(selector);
    if (!el) return;

    this.ensureCursor();
    const r = el.getBoundingClientRect();
    const cx = r.left + r.width / 2 - 10;
    const cy = r.top + r.height / 2 - 10;

    this.cursorEl!.style.opacity = "1";
    this.cursorEl!.style.left = `${cx}px`;
    this.cursorEl!.style.top = `${cy}px`;

    this.logEvent({ type: "cursorTo", selector });
    await this.wait(450); // wait for transition
  }

  /** Hide cursor */
  hideCursor() {
    if (this.cursorEl) this.cursorEl.style.opacity = "0";
  }

  /** Wait for a given duration (ms) */
  wait(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  /** Pause the demo — returns a promise that resolves when resume() is called.
   *  Use this to let the agent snapshot the UI and decide next action. */
  pause(): Promise<void> {
    if (this.paused) return Promise.resolve();
    this.paused = true;
    this.logEvent({ type: "pause" });
    console.log("[DEMO] Paused — call demo.resume() to continue");
    return new Promise(resolve => { this.pauseResolve = resolve; });
  }

  /** Resume after a pause() */
  resume() {
    if (this.pauseResolve) {
      this.pauseResolve();
      this.pauseResolve = null;
    }
    this.paused = false;
    this.logEvent({ type: "resume" });
    console.log("[DEMO] Resumed");
  }

  /** Check if demo is currently paused */
  isPaused(): boolean {
    return this.paused;
  }

  /** Clear all overlays, tooltips, spotlight, cursor */
  clear() {
    if (this.overlay) { this.overlay.style.opacity = "0"; this.overlay.style.clipPath = "none"; }
    if (this.tooltip) this.tooltip.style.opacity = "0";
    if (this.captionBar) this.captionBar.style.opacity = "0";
    if (this.stepBadge) this.stepBadge.style.opacity = "0";
    if (this.cursorEl) this.cursorEl.style.opacity = "0";
    if (this.activeEl) { this.activeEl.style.boxShadow = ""; this.activeEl = null; }
    this.logEvent({ type: "clear" });
  }

  /** Remove all DOM elements (full cleanup) */
  destroy() {
    this.overlay?.remove(); this.overlay = null;
    this.tooltip?.remove(); this.tooltip = null;
    this.captionBar?.remove(); this.captionBar = null;
    this.stepBadge?.remove(); this.stepBadge = null;
    this.cursorEl?.remove(); this.cursorEl = null;
  }

  // ─── TTS Engine ───

  private speak(text: string): Promise<number> {
    return new Promise(resolve => {
      if (!("speechSynthesis" in window)) {
        // No TTS available — estimate duration
        const estimatedMs = text.length * 60;
        setTimeout(() => resolve(estimatedMs), estimatedMs);
        return;
      }

      const utterance = new SpeechSynthesisUtterance(text);
      utterance.rate = 0.95;
      utterance.pitch = 1;
      utterance.volume = 1;

      // Prefer a natural voice
      const voices = speechSynthesis.getVoices();
      const preferred = voices.find(v =>
        v.name.includes("Samantha") || v.name.includes("Daniel") ||
        v.name.includes("Karen") || v.name.includes("Google")
      ) || voices.find(v => v.lang.startsWith("en")) || voices[0];
      if (preferred) utterance.voice = preferred;

      const startTime = Date.now();
      utterance.onend = () => resolve(Date.now() - startTime);
      utterance.onerror = () => resolve(text.length * 60);

      speechSynthesis.speak(utterance);
    });
  }

  // ─── Export for post-processing ───

  /** Export events as SRT subtitle format */
  exportSRT(): string {
    const sayEvents = this.events.filter(e => e.type === "say" || e.type === "caption");
    return sayEvents.map((e, i) => {
      const start = this.formatSRTTime(e.t);
      const end = this.formatSRTTime(e.t + (e.duration || 3000));
      return `${i + 1}\n${start} --> ${end}\n${e.text}\n`;
    }).join("\n");
  }

  private formatSRTTime(ms: number): string {
    const s = Math.floor(ms / 1000);
    const m = Math.floor(s / 60);
    const h = Math.floor(m / 60);
    const remainder = ms % 1000;
    return `${String(h).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}:${String(s % 60).padStart(2, "0")},${String(remainder).padStart(3, "0")}`;
  }
}

// ─── Attach to window ───
const demo = new DemoRuntime();
(window as any).demo = demo;

export { DemoRuntime, demo };
export type { DemoEvent };
