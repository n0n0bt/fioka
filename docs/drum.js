// The hero's card bar, live: the app's own cards on a drum, placed the way
// CardDrumView places them and turned with GSAP.
//
// The drum's position is one number, `pos`, the index of the card in front.
// Every frame derives each card's offset from it, so a turn, a drag and a
// rewind are all just animations of that number. Like the app it does not
// wrap: the newest card opens in front with nothing to its left.
(() => {
  const drum = document.getElementById("drum");
  const stage = document.getElementById("drum-stage");
  if (!drum || !stage || !window.gsap) {
    if (drum) drum.style.visibility = "visible";
    return;
  }

  const cards = [...stage.querySelectorAll(".drum-card")];
  const last = cards.length - 1;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  // CardDrumView's numbers, in units of the card's width (232pt in the app).
  const REACH = 3;
  const SPACING = 196 / 232;
  const TURN = 38;
  const SHRINK = 0.14;
  const FADE = 0.22;
  const BLUR = 0.6 / 232;

  const state = { pos: 0 };
  let unit = 232;
  let front = -1;

  function measure() {
    unit = cards[0].offsetWidth || 232;
  }

  function render() {
    cards.forEach((card, index) => {
      const offset = index - state.pos;
      const distance = Math.abs(offset);
      // The app hides cards past REACH; here the last step fades them out.
      const beyond = Math.min(Math.max(distance - REACH, 0), 1);
      const opacity = Math.max(0, (1 - distance * FADE) * (1 - beyond));
      card.style.visibility = opacity <= 0.01 ? "hidden" : "visible";
      card.style.opacity = opacity.toFixed(3);
      card.style.transform =
        `translate(-50%, -50%) translateX(${(offset * SPACING * unit).toFixed(2)}px) ` +
        `perspective(${(unit * 2.6).toFixed(0)}px) rotateY(${(-offset * TURN).toFixed(2)}deg) ` +
        `scale(${(1 - Math.min(distance, REACH + 1) * SHRINK).toFixed(4)})`;
      card.style.filter = distance > 0.05 ? `blur(${(distance * BLUR * unit).toFixed(2)}px)` : "none";
      card.style.zIndex = String(100 - Math.round(distance * 10));
    });

    const nearest = Math.round(state.pos);
    if (nearest !== front) {
      front = nearest;
      cards.forEach((card, index) => {
        card.classList.toggle("front", index === front);
        card.querySelector("img").setAttribute("aria-hidden", index === front ? "false" : "true");
      });
    }
  }

  let turn;
  // The app springs to the new card (response 0.38, damping 0.82): a quick
  // move with a touch of overshoot.
  function turnTo(index, { duration, ease } = {}) {
    const target = Math.min(Math.max(index, 0), last);
    const steps = Math.abs(target - state.pos);
    turn?.kill();
    turn = gsap.to(state, {
      pos: target,
      duration: duration ?? Math.min(0.55 + steps * 0.08, 1.2),
      ease: ease ?? "back.out(1.15)",
      onUpdate: render
    });
    return turn;
  }

  // ---- Autoplay: browse back through the history, then return to the
  //      newest, as someone flicking through the bar would.

  let auto;
  let inView = true;
  let idleUntil = 0;

  function scheduleAuto(delay = 2.1) {
    auto?.kill();
    if (reduce || !inView || document.hidden) return;
    auto = gsap.delayedCall(delay, autoStep);
  }

  function autoStep() {
    if (performance.now() < idleUntil) return scheduleAuto((idleUntil - performance.now()) / 1000);
    const next = Math.round(state.pos) + 1;
    if (next > last) {
      turnTo(0, { duration: 1.5, ease: "power3.inOut" });
      scheduleAuto(3.4);
    } else {
      turnTo(next);
      scheduleAuto(next === last ? 2.8 : 2.1);
    }
  }

  // Anything the visitor does pauses the autoplay for a while.
  function touched() {
    idleUntil = performance.now() + 7000;
    scheduleAuto(7);
  }

  if ("IntersectionObserver" in window) {
    new IntersectionObserver(([entry]) => {
      inView = entry.isIntersecting;
      inView ? scheduleAuto() : auto?.kill();
    }, { threshold: 0.25 }).observe(drum);
  }
  document.addEventListener("visibilitychange", () => (document.hidden ? auto?.kill() : scheduleAuto()));

  // ---- Keys: ← → turn it, as in the app. Only while the drum has focus or
  //      the pointer is over it, so the page's own arrow-key scrolling stays.

  let hovering = false;
  drum.addEventListener("pointerenter", () => { hovering = true; });
  drum.addEventListener("pointerleave", () => { hovering = false; });
  document.addEventListener("keydown", (event) => {
    if (event.metaKey || event.ctrlKey || event.altKey) return;
    if (!hovering && document.activeElement !== drum) return;
    const step = { ArrowLeft: -1, ArrowRight: 1 }[event.key];
    if (!step) return;
    event.preventDefault();
    touched();
    turnTo(front + step);
  });

  // ---- Dragging spins it continuously; letting go settles on the nearest
  //      card, carried a little by the flick. A tap on a side card turns to it.

  let drag = null;
  stage.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) return;
    turn?.kill();
    drag = { x: event.clientX, pos: state.pos, moved: false, samples: [[event.timeStamp, event.clientX]] };
  });
  stage.addEventListener("pointermove", (event) => {
    if (!drag) return;
    const dx = event.clientX - drag.x;
    if (!drag.moved && Math.abs(dx) > 6) {
      drag.moved = true;
      try { stage.setPointerCapture(event.pointerId); } catch {}
      stage.classList.add("dragging");
      touched();
    }
    if (!drag.moved) return;
    let pos = drag.pos - dx / (SPACING * unit);
    // Past either end it gives, but less and less.
    if (pos < 0) pos = -Math.sqrt(-pos) * 0.35;
    if (pos > last) pos = last + Math.sqrt(pos - last) * 0.35;
    state.pos = pos;
    render();
    drag.samples.push([event.timeStamp, event.clientX]);
    if (drag.samples.length > 5) drag.samples.shift();
  });
  function endDrag(event) {
    if (!drag) return;
    const { moved, samples } = drag;
    drag = null;
    stage.classList.remove("dragging");
    if (!moved) {
      const card = event.target.closest?.(".drum-card");
      if (card) {
        touched();
        const index = Number(card.dataset.index);
        if (index === front) {
          // The front card: a press, as Enter would paste it.
          gsap.timeline()
            .to(card.querySelector("img"), { scale: 0.95, duration: 0.09, ease: "power2.out" })
            .to(card.querySelector("img"), { scale: 1, duration: 0.45, ease: "elastic.out(1, 0.45)" });
        } else {
          turnTo(index);
        }
      }
      return;
    }
    const [t0, x0] = samples[0];
    const [t1, x1] = samples[samples.length - 1];
    const velocity = t1 > t0 ? (x1 - x0) / (t1 - t0) : 0; // px per ms
    turnTo(Math.round(state.pos - (velocity * 140) / (SPACING * unit)));
  }
  stage.addEventListener("pointerup", endDrag);
  stage.addEventListener("pointercancel", endDrag);

  // ---- Trackpad: a sideways swipe turns it a card at a time, like the
  //      app's scroll monitor. Vertical scrolling is left to the page.

  let wheelSum = 0;
  stage.addEventListener("wheel", (event) => {
    if (Math.abs(event.deltaX) <= Math.abs(event.deltaY)) return;
    event.preventDefault();
    wheelSum += event.deltaX;
    if (Math.abs(wheelSum) >= 46) {
      touched();
      turnTo(front + Math.sign(wheelSum));
      wheelSum = 0;
    }
  }, { passive: false });

  // ---- Opening and closing, as ⇧⌘V does in the app: it slides up from the
  //      bottom edge and opens on the newest copy.

  function open({ delay = 0 } = {}) {
    turn?.kill();
    state.pos = 0;
    render();
    gsap.set(drum, { visibility: "visible" });
    const timeline = gsap.timeline({ delay });
    if (reduce) {
      timeline.fromTo(drum, { autoAlpha: 0 }, { autoAlpha: 1, duration: 0.3 });
      state.pos = 2;
      render();
      return timeline;
    }
    timeline
      .fromTo(drum, { yPercent: 45, autoAlpha: 0 }, { yPercent: 0, autoAlpha: 1, duration: 0.85, ease: "back.out(1.25)" })
      .add(() => scheduleAuto(1.4));
    return timeline;
  }

  function close() {
    auto?.kill();
    turn?.kill();
    return gsap.to(drum, { yPercent: 45, autoAlpha: 0, duration: 0.22, ease: "power2.in" });
  }

  window.fiokaDrum = {
    toggle() {
      if (gsap.isTweening(drum)) return;
      close().then(() => open());
    }
  };

  measure();
  render();
  addEventListener("resize", () => { measure(); render(); });
  open({ delay: 0.35 });
})();
