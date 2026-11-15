// Points the download buttons at the newest APK and fills the changelog from
// GitHub Releases. The HTML already holds a working fallback for both, so if
// GitHub does not answer the page still works.
(function () {
  const REPO = "Asta39/postvault";
  const API = "https://api.github.com/repos/" + REPO + "/releases?per_page=20";
  const CACHE_KEY = "postvault-releases";
  const CACHE_MS = 10 * 60 * 1000;
  // Release-note sections that only make sense on GitHub (the page has its own download and install parts).
  const SKIP = /^(download|verify|ai sorting|turn on ai sorting|install)\b/i;

  if (/Android/i.test(navigator.userAgent)) document.documentElement.classList.add("is-android");
  if (window.liquidGlass) document.querySelectorAll(".glass-pill").forEach((p) => window.liquidGlass(p));

  function cached() {
    try {
      const c = JSON.parse(sessionStorage.getItem(CACHE_KEY));
      if (c && Date.now() - c.at < CACHE_MS) return c.data;
    } catch (e) {}
    return null;
  }

  async function load() {
    const hit = cached();
    if (hit) return hit;
    const res = await fetch(API, { headers: { Accept: "application/vnd.github+json" } });
    if (!res.ok) throw new Error("GitHub answered " + res.status);
    const data = (await res.json())
      .filter((r) => !r.draft && !r.prerelease)
      .map((r) => ({
        tag: r.tag_name,
        date: r.published_at,
        body: r.body || "",
        apk: (r.assets.find((a) => /\.apk$/i.test(a.name)) || null),
      }))
      .map((r) => ({ ...r, apk: r.apk && { url: r.apk.browser_download_url, size: r.apk.size } }));
    try { sessionStorage.setItem(CACHE_KEY, JSON.stringify({ at: Date.now(), data })); } catch (e) {}
    return data;
  }

  // **bold**, `code` and [text](https://link) inside one line of release notes.
  function inline(parent, text) {
    const re = /\*\*(.+?)\*\*|`([^`]+)`|\[([^\]]+)\]\((https:\/\/[^)\s]+)\)/g;
    let last = 0, m;
    while ((m = re.exec(text))) {
      if (m.index > last) parent.append(text.slice(last, m.index));
      let node;
      if (m[1] != null) { node = document.createElement("strong"); inline(node, m[1]); }
      else if (m[2] != null) { node = document.createElement("code"); node.textContent = m[2]; }
      else { node = document.createElement("a"); node.href = m[4]; node.rel = "noopener"; node.textContent = m[3]; }
      parent.append(node);
      last = re.lastIndex;
    }
    if (last < text.length) parent.append(text.slice(last));
  }

  function renderBody(md) {
    const out = document.createElement("div");
    out.className = "release-body";
    let skipping = false, list = null, para = null;
    const closeBlocks = () => { list = null; para = null; };
    for (const raw of md.replace(/\r/g, "").split("\n")) {
      const line = raw.trim();
      const heading = line.match(/^#{1,6}\s+(.*)$/);
      if (heading) {
        closeBlocks();
        skipping = SKIP.test(heading[1]);
        if (!skipping) { const h = document.createElement("h4"); inline(h, heading[1]); out.append(h); }
        continue;
      }
      if (skipping || line.startsWith(">")) { closeBlocks(); continue; }
      if (!line) { closeBlocks(); continue; }
      const item = line.match(/^(?:[-*]|(\d+)\.)\s+(.*)$/);
      if (item) {
        const tag = item[1] ? "OL" : "UL";
        if (!list || list.tagName !== tag) { list = document.createElement(tag); out.append(list); }
        para = null;
        const li = document.createElement("li");
        inline(li, item[2]);
        list.append(li);
        continue;
      }
      list = null;
      if (para) para.append(" "); else { para = document.createElement("p"); out.append(para); }
      inline(para, line);
    }
    return out;
  }

  function render(releases) {
    const latest = releases.find((r) => r.apk);
    if (latest) {
      document.querySelectorAll("[data-download]").forEach((a) => { a.href = latest.apk.url; });
      document.querySelectorAll("[data-version]").forEach((n) => { n.textContent = latest.tag; });
      document.querySelectorAll("[data-size]").forEach((n) => { n.textContent = Math.round(latest.apk.size / 1e6) + " MB"; });
    }
    const box = document.getElementById("releases");
    if (!box || !releases.length) return;
    const fmt = new Intl.DateTimeFormat("en-GB", { day: "numeric", month: "long", year: "numeric" });
    box.replaceChildren(...releases.map((r) => {
      const art = document.createElement("article");
      art.className = "release";
      const head = document.createElement("header");
      const h = document.createElement("h3"); h.textContent = r.tag;
      const t = document.createElement("time"); t.dateTime = r.date; t.textContent = fmt.format(new Date(r.date));
      head.append(h, t);
      art.append(head, renderBody(r.body));
      return art;
    }));
  }

  load().then(render).catch(() => { /* the HTML fallback stays in place */ });
})();
