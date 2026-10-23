// Three small behaviours, each answering something the visitor does.

// 1. ⇧⌘V closes and reopens the hero's card bar, as it toggles the bar in the app.
const bar = document.querySelector(".bar");
document.addEventListener("keydown", (event) => {
  if (event.key.toLowerCase() !== "v" || !event.metaKey || !event.shiftKey) return;
  event.preventDefault();
  if (!bar) return;
  bar.classList.add("closing");
  bar.addEventListener("animationend", () => {
    bar.classList.remove("closing");
    // Restart the opening animation.
    bar.style.animation = "none";
    void bar.offsetWidth;
    bar.style.animation = "";
  }, { once: true });
  bar.scrollIntoView({ behavior: "smooth", block: "end" });
});

// 2. The wheel switcher: the keycaps, and the real modifier keys while the
//    section is on screen.
const wheels = {
  formats: { src: "assets/wheel-formats.png", alt: "The formats wheel: JPEG highlighted, with PDF, HEIC, BMP, TIFF and AVIF around it." },
  tools: { src: "assets/wheel-tools.png", alt: "The tools wheel: Compress highlighted, with 50%, 25%, Metadata, Text and Edit around it." },
  actions: { src: "assets/wheel-actions.png", alt: "The actions wheel: AirDrop highlighted, with Copy, Path, Zip and Terminal around it." }
};
const image = document.getElementById("wheel-image");
const caps = [...document.querySelectorAll(".cap")];

// Preload so switching never flashes.
Object.values(wheels).forEach(({ src }) => { new Image().src = src; });

function show(mode) {
  const wheel = wheels[mode];
  if (!wheel || !image || image.dataset.mode === mode) return;
  image.dataset.mode = mode;
  caps.forEach((cap) => cap.setAttribute("aria-pressed", String(cap.dataset.mode === mode)));
  image.classList.add("swapping");
  setTimeout(() => {
    image.src = wheel.src;
    image.alt = wheel.alt;
    image.classList.remove("swapping");
  }, 120);
}
caps.forEach((cap) => cap.addEventListener("click", () => show(cap.dataset.mode)));
if (image) image.dataset.mode = "formats";

let wheelInView = false;
const wheelSection = document.getElementById("wheel");
if (wheelSection && "IntersectionObserver" in window) {
  new IntersectionObserver(([entry]) => { wheelInView = entry.isIntersecting; }, { threshold: 0.4 })
    .observe(wheelSection);
}
document.addEventListener("keydown", (event) => {
  if (!wheelInView || event.repeat) return;
  const mode = { Shift: "formats", Meta: "tools", Control: "actions" }[event.key];
  if (mode) show(mode);
});

// 3. Copy buttons for the install commands.
document.querySelectorAll(".copy").forEach((button) => {
  button.addEventListener("click", async () => {
    const source = document.getElementById(button.dataset.copy);
    if (!source) return;
    try {
      await navigator.clipboard.writeText(source.textContent);
      button.textContent = "Copied";
    } catch {
      button.textContent = "Select and copy";
    }
    setTimeout(() => { button.textContent = "Copy"; }, 1600);
  });
});
