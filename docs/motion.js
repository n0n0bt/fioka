// The page's motion, apart from the drum (drum.js) and the demo desktop
// (desktop.js). Nothing here runs when the visitor asks for reduced motion.
(() => {
  if (!window.gsap || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  if (window.ScrollTrigger) gsap.registerPlugin(ScrollTrigger);

  // The hero's copy settles in line by line, just before the drum slides up.
  gsap.from([".hero-logo", ".platform", "#hero-title", ".lede", ".actions", ".hint"], {
    y: 22,
    autoAlpha: 0,
    duration: 0.7,
    ease: "power3.out",
    stagger: 0.07,
    clearProps: "transform,opacity,visibility"
  });

  // The banner's glass ribs catch the light as the pointer crosses it.
  const logo = document.querySelector(".hero-logo");
  if (logo && matchMedia("(hover: hover)").matches) {
    const tiltX = gsap.quickTo(logo, "rotationY", { duration: 0.5, ease: "power3.out" });
    const tiltY = gsap.quickTo(logo, "rotationX", { duration: 0.5, ease: "power3.out" });
    gsap.set(logo, { transformPerspective: 700 });
    logo.addEventListener("pointermove", (event) => {
      const box = logo.getBoundingClientRect();
      tiltX(((event.clientX - box.left) / box.width - 0.5) * 14);
      tiltY(-((event.clientY - box.top) / box.height - 0.5) * 14);
    });
    logo.addEventListener("pointerleave", () => { tiltX(0); tiltY(0); });
  }

  if (!window.ScrollTrigger) return;

  // Each section rises in once, its parts one after another.
  gsap.utils.toArray("main > section:not(.stage)").forEach((section) => {
    const parts = section.matches(".feature")
      ? [...section.querySelectorAll(".feature-copy > *"), ...section.querySelectorAll(".feature-visual")]
      : [...section.children];
    gsap.from(parts, {
      y: 36,
      autoAlpha: 0,
      duration: 0.8,
      ease: "power3.out",
      stagger: 0.08,
      clearProps: "transform,opacity,visibility",
      scrollTrigger: { trigger: section, start: "top 82%", once: true }
    });
  });

  // The rows of shortcuts and tools tick in, a beat apart.
  gsap.utils.toArray(".keys, .kinds, .tools").forEach((list) => {
    gsap.from(list.children, {
      x: -14,
      autoAlpha: 0,
      duration: 0.5,
      ease: "power2.out",
      stagger: 0.05,
      clearProps: "transform,opacity,visibility",
      scrollTrigger: { trigger: list, start: "top 85%", once: true }
    });
  });
})();
