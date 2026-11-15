// Liquid glass, ported to vanilla JS from Opaline (https://opaline.buildlab.in),
// the same engine the Stripped project vendors in src/vendor/opaline.
// Traces light through a squircle bezel with Snell's law, bakes it into a
// displacement map, and applies it via backdrop-filter: url(#svg-filter).
// Only Chromium refracts the backdrop; other engines get a frosted blur.

(function () {
  const IOR = 1.5;
  const THICKNESS_RATIO = 1.4;
  const SAMPLES = 128;
  const MAX_MAP = 480;
  const NS = "http://www.w3.org/2000/svg";

  const squircle = (t) => Math.pow(1 - Math.pow(1 - t, 4), 0.25);

  function slopeAt(t) {
    const e = 1e-4, a = Math.max(0, t - e), b = Math.min(1, t + e);
    return (squircle(b) - squircle(a)) / (b - a);
  }

  // How far (px) each vertical ray shifts as it refracts through the rim.
  function profile(bezel, thickness) {
    const values = new Float32Array(SAMPLES);
    let max = 0;
    for (let i = 0; i < SAMPLES; i++) {
      const t = Math.max(i / (SAMPLES - 1), 1e-3);
      const slope = (slopeAt(t) * thickness) / bezel;
      const t1 = Math.atan(Math.abs(slope));
      const s = Math.sin(t1) / IOR;
      const t2 = Math.abs(s) > 1 ? t1 : Math.asin(s);
      const d = thickness * squircle(t) * Math.tan(t1 - t2) * Math.sign(slope);
      values[i] = d;
      max = Math.max(max, Math.abs(d));
    }
    return { values, max };
  }

  function sample(values, t) {
    const x = Math.min(1, Math.max(0, t)) * (values.length - 1);
    const i = Math.floor(x), j = Math.min(values.length - 1, i + 1);
    return values[i] + (values[j] - values[i]) * (x - i);
  }

  // Walks every pixel of a rounded rect with its distance from the edge and outward normal.
  function paint(w, h, radius, fn) {
    const scale = Math.min(1, MAX_MAP / Math.max(w, h));
    const mw = Math.max(1, Math.round(w * scale)), mh = Math.max(1, Math.round(h * scale));
    const r = Math.min(radius, w / 2, h / 2) * scale;
    const canvas = document.createElement("canvas");
    canvas.width = mw; canvas.height = mh;
    const ctx = canvas.getContext("2d");
    const img = ctx.createImageData(mw, mh);
    const hw = mw / 2, hh = mh / 2;
    for (let y = 0; y < mh; y++) {
      for (let x = 0; x < mw; x++) {
        const px = x + 0.5 - hw, py = y + 0.5 - hh;
        const qx = Math.abs(px) - (hw - r), qy = Math.abs(py) - (hh - r);
        let dist, nx = 0, ny = 0;
        if (qx > 0 && qy > 0) {
          const len = Math.hypot(qx, qy);
          dist = r - len; nx = (qx / len) * Math.sign(px); ny = (qy / len) * Math.sign(py);
        } else if (qx > qy) { dist = r - qx; nx = Math.sign(px); }
        else { dist = r - qy; ny = Math.sign(py); }
        fn(dist / scale, nx, ny, img.data, (y * mw + x) * 4);
      }
    }
    ctx.putImageData(img, 0, 0);
    return canvas.toDataURL();
  }

  function displacementMap(w, h, radius, bezel) {
    const b = Math.max(1, Math.min(bezel, w / 2, h / 2));
    const { values, max } = profile(b, b * THICKNESS_RATIO);
    const url = paint(w, h, radius, (dist, nx, ny, d, i) => {
      let dx = 0, dy = 0;
      if (max > 0 && dist > 0 && dist < b) {
        const m = sample(values, dist / b) / max;
        dx = -nx * m; dy = -ny * m;
      }
      d[i] = 128 + dx * 127; d[i + 1] = 128 + dy * 127; d[i + 2] = 128; d[i + 3] = 255;
    });
    return { url, scale: max * 2, bezel: b };
  }

  function specularMap(w, h, radius, bezel, angle) {
    const lx = Math.cos((angle * Math.PI) / 180), ly = Math.sin((angle * Math.PI) / 180);
    return paint(w, h, radius, (dist, nx, ny, d, i) => {
      let a = 0;
      if (dist > 0 && dist < bezel) {
        const s = Math.abs(slopeAt(Math.max(dist / bezel, 1e-3)));
        a = Math.pow(Math.abs(nx * lx + ny * ly), 3) * Math.pow(s / Math.hypot(1, s), 0.6);
      }
      d[i] = d[i + 1] = d[i + 2] = 255; d[i + 3] = a * 255;
    });
  }

  const supports = (() => {
    const ua = navigator.userAgent;
    const chromium = /Chrome\/|Chromium\//.test(ua) && !/CriOS|FxiOS|EdgiOS/.test(ua);
    const reduced = matchMedia("(prefers-reduced-transparency: reduce)").matches;
    return chromium && !reduced;
  })();

  let uid = 0;
  const el = (tag, attrs) => {
    const n = document.createElementNS(NS, tag);
    for (const k in attrs) n.setAttribute(k, attrs[k]);
    return n;
  };

  function buildFilter(id, map, spec, w, h, o) {
    const f = el("filter", { id, x: 0, y: 0, width: w, height: h, filterUnits: "userSpaceOnUse", "color-interpolation-filters": "sRGB" });
    f.append(el("feGaussianBlur", { in: "SourceGraphic", stdDeviation: o.blur, result: "blur" }));
    f.append(el("feImage", { href: map.url, x: 0, y: 0, width: w, height: h, preserveAspectRatio: "none", result: "map" }));
    const disp = (k, result) => el("feDisplacementMap", { in: "blur", in2: "map", scale: map.scale * k, xChannelSelector: "R", yChannelSelector: "G", result });
    const only = (r, g, b, result, input) => el("feColorMatrix", { in: input, type: "matrix", values: `${r} 0 0 0 0  0 ${g} 0 0 0  0 0 ${b} 0 0  0 0 0 1 0`, result });
    f.append(disp(1, "dr"), only(1, 0, 0, "r", "dr"), disp(1 - o.dispersion, "dg"), only(0, 1, 0, "g", "dg"),
      disp(1 - o.dispersion * 2, "db"), only(0, 0, 1, "b", "db"),
      el("feBlend", { in: "r", in2: "g", mode: "screen", result: "rg" }),
      el("feBlend", { in: "rg", in2: "b", mode: "screen", result: "refracted" }),
      el("feColorMatrix", { in: "refracted", type: "saturate", values: o.saturation, result: "saturated" }),
      el("feImage", { href: spec, x: 0, y: 0, width: w, height: h, preserveAspectRatio: "none", result: "specMap" }));
    const ct = el("feComponentTransfer", { in: "specMap", result: "spec" });
    ct.append(el("feFuncA", { type: "linear", slope: o.specular }));
    f.append(ct, el("feComposite", { in: "spec", in2: "saturated", operator: "over" }));
    return f;
  }

  // Turns an element into a liquid glass surface. Its border-radius sets the shape.
  window.liquidGlass = function (target, opts) {
    const o = Object.assign({ blur: 2, saturation: 1.6, dispersion: 0.12, specular: 0.25, lightAngle: -60 }, opts);
    target.dataset.glass = "";
    const backdrop = document.createElement("span");
    backdrop.className = "glass-backdrop";
    backdrop.setAttribute("aria-hidden", "true");
    const tint = document.createElement("span"); tint.className = "glass-tint"; tint.setAttribute("aria-hidden", "true");
    const rim = document.createElement("span"); rim.className = "glass-rim"; rim.setAttribute("aria-hidden", "true");
    target.prepend(backdrop, tint, rim);
    if (!supports) return;

    const svg = el("svg", { width: 0, height: 0, "aria-hidden": "true" });
    svg.style.cssText = "position:absolute;width:0;height:0;pointer-events:none";
    target.append(svg);
    const id = "lg" + ++uid;
    let last = "";

    const build = () => {
      const w = target.offsetWidth, h = target.offsetHeight;
      if (!w || !h) return;
      const radius = Math.min(parseFloat(getComputedStyle(target).borderTopLeftRadius) || 0, w / 2, h / 2);
      const key = [w, h, radius].join(":");
      if (key === last) return;
      last = key;
      const bezel = Math.max(6, Math.min(Math.min(w, h) * 0.4, 40));
      const map = displacementMap(w, h, radius, bezel);
      const spec = specularMap(w, h, radius, map.bezel, o.lightAngle);
      svg.replaceChildren(buildFilter(id, map, spec, w, h, o));
      backdrop.style.backdropFilter = backdrop.style.webkitBackdropFilter = `url(#${id})`;
    };
    build();
    let t;
    new ResizeObserver(() => { clearTimeout(t); t = setTimeout(build, 140); }).observe(target);
  };
})();
