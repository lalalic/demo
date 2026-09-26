var __demoRuntime = (() => {
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // runtimes/demo-runtime.ts
  var demo_runtime_exports = {};
  __export(demo_runtime_exports, {
    DemoRuntime: () => DemoRuntime,
    demo: () => demo
  });
  var DemoRuntime = class {
    overlay = null;
    tooltip = null;
    captionBar = null;
    stepBadge = null;
    cursorEl = null;
    activeEl = null;
    events = [];
    recording = false;
    startTime = 0;
    stepCount = 0;
    pauseResolve = null;
    paused = false;
    // ─── Initialization ───
    ensureOverlay() {
      if (this.overlay) return;
      this.overlay = document.createElement("div");
      this.overlay.id = "__demo_overlay";
      Object.assign(this.overlay.style, {
        position: "fixed",
        inset: "0",
        background: "rgba(0,0,0,0.55)",
        zIndex: "999998",
        pointerEvents: "none",
        transition: "clip-path 300ms ease, opacity 300ms ease",
        opacity: "0"
      });
      document.body.appendChild(this.overlay);
    }
    ensureTooltip() {
      if (this.tooltip) return;
      this.tooltip = document.createElement("div");
      this.tooltip.id = "__demo_tooltip";
      Object.assign(this.tooltip.style, {
        position: "fixed",
        maxWidth: "300px",
        padding: "10px 14px",
        background: "#111",
        color: "#fff",
        borderRadius: "8px",
        fontSize: "13px",
        lineHeight: "1.4",
        zIndex: "1000000",
        pointerEvents: "none",
        opacity: "0",
        transition: "opacity 200ms ease",
        boxShadow: "0 4px 12px rgba(0,0,0,0.4)"
      });
      document.body.appendChild(this.tooltip);
    }
    ensureCaptionBar() {
      if (this.captionBar) return;
      this.captionBar = document.createElement("div");
      this.captionBar.id = "__demo_caption";
      Object.assign(this.captionBar.style, {
        position: "fixed",
        bottom: "40px",
        left: "50%",
        transform: "translateX(-50%)",
        maxWidth: "70%",
        padding: "12px 24px",
        background: "rgba(0,0,0,0.75)",
        color: "#fff",
        borderRadius: "12px",
        fontSize: "16px",
        lineHeight: "1.5",
        textAlign: "center",
        zIndex: "1000001",
        pointerEvents: "none",
        opacity: "0",
        transition: "opacity 250ms ease",
        backdropFilter: "blur(8px)",
        fontFamily: "-apple-system, system-ui, sans-serif"
      });
      document.body.appendChild(this.captionBar);
    }
    ensureStepBadge() {
      if (this.stepBadge) return;
      this.stepBadge = document.createElement("div");
      this.stepBadge.id = "__demo_step";
      Object.assign(this.stepBadge.style, {
        position: "fixed",
        top: "20px",
        left: "20px",
        padding: "6px 16px",
        background: "rgba(88,166,255,0.9)",
        color: "#fff",
        borderRadius: "20px",
        fontSize: "13px",
        fontWeight: "600",
        zIndex: "1000001",
        pointerEvents: "none",
        opacity: "0",
        transition: "opacity 250ms ease",
        fontFamily: "-apple-system, system-ui, sans-serif"
      });
      document.body.appendChild(this.stepBadge);
    }
    ensureCursor() {
      if (this.cursorEl) return;
      this.cursorEl = document.createElement("div");
      this.cursorEl.id = "__demo_cursor";
      Object.assign(this.cursorEl.style, {
        position: "fixed",
        width: "20px",
        height: "20px",
        borderRadius: "50%",
        background: "rgba(255,100,100,0.7)",
        border: "2px solid rgba(255,255,255,0.8)",
        zIndex: "1000002",
        pointerEvents: "none",
        opacity: "0",
        transition: "left 400ms ease, top 400ms ease, opacity 200ms ease",
        boxShadow: "0 0 8px rgba(255,100,100,0.5)"
      });
      document.body.appendChild(this.cursorEl);
    }
    logEvent(event) {
      if (!this.recording) return;
      this.events.push({ t: Date.now() - this.startTime, ...event });
    }
    resolveEl(selector) {
      if (selector.startsWith("@")) {
        const refId = selector.slice(1);
        const tagged = document.querySelector(`[data-demo-ref="${refId}"]`);
        if (tagged) return tagged;
        const ext = document.querySelector(`[data-ref="${refId}"]`);
        if (ext) return ext;
        console.warn(`[DEMO] @${refId} not mapped. Call demo.mapRefs() or demo.tagRef("${refId}", "cssSelector") first.`);
        return null;
      }
      return document.querySelector(selector);
    }
    // ─── Ref Mapping ───
    /** Explicitly tag a DOM element with a ref ID for @ref resolution */
    tagRef(refId, cssSelector) {
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
    mapRefs(refs) {
      document.querySelectorAll("[data-demo-ref]").forEach(
        (el) => el.removeAttribute("data-demo-ref")
      );
      const allEls = [];
      const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
      let node;
      while (node = walker.nextNode()) allEls.push(node);
      const used = /* @__PURE__ */ new Set();
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
    findByRoleAndName(elements, role, name, used) {
      const normName = name.replace(/\s+/g, " ").trim();
      for (const el of elements) {
        if (used.has(el)) continue;
        if (!this.matchesRole(el, role)) continue;
        const accName = this.getAccessibleName(el);
        const normAccName = accName.replace(/\s+/g, " ").trim();
        if (normAccName === normName || normName.length > 10 && normAccName.startsWith(normName)) {
          return el;
        }
      }
      return null;
    }
    matchesRole(el, role) {
      const explicit = el.getAttribute("role");
      if (explicit === role) return true;
      const tag = el.tagName.toLowerCase();
      switch (role) {
        case "button":
          return tag === "button" || tag === "input" && el.type === "button";
        case "textbox":
          return tag === "textarea" || tag === "input" && ["text", "email", "search", "tel", "url", "", "number"].includes(el.type || "");
        case "heading":
          return /^h[1-6]$/.test(tag);
        case "link":
          return tag === "a";
        case "generic":
          return ["div", "span", "section", "article", "main", "aside", "nav", "header", "footer", "p"].includes(tag);
        case "listitem":
          return tag === "li";
        case "list":
          return tag === "ul" || tag === "ol";
        case "img":
        case "image":
          return tag === "img";
        case "code":
          return tag === "code" || tag === "pre";
        case "paragraph":
          return tag === "p";
        default:
          return false;
      }
    }
    getAccessibleName(el) {
      return el.getAttribute("aria-label") || el.textContent?.trim() || el.placeholder || el.title || "";
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
    stopRecording() {
      this.logEvent({ type: "recording-stop" });
      this.recording = false;
      this.clear();
      console.log(`[DEMO] Recording stopped \u2014 ${this.events.length} events`);
      return [...this.events];
    }
    /** Get the recorded events without stopping */
    getEvents() {
      return [...this.events];
    }
    /** Announce a narrative step (shown as badge) */
    step(title) {
      this.stepCount++;
      this.ensureStepBadge();
      this.stepBadge.textContent = `Step ${this.stepCount}: ${title}`;
      this.stepBadge.style.opacity = "1";
      this.logEvent({ type: "step", text: title });
      console.log(`[DEMO STEP ${this.stepCount}] ${title}`);
    }
    /** Dim background, spotlight a specific element */
    spotlight(selector, text) {
      const el = this.resolveEl(selector);
      if (!el) {
        console.warn(`[DEMO] spotlight: element not found: ${selector}`);
        return;
      }
      this.activeEl = el;
      el.scrollIntoView({ behavior: "smooth", block: "center" });
      this.ensureOverlay();
      const r = el.getBoundingClientRect();
      const pad = 8;
      this.overlay.style.opacity = "1";
      this.overlay.style.clipPath = `
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
      el.style.transition = "box-shadow 200ms ease";
      el.style.boxShadow = "0 0 0 3px rgba(88,166,255,0.6)";
      if (text) this.annotate(selector, text);
      this.logEvent({ type: "spotlight", selector, text });
    }
    /** Brief green highlight pulse on an element */
    highlight(selector) {
      const el = this.resolveEl(selector);
      if (!el) return;
      el.style.transition = "box-shadow 150ms ease";
      el.style.boxShadow = "0 0 0 3px #4ade80";
      setTimeout(() => {
        el.style.boxShadow = "";
      }, 800);
      this.logEvent({ type: "highlight", selector });
    }
    /** Show a tooltip near an element */
    annotate(selector, text) {
      const el = this.resolveEl(selector);
      if (!el) return;
      this.ensureTooltip();
      const r = el.getBoundingClientRect();
      this.tooltip.textContent = text;
      this.tooltip.style.opacity = "1";
      const tipHeight = 60;
      if (r.bottom + tipHeight + 20 > window.innerHeight) {
        this.tooltip.style.left = `${r.left}px`;
        this.tooltip.style.top = `${r.top - tipHeight - 10}px`;
      } else {
        this.tooltip.style.left = `${r.left}px`;
        this.tooltip.style.top = `${r.bottom + 10}px`;
      }
      this.logEvent({ type: "annotate", selector, text });
    }
    /** Show caption text (bottom bar, no speech) */
    caption(text) {
      this.ensureCaptionBar();
      this.captionBar.textContent = text;
      this.captionBar.style.opacity = "1";
      this.logEvent({ type: "caption", text });
    }
    /** Hide caption bar */
    hideCaption() {
      if (this.captionBar) this.captionBar.style.opacity = "0";
    }
    /** Speak text via TTS + show caption. Returns promise that resolves when speech ends. */
    async say(text) {
      this.caption(text);
      const duration = await this.speak(text);
      this.logEvent({ type: "say", text, duration });
      await this.wait(500);
      this.hideCaption();
    }
    /** Animate cursor to an element */
    async cursorTo(selector) {
      const el = this.resolveEl(selector);
      if (!el) return;
      this.ensureCursor();
      const r = el.getBoundingClientRect();
      const cx = r.left + r.width / 2 - 10;
      const cy = r.top + r.height / 2 - 10;
      this.cursorEl.style.opacity = "1";
      this.cursorEl.style.left = `${cx}px`;
      this.cursorEl.style.top = `${cy}px`;
      this.logEvent({ type: "cursorTo", selector });
      await this.wait(450);
    }
    /** Hide cursor */
    hideCursor() {
      if (this.cursorEl) this.cursorEl.style.opacity = "0";
    }
    /** Wait for a given duration (ms) */
    wait(ms) {
      return new Promise((resolve) => setTimeout(resolve, ms));
    }
    /** Pause the demo — returns a promise that resolves when resume() is called.
     *  Use this to let the agent snapshot the UI and decide next action. */
    pause() {
      if (this.paused) return Promise.resolve();
      this.paused = true;
      this.logEvent({ type: "pause" });
      console.log("[DEMO] Paused \u2014 call demo.resume() to continue");
      return new Promise((resolve) => {
        this.pauseResolve = resolve;
      });
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
    isPaused() {
      return this.paused;
    }
    /** Clear all overlays, tooltips, spotlight, cursor */
    clear() {
      if (this.overlay) {
        this.overlay.style.opacity = "0";
        this.overlay.style.clipPath = "none";
      }
      if (this.tooltip) this.tooltip.style.opacity = "0";
      if (this.captionBar) this.captionBar.style.opacity = "0";
      if (this.stepBadge) this.stepBadge.style.opacity = "0";
      if (this.cursorEl) this.cursorEl.style.opacity = "0";
      if (this.activeEl) {
        this.activeEl.style.boxShadow = "";
        this.activeEl = null;
      }
      this.logEvent({ type: "clear" });
    }
    /** Remove all DOM elements (full cleanup) */
    destroy() {
      this.overlay?.remove();
      this.overlay = null;
      this.tooltip?.remove();
      this.tooltip = null;
      this.captionBar?.remove();
      this.captionBar = null;
      this.stepBadge?.remove();
      this.stepBadge = null;
      this.cursorEl?.remove();
      this.cursorEl = null;
    }
    // ─── TTS Engine ───
    speak(text) {
      return new Promise((resolve) => {
        if (!("speechSynthesis" in window)) {
          const estimatedMs = text.length * 60;
          setTimeout(() => resolve(estimatedMs), estimatedMs);
          return;
        }
        const utterance = new SpeechSynthesisUtterance(text);
        utterance.rate = 0.95;
        utterance.pitch = 1;
        utterance.volume = 1;
        const voices = speechSynthesis.getVoices();
        const preferred = voices.find(
          (v) => v.name.includes("Samantha") || v.name.includes("Daniel") || v.name.includes("Karen") || v.name.includes("Google")
        ) || voices.find((v) => v.lang.startsWith("en")) || voices[0];
        if (preferred) utterance.voice = preferred;
        const startTime = Date.now();
        utterance.onend = () => resolve(Date.now() - startTime);
        utterance.onerror = () => resolve(text.length * 60);
        speechSynthesis.speak(utterance);
      });
    }
    // ─── Export for post-processing ───
    /** Export events as SRT subtitle format */
    exportSRT() {
      const sayEvents = this.events.filter((e) => e.type === "say" || e.type === "caption");
      return sayEvents.map((e, i) => {
        const start = this.formatSRTTime(e.t);
        const end = this.formatSRTTime(e.t + (e.duration || 3e3));
        return `${i + 1}
${start} --> ${end}
${e.text}
`;
      }).join("\n");
    }
    formatSRTTime(ms) {
      const s = Math.floor(ms / 1e3);
      const m = Math.floor(s / 60);
      const h = Math.floor(m / 60);
      const remainder = ms % 1e3;
      return `${String(h).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}:${String(s % 60).padStart(2, "0")},${String(remainder).padStart(3, "0")}`;
    }
  };
  var demo = new DemoRuntime();
  window.demo = demo;
  return __toCommonJS(demo_runtime_exports);
})();
