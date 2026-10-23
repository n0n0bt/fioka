// A pretend Mac desktop for trying the drop wheel. Drag a file with the mouse
// as in Finder; press ⇧, ⌘ or ⌃ while holding it and the wheel opens under
// the cursor; let go over a slice. The new file appears next to the original,
// as the app saves it. Images convert for real, in the browser; other kinds
// show what Fioka would save.
//
// The drag is pointer events rather than the browser's native drag and drop,
// so real key presses arrive while the file is held, exactly as in the app.

(() => {
  const desktop = document.getElementById("desktop");
  if (!desktop) return;

  const filesLayer = document.getElementById("files");
  const panel = document.getElementById("live-wheel");
  const svg = document.getElementById("wheel-svg");
  const caption = document.getElementById("live-caption");
  const toast = document.getElementById("toast");
  const toastText = document.getElementById("toast-text");
  const coach = document.getElementById("coach");

  // Geometry from DropWheelView: outer radius 190, hub 70, rounded slices.
  const SIZE = 420, C = SIZE / 2, OUTER = 190, INNER = 70, GAP = 7, CORNER = 12;
  const ICON_W = 112, ICON_H = 112;

  // ---------- Clock ----------

  const clock = document.getElementById("clock");
  const tick = () => {
    clock.textContent = new Date().toLocaleString(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" });
  };
  tick();
  setInterval(tick, 30_000);

  // ---------- Files ----------

  let nextId = 1;
  const files = [];

  const colours = { pdf: "#e5484d", mov: "#6e6bff", mp4: "#6e6bff", m4v: "#6e6bff", gif: "#3cc8e0", wav: "#f76ba8", m4a: "#f76ba8", aiff: "#f76ba8", flac: "#f76ba8", alac: "#f76ba8", docx: "#2f6feb", doc: "#2f6feb", rtf: "#2f6feb", odt: "#2f6feb", html: "#e5893b", txt: "#6b6880", zip: "#8a8799", heic: "#3cc8e0", avif: "#3cc8e0" };

  // A document icon: a page with a folded corner and a coloured type band.
  function docIcon(ext) {
    const colour = colours[ext] || "#6b6880";
    const label = ext.toUpperCase().slice(0, 4);
    return `<svg viewBox="0 0 52 64" width="52" height="64" aria-hidden="true">
      <path d="M4 2h30l14 14v44a2 2 0 0 1-2 2H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2z" fill="#fff" stroke="#d6d3e3"/>
      <path d="M34 2v12a2 2 0 0 0 2 2h12" fill="#ecebf3" stroke="#d6d3e3"/>
      <rect x="2" y="40" width="46" height="15" fill="${colour}"/>
      <text x="25" y="51" text-anchor="middle" font-family="-apple-system, sans-serif" font-size="10" font-weight="700" fill="#fff">${label}</text>
      <rect x="9" y="14" width="20" height="3" rx="1.5" fill="#dcdae6"/>
      <rect x="9" y="21" width="30" height="3" rx="1.5" fill="#dcdae6"/>
      <rect x="9" y="28" width="26" height="3" rx="1.5" fill="#dcdae6"/>
    </svg>`;
  }

  const extOfName = (name) => (name.includes(".") ? name.split(".").pop().toLowerCase() : "");

  function kindOf(type, name = "") {
    const ext = extOfName(name);
    if ((type || "").startsWith("image/") || ["heic", "png", "jpg", "jpeg", "webp", "gif", "tiff", "bmp", "avif"].includes(ext)) return "image";
    if ((type || "").startsWith("video/") || ["mov", "mp4", "m4v"].includes(ext)) return "video";
    if ((type || "").startsWith("audio/") || ["wav", "m4a", "aiff", "flac", "mp3"].includes(ext)) return "audio";
    if (type === "application/pdf" || ext === "pdf") return "pdf";
    if (["doc", "docx", "rtf", "odt", "html", "txt"].includes(ext)) return "document";
    if (ext === "zip") return "archive";
    return "other";
  }

  function addFile({ name, kind, file = null, thumb = null, x, y, isNew = false }) {
    const entry = { id: nextId++, name, kind: kind || kindOf(file?.type, name), file, thumb, x, y };
    const node = document.createElement("button");
    node.type = "button";
    node.className = "file";
    node.setAttribute("role", "option");
    node.dataset.id = entry.id;
    node.innerHTML = `<span class="thumb"></span><span class="label"></span>`;
    const thumbBox = node.querySelector(".thumb");
    if (thumb) {
      const img = document.createElement("img");
      img.src = thumb;
      img.alt = "";
      img.draggable = false;
      thumbBox.append(img);
    } else {
      thumbBox.innerHTML = docIcon(extOfName(name));
    }
    node.querySelector(".label").textContent = name;
    node.setAttribute("aria-label", name);
    if (isNew) node.classList.add("new");
    entry.node = node;
    files.push(entry);
    filesLayer.append(node);
    position(entry);
    return entry;
  }

  function position(entry) {
    entry.node.style.left = `${entry.x}px`;
    entry.node.style.top = `${entry.y}px`;
  }

  function select(entry) {
    files.forEach((f) => f.node.classList.toggle("selected", f === entry));
    files.forEach((f) => f.node.setAttribute("aria-selected", String(f === entry)));
  }

  // Lay out the starting files down the right edge, as macOS does.
  async function seed() {
    const right = filesLayer.clientWidth - ICON_W - 14;
    const perColumn = Math.max(1, Math.floor((filesLayer.clientHeight - 20) / (ICON_H - 4)));
    const photoBlob = await (await fetch("assets/sample-photo.jpg")).blob();
    const photo = new File([photoBlob], "photo.jpg", { type: "image/jpeg" });
    const start = [
      { name: "photo.jpg", file: photo, thumb: URL.createObjectURL(photo) },
      { name: "Q3 Report.pdf" },
      { name: "holiday.mov" },
      { name: "podcast.wav" },
      { name: "Notes.docx" }
    ];
    start.forEach((f, i) => addFile({
      ...f,
      x: right - Math.floor(i / perColumn) * (ICON_W - 8),
      y: 14 + (i % perColumn) * (ICON_H - 4)
    }));
    setCoach("start");
  }

  // Next to the original, in the first free spot, as the app writes beside it.
  function freeSpotNear(entry) {
    const maxX = filesLayer.clientWidth - ICON_W, maxY = filesLayer.clientHeight - ICON_H;
    const offsets = [[-1, 0], [-2, 0], [-1, 1], [-2, 1], [-1, -1], [-3, 0], [-3, 1], [0, 1], [-2, -1], [-4, 0]];
    for (const [dx, dy] of offsets) {
      const x = entry.x + dx * ICON_W, y = entry.y + dy * (ICON_H - 4);
      if (x < 0 || y < 0 || x > maxX || y > maxY) continue;
      if (files.every((f) => Math.hypot(f.x - x, f.y - y) > 70)) return { x, y };
    }
    return { x: Math.max(0, entry.x - ICON_W), y: Math.min(maxY, entry.y + 20) };
  }

  // ---------- What each wheel offers ----------

  const canWebP = (() => {
    const c = document.createElement("canvas");
    c.width = c.height = 1;
    return c.toDataURL("image/webp").startsWith("data:image/webp");
  })();

  const appOnly = (title, caption, { ext = null, suffix = null, verb = null } = {}) => ({ title, caption, appOnly: true, ext, suffix, verb });

  function segmentsFor(kind, mode) {
    if (mode === "actions") return [
      kind === "image" ? { title: "Copy", caption: "Copy to the clipboard", run: copyImage } : appOnly("Copy", "Copy to the clipboard", { verb: "puts it on your clipboard" }),
      appOnly("AirDrop", "Send with AirDrop", { verb: "sends it with AirDrop" }),
      appOnly("Path", "Copy path", { verb: "copies its path" }),
      appOnly("Zip", "Compress into a zip", { ext: "zip" }),
      appOnly("Terminal", "Open in Terminal", { verb: "opens its folder in Terminal" })
    ];
    if (kind === "image") {
      if (mode === "formats") return [
        { title: "PNG", caption: "Convert to PNG", run: (e) => convert(e, "image/png") },
        { title: "JPEG", caption: "Convert to JPEG", run: (e) => convert(e, "image/jpeg", { quality: 0.9 }) },
        ...(canWebP ? [{ title: "WebP", caption: "Convert to WebP", run: (e) => convert(e, "image/webp", { quality: 0.9 }) }] : []),
        { title: "PDF", caption: "Convert to PDF", run: toPDF },
        appOnly("HEIC", "Convert to HEIC", { ext: "heic" }),
        appOnly("AVIF", "Convert to AVIF", { ext: "avif" })
      ];
      return [
        { title: "Compress", caption: "Compress", run: compress },
        { title: "50%", caption: "Resize to 50%", run: (e) => convert(e, sameType(e), { scale: 0.5, suffix: "50%" }) },
        { title: "25%", caption: "Resize to 25%", run: (e) => convert(e, sameType(e), { scale: 0.25, suffix: "25%" }) },
        { title: "Metadata", caption: "Remove metadata", run: (e) => convert(e, sameType(e), { quality: 0.95, suffix: "clean" }) },
        appOnly("Text", "Copy the text in it", { verb: "copies the text in the image to your clipboard" }),
        appOnly("Edit", "Crop, annotate, add a background", { verb: "opens it in the screenshot editor" })
      ];
    }
    const formats = {
      video: ["MP4", "MOV", "M4V", "GIF", "M4A"],
      audio: ["M4A", "WAV", "AIFF", "FLAC", "ALAC"],
      pdf: ["PNG", "JPEG", "TXT", "DOCX", "RTF"],
      document: ["PDF", "DOCX", "RTF", "ODT", "HTML", "TXT"],
      archive: ["Extract"]
    };
    const tools = {
      video: [["Compress", "Compress (HEVC)", "compressed"], ["720p", "Resize to 720p", "720p"], ["Mute", "Remove the sound", "muted"], ["Frame", "Save a still frame", "frame", "png"]],
      audio: [["Compress", "Compress (AAC)", "compressed", "m4a"], ["Mono", "Mix down to mono", "mono"], ["Normalize", "Normalize loudness", "normalized"]],
      pdf: [["Compress", "Compress", "compressed"], ["Split", "One PDF per page", "1"], ["Rotate", "Rotate 90°", "rotated"]],
      document: [["Text", "Copy the text", null]]
    };
    if (mode === "formats" && formats[kind]) {
      return formats[kind]
        .filter((f) => f.toLowerCase() !== extOfName(current?.name || ""))
        .map((f) => f === "Extract" ? appOnly(f, "Extract here", { verb: "extracts it into a folder" }) : appOnly(f, `Convert to ${f}`, { ext: f.toLowerCase() === "jpeg" ? "jpeg" : f.toLowerCase() }));
    }
    if (mode === "tools" && tools[kind]) {
      return tools[kind].map(([t, c, suffix, ext]) => appOnly(t, c, suffix ? { suffix, ext } : { verb: "copies its text to your clipboard" }));
    }
    return [];
  }

  // ---------- Drawing the wheel (same geometry as the app) ----------

  const NS = "http://www.w3.org/2000/svg";
  const el = (name, attrs = {}) => {
    const node = document.createElementNS(NS, name);
    Object.entries(attrs).forEach(([k, v]) => node.setAttribute(k, v));
    return node;
  };

  function slicePath(start, end) {
    const inset = GAP / 2 + CORNER;
    const outer = OUTER - 6 - inset, inner = INNER + 6 + inset;
    const po = Math.asin(Math.min(1, inset / outer)), pi = Math.asin(Math.min(1, inset / inner));
    const pt = (a, r) => [C + Math.sin(a) * r, C - Math.cos(a) * r];
    const [ox1, oy1] = pt(start + po, outer), [ox2, oy2] = pt(end - po, outer);
    const [ix1, iy1] = pt(end - pi, inner), [ix2, iy2] = pt(start + pi, inner);
    const large = end - start - 2 * po > Math.PI ? 1 : 0;
    return `M${ox1} ${oy1} A${outer} ${outer} 0 ${large} 1 ${ox2} ${oy2} L${ix1} ${iy1} A${inner} ${inner} 0 ${large} 0 ${ix2} ${iy2} Z`;
  }

  function draw() {
    svg.replaceChildren();
    const defs = el("defs");
    const gradient = el("linearGradient", { id: "lit", gradientUnits: "userSpaceOnUse", x1: 20, y1: 20, x2: 400, y2: 400 });
    [["0", "#f76ba8"], ["0.55", "#6e6bff"], ["1", "#3cc8e0"]].forEach(([o, c]) => gradient.append(el("stop", { offset: o, "stop-color": c })));
    const shadow = el("filter", { id: "lift", x: "-30%", y: "-30%", width: "160%", height: "160%" });
    shadow.append(el("feDropShadow", { dx: 0, dy: 10, stdDeviation: 16, "flood-color": "#000", "flood-opacity": 0.32 }));
    defs.append(gradient, shadow);
    svg.append(defs, el("circle", { cx: C, cy: C, r: OUTER, fill: "#eae8f3", filter: "url(#lift)" }));

    const n = wheel.segments.length, step = (2 * Math.PI) / Math.max(n, 1);
    wheel.segments.forEach((segment, i) => {
      const lit = i === wheel.hovered;
      const fill = lit ? "url(#lit)" : "#fbfaff";
      const group = el("g", { class: "slice" });
      if (n === 1) {
        group.append(el("circle", { cx: C, cy: C, r: (OUTER + INNER) / 2, fill: "none", stroke: fill, "stroke-width": OUTER - INNER - 12 - GAP }));
      } else {
        group.append(el("path", { d: slicePath(i * step - step / 2, i * step + step / 2), fill, stroke: fill, "stroke-width": CORNER * 2, "stroke-linejoin": "round" }));
      }
      const mid = i * step, r = (INNER + OUTER) / 2 + 6;
      const isFormat = wheel.mode === "formats";
      const label = el("text", {
        x: C + Math.sin(mid) * r, y: C - Math.cos(mid) * r, "text-anchor": "middle", "dominant-baseline": "central",
        "font-size": isFormat ? 20 : 12, "font-weight": isFormat ? 800 : 700, "letter-spacing": isFormat ? 0.4 : 0.8,
        fill: lit ? "#fff" : "#17151f", opacity: segment.appOnly && !lit ? 0.55 : 1
      });
      label.textContent = segment.title.toUpperCase();
      group.append(label);
      svg.append(group);
    });

    svg.append(el("circle", { cx: C, cy: C, r: INNER - 4, fill: "#f6f5fa" }));
    const now = wheel.segments[wheel.hovered];
    if (now) {
      svg.append(el("rect", { x: C - 56, y: C - 17, width: 112, height: 34, rx: 17, fill: "#fff" }));
      const hub = el("text", { x: C, y: C, "text-anchor": "middle", "dominant-baseline": "central", "font-size": 12, "font-weight": 700, "letter-spacing": 0.8, fill: "#17151f" });
      hub.textContent = now.title.toUpperCase();
      svg.append(hub);
      caption.textContent = now.appOnly ? `${now.caption} (in the app)` : now.caption;
    }
  }

  // ---------- The wheel's state ----------

  const wheel = { open: false, mode: null, segments: [], hovered: 0, keyboard: false, tap: false };
  const touch = matchMedia("(hover: none) and (pointer: coarse)").matches;
  let current = null;   // the file being dragged, or chosen with the keyboard

  function openWheel(mode, clientX, clientY) {
    const segments = segmentsFor(current.kind, mode);
    if (!segments.length) {
      notify(`Fioka has no ${mode} for ${current.name}.`);
      return;
    }
    const reopening = wheel.open;
    Object.assign(wheel, { open: true, mode, segments, hovered: 0 });
    if (!reopening) placeWheel(clientX, clientY);
    panel.hidden = false;
    draw();
    setCoach("wheel");
  }

  function closeWheel() {
    wheel.open = false;
    wheel.keyboard = false;
    wheel.tap = false;
    panel.style.pointerEvents = "";
    panel.hidden = true;
  }

  // Phones: tap a file, then a key, then a slice.
  function openForTap(mode) {
    const entry = current || files.find((f) => f.node.classList.contains("selected"));
    if (!entry) { setCoach("start"); return; }
    current = entry;
    const box = entry.node.getBoundingClientRect();
    wheel.tap = true;
    openWheel(mode, box.left + box.width / 2, box.top + box.height / 2);
    panel.style.pointerEvents = "auto";
  }

  svg.addEventListener("pointermove", (e) => { if (wheel.tap) hover(e.clientX, e.clientY); });
  svg.addEventListener("click", (e) => {
    if (!wheel.tap || !hover(e.clientX, e.clientY)) return;
    const segment = wheel.segments[wheel.hovered];
    const entry = current;
    closeWheel();
    run(segment, entry);
  });
  desktop.addEventListener("pointerdown", (e) => {
    if (wheel.tap && !panel.contains(e.target) && !e.target.closest(".keystrip")) closeWheel();
  }, true);

  // Centred on the cursor, kept inside the desktop, scaled down if it is small.
  function placeWheel(clientX, clientY) {
    const box = desktop.getBoundingClientRect();
    const scale = Math.min(1, (box.height - 40) / 480, (box.width - 20) / 430);
    desktop.style.setProperty("--wheel-scale", scale);
    const halfW = 210 * scale, halfH = 235 * scale;
    const x = Math.min(Math.max(clientX - box.left, halfW), box.width - halfW);
    const y = Math.min(Math.max(clientY - box.top, halfH + 30), box.height - halfH);
    panel.style.left = `${x}px`;
    panel.style.top = `${y}px`;
  }

  // Which slice the cursor is over, clockwise from twelve as in DropWheel.
  // In the hub the slice doesn't change, so letting go there runs it.
  function hover(clientX, clientY) {
    const box = svg.getBoundingClientRect();
    const scale = box.width / SIZE;
    const dx = clientX - (box.left + box.width / 2), dy = (box.top + box.height / 2) - clientY;
    const distance = Math.hypot(dx, dy) / scale;
    if (distance < INNER) return true;
    if (distance > OUTER + 40) return false;
    let angle = Math.atan2(dx, dy);
    if (angle < 0) angle += 2 * Math.PI;
    const step = (2 * Math.PI) / wheel.segments.length;
    const index = Math.floor((angle + step / 2) / step) % wheel.segments.length;
    if (index !== wheel.hovered) { wheel.hovered = index; draw(); }
    return true;
  }

  // ---------- Dragging, Finder style ----------

  let press = null;     // { entry, startX, startY, dragging, ghost, lastX, lastY }

  filesLayer.addEventListener("pointerdown", (e) => {
    const node = e.target.closest(".file");
    if (!node || e.button > 0) return;
    const entry = files.find((f) => f.id === Number(node.dataset.id));
    select(entry);
    current = entry;
    press = { entry, startX: e.clientX, startY: e.clientY, lastX: e.clientX, lastY: e.clientY, dragging: false, pointerType: e.pointerType };
    // Keep receiving moves while the cursor is outside the icon.
    try { node.setPointerCapture(e.pointerId); } catch { /* synthetic or lost pointer */ }
  });

  filesLayer.addEventListener("pointermove", (e) => {
    if (!press) return;
    press.lastX = e.clientX;
    press.lastY = e.clientY;
    if (!press.dragging && Math.hypot(e.clientX - press.startX, e.clientY - press.startY) > 5) {
      press.dragging = true;
      current = press.entry;
      press.entry.node.classList.add("lifted");
      const ghost = press.entry.node.cloneNode(true);
      ghost.classList.remove("lifted", "new");
      ghost.classList.add("file", "ghost");
      document.body.append(ghost);
      press.ghost = ghost;
      setCoach("dragging");
    }
    if (press.dragging) {
      press.ghost.style.left = `${e.clientX}px`;
      press.ghost.style.top = `${e.clientY}px`;
      if (wheel.open) hover(e.clientX, e.clientY);
    }
  });

  filesLayer.addEventListener("pointerup", (e) => finishDrag(e.clientX, e.clientY));
  filesLayer.addEventListener("pointercancel", () => cancelDrag());

  function finishDrag(x, y) {
    if (!press) return;
    const { entry, dragging } = press;
    press.ghost?.remove();
    entry.node.classList.remove("lifted");
    const pointerType = press.pointerType;
    press = null;
    if (!dragging) {
      // Double-tap on touchscreens, where dblclick is unreliable.
      if (pointerType === "touch") {
        const now = Date.now();
        if (lastTap.entry === entry && now - lastTap.time < 400) download(entry);
        lastTap = { entry, time: now };
        if (stage === "start") setCoach("picked");
      }
      return;
    }

    if (wheel.open && hover(x, y)) {
      const segment = wheel.segments[wheel.hovered];
      closeWheel();
      run(segment, entry);
      return;
    }
    closeWheel();
    // Let go elsewhere: an ordinary move, as in Finder.
    const box = filesLayer.getBoundingClientRect();
    entry.x = Math.min(Math.max(x - box.left - ICON_W / 2, 0), box.width - ICON_W);
    entry.y = Math.min(Math.max(y - box.top - 36, 0), box.height - ICON_H);
    position(entry);
    setCoach(stage === "dragging" || stage === "wheel" ? "start" : stage);
  }

  function cancelDrag() {
    if (!press) return;
    press.ghost?.remove();
    press.entry.node.classList.remove("lifted");
    press = null;
    closeWheel();
  }

  // Keys: while a file is held, a newly pressed modifier opens or switches
  // the wheel. With the keyboard alone, tapping a modifier on a selected file
  // opens it there.
  const modeOf = { Shift: "formats", Meta: "tools", Control: "actions" };
  let tapCandidate = null;

  window.addEventListener("keydown", (e) => {
    const mode = modeOf[e.key];
    if (press?.dragging) {
      if (e.key === "Escape") { e.preventDefault(); cancelDrag(); return; }
      if (mode && !e.repeat) { e.preventDefault(); openWheel(mode, press.lastX, press.lastY); }
      return;
    }
    if (wheel.keyboard) {
      const step = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 }[e.key];
      if (step) {
        e.preventDefault();
        wheel.hovered = (wheel.hovered + step + wheel.segments.length) % wheel.segments.length;
        draw();
      } else if (e.key === "Enter") {
        e.preventDefault();
        const segment = wheel.segments[wheel.hovered];
        closeWheel();
        run(segment, current);
      } else if (e.key === "Escape") {
        closeWheel();
      } else if (mode && !e.repeat) {
        openWheel(mode, 0, 0);
      }
      return;
    }
    tapCandidate = mode && document.activeElement?.classList.contains("file") ? e.key : null;
  });

  window.addEventListener("keyup", (e) => {
    if (!tapCandidate || e.key !== tapCandidate) return;
    tapCandidate = null;
    const node = document.activeElement;
    const entry = files.find((f) => f.node === node);
    if (!entry) return;
    current = entry;
    select(entry);
    const box = node.getBoundingClientRect();
    wheel.keyboard = true;
    openWheel(modeOf[e.key], box.left + box.width / 2, box.top + box.height / 2);
  });

  // Touchscreens: tap an on-screen key with another finger while dragging.
  document.querySelectorAll(".touch-key").forEach((key) => {
    key.addEventListener("pointerdown", (e) => {
      e.preventDefault();
      if (press?.dragging) openWheel(key.dataset.mode, press.lastX, press.lastY);
      else openForTap(key.dataset.mode);
    });
  });

  // Double-click a converted file to save it.
  let lastTap = { entry: null, time: 0 };
  filesLayer.addEventListener("dblclick", (e) => {
    const node = e.target.closest(".file");
    const entry = node && files.find((f) => f.id === Number(node.dataset.id));
    if (entry) download(entry);
  });

  function download(entry) {
    if (entry.file && entry.made) {
      const link = document.createElement("a");
      link.href = URL.createObjectURL(entry.file);
      link.download = entry.name;
      link.click();
      notify(`Downloading ${entry.name}.`);
    } else if (entry.simulated) {
      notify(`${entry.name} is a stand-in: in this demo only images convert for real.`);
    }
  }

  // Your own files, dropped in from Finder, join the desktop.
  desktop.addEventListener("dragover", (e) => {
    if ([...(e.dataTransfer?.items || [])].some((i) => i.kind === "file")) e.preventDefault();
  });
  desktop.addEventListener("drop", (e) => {
    e.preventDefault();
    const box = filesLayer.getBoundingClientRect();
    [...e.dataTransfer.files].slice(0, 6).forEach((file, i) => {
      const kind = kindOf(file.type, file.name);
      addFile({
        name: file.name, kind, file, isNew: true,
        thumb: kind === "image" ? URL.createObjectURL(file) : null,
        x: Math.min(Math.max(e.clientX - box.left - ICON_W / 2 + i * 16, 0), box.width - ICON_W),
        y: Math.min(Math.max(e.clientY - box.top - 36 + i * 16, 0), box.height - ICON_H)
      });
    });
    notify("Now drag one, and press a key while you hold it.");
  });

  // ---------- Running a slice ----------

  const baseName = (name) => name.replace(/\.[^.]+$/, "");
  const nameFor = (entry, ext, suffix) => `${[baseName(entry.name), suffix].filter(Boolean).join(" ")}.${ext}`;
  const typeExt = { "image/png": "png", "image/jpeg": "jpeg", "image/webp": "webp" };
  const sameType = (entry) => typeExt[entry.file?.type] ? entry.file.type : "image/png";

  async function run(segment, entry) {
    if (segment.appOnly) {
      if (segment.ext || segment.suffix) {
        const name = nameFor(entry, segment.ext || extOfName(entry.name), segment.suffix);
        const spot = freeSpotNear(entry);
        const made = addFile({ name, x: spot.x, y: spot.y, isNew: true });
        made.simulated = true;
        notify(`Saved ${name} next to the original. In the app this is the real file; here only images convert.`);
      } else {
        notify(`In the app, this ${segment.verb}.`);
      }
      setCoach("done");
      return;
    }
    try {
      const result = await segment.run(entry);
      if (result?.blob) {
        const file = new File([result.blob], result.name, { type: result.blob.type });
        const spot = freeSpotNear(entry);
        const made = addFile({ name: result.name, kind: kindOf(file.type, result.name), file, thumb: result.thumb, x: spot.x, y: spot.y, isNew: true });
        made.made = true;
        select(made);
        notify(`${result.message || `Saved ${result.name} next to the original.`} ${touch ? "Double-tap" : "Double-click"} it to download.`);
      } else if (result?.message) {
        notify(result.message);
      }
      setCoach("done");
    } catch (error) {
      notify(`${error.message} Fioka itself reads HEIC and more.`);
    }
  }

  async function decode(entry) {
    try {
      return await createImageBitmap(entry.file, { imageOrientation: "from-image" });
    } catch {
      throw new Error("This browser can't open that image.");
    }
  }

  function canvasFor(bitmap, scale, opaque) {
    const canvas = document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(bitmap.width * scale));
    canvas.height = Math.max(1, Math.round(bitmap.height * scale));
    const ctx = canvas.getContext("2d");
    if (opaque) { ctx.fillStyle = "#fff"; ctx.fillRect(0, 0, canvas.width, canvas.height); }
    ctx.imageSmoothingQuality = "high";
    ctx.drawImage(bitmap, 0, 0, canvas.width, canvas.height);
    return canvas;
  }

  const toBlob = (canvas, type, quality) => new Promise((resolve) => canvas.toBlob(resolve, type, quality));

  async function convert(entry, type, { quality, scale = 1, suffix } = {}) {
    const bitmap = await decode(entry);
    const canvas = canvasFor(bitmap, scale, type === "image/jpeg");
    const blob = await toBlob(canvas, type, quality);
    return { blob, name: nameFor(entry, typeExt[type], suffix), thumb: URL.createObjectURL(blob) };
  }

  async function compress(entry) {
    const type = ["image/jpeg", "image/webp"].includes(entry.file.type) ? entry.file.type : "image/jpeg";
    const result = await convert(entry, type, { quality: 0.6, suffix: "compressed" });
    const saved = Math.round((1 - result.blob.size / entry.file.size) * 100);
    if (saved > 0) result.message = `Saved ${result.name}, ${saved}% smaller.`;
    return result;
  }

  async function copyImage(entry) {
    const bitmap = await decode(entry);
    const blob = await toBlob(canvasFor(bitmap, 1, false), "image/png");
    await navigator.clipboard.write([new ClipboardItem({ "image/png": blob })]);
    return { message: `Copied ${entry.name} to your clipboard.` };
  }

  // A one-page PDF around the image as a JPEG, written by hand.
  async function toPDF(entry) {
    const bitmap = await decode(entry);
    const canvas = canvasFor(bitmap, 1, true);
    const jpeg = new Uint8Array(await (await toBlob(canvas, "image/jpeg", 0.92)).arrayBuffer());
    const w = canvas.width, h = canvas.height;
    const encoder = new TextEncoder(), parts = [], offsets = [];
    let length = 0;
    const push = (chunk) => { const bytes = typeof chunk === "string" ? encoder.encode(chunk) : chunk; parts.push(bytes); length += bytes.length; };
    const object = (body) => { offsets.push(length); push(body); };
    push("%PDF-1.4\n");
    object("1 0 obj <</Type /Catalog /Pages 2 0 R>> endobj\n");
    object("2 0 obj <</Type /Pages /Kids [3 0 R] /Count 1>> endobj\n");
    object(`3 0 obj <</Type /Page /Parent 2 0 R /MediaBox [0 0 ${w} ${h}] /Resources <</XObject <</Im0 4 0 R>>>> /Contents 5 0 R>> endobj\n`);
    offsets.push(length);
    push(`4 0 obj <</Type /XObject /Subtype /Image /Width ${w} /Height ${h} /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length ${jpeg.length}>> stream\n`);
    push(jpeg);
    push("\nendstream endobj\n");
    const paint = `q ${w} 0 0 ${h} 0 0 cm /Im0 Do Q`;
    object(`5 0 obj <</Length ${paint.length}>> stream\n${paint}\nendstream endobj\n`);
    const xref = length;
    push(`xref\n0 6\n0000000000 65535 f \n${offsets.map((o) => `${String(o).padStart(10, "0")} 00000 n \n`).join("")}`);
    push(`trailer <</Size 6 /Root 1 0 R>>\nstartxref\n${xref}\n%%EOF\n`);
    return { blob: new Blob(parts, { type: "application/pdf" }), name: nameFor(entry, "pdf"), thumb: null };
  }

  // ---------- Notification and guide ----------

  let toastTimer;
  function notify(text) {
    toastText.textContent = text;
    toast.hidden = false;
    // Restart the slide-in for each new message.
    toast.style.animation = "none";
    void toast.offsetWidth;
    toast.style.animation = "";
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { toast.hidden = true; }, 6000);
  }

  let stage = "start", conversions = 0;
  const coachText = touch ? {
    start: "Tap photo.jpg",
    picked: "Now tap <kbd>⇧</kbd> for formats, or <kbd>⌘</kbd> for tools",
    dragging: "Tap <kbd>⇧</kbd> or <kbd>⌘</kbd> with another finger",
    wheel: "Tap a slice",
    done: "Double-tap the new file to save it, or try another key"
  } : {
    start: "Drag photo.jpg somewhere, and keep holding it",
    picked: "Drag it somewhere, and keep holding it",
    dragging: "Now press <kbd>⇧</kbd> for formats, or <kbd>⌘</kbd> for tools",
    wheel: "Let go over a slice",
    done: "Double-click the new file to save it, or try another key"
  };
  function setCoach(next) {
    stage = next;
    if (next === "done") conversions += 1;
    coach.innerHTML = conversions >= 3 && next !== "dragging" && next !== "wheel" ? "" : coachText[next];
  }

  // Only lay out the desktop once it has a size.
  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(([entry]) => {
      if (!entry.isIntersecting) return;
      observer.disconnect();
      seed();
    }, { rootMargin: "400px" });
    observer.observe(desktop);
  } else {
    seed();
  }
})();
