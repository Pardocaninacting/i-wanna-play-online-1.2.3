/* ============================================================
   IWPO Online — skins library page
   GET /skins · /skins/<hash>/file/<state>.png · /skins/<hash>.zip
   POST /skins/upload
   ============================================================ */

(function () {
  "use strict";

  

  const STATES = ["idle", "run", "jump", "fall", "slide", "bow", "bullet"];
  const STATE_LABEL = { idle: "待机", run: "奔跑", jump: "跳跃", fall: "下落", slide: "滑铲", bow: "鞠躬", bullet: "子弹" };
  const MAX_SCALE = 3;    // sprite magnification
  const FRAME_MS = 90;    // per animation frame

  const grid = document.getElementById("skins-grid");
  const countEl = document.getElementById("skins-count");
  const searchEl = document.getElementById("skins-search");
  const sortEl = document.getElementById("skins-sort");
  const modal = document.getElementById("skin-modal");
  const modalBody = document.getElementById("skin-modal-body");
  const uploadToggle = document.getElementById("upload-open");
  const uploadPanel = document.getElementById("upload-panel");
  const uploadMsg = document.getElementById("upload-msg");

  let allSkins = [];

  /* ---------- sprite frame view ----------
     One div per state: background = the horizontal strip, showing exactly
     one frame. Multi-frame states play as a css background-position step
     animation (keyframes live in the page stylesheet). */
  function frameView(parent, url, framewidth, frames, animate, maxHeight, onMissing) {
    const view = document.createElement("div");
    view.className = "skin-frame";
    parent.appendChild(view);
    const img = new Image();
    img.onload = function () {
      const fw = framewidth > 0 ? framewidth : Math.max(1, Math.round(img.naturalWidth / Math.max(1, frames)));
      const scale = Math.max(1, Math.min(MAX_SCALE, Math.floor(maxHeight / Math.max(1, img.naturalHeight))));
      view.style.width = fw * scale + "px";
      view.style.height = img.naturalHeight * scale + "px";
      view.style.backgroundImage = 'url("' + url + '")';
      view.style.backgroundSize = img.naturalWidth * scale + "px " + img.naturalHeight * scale + "px";
      if (animate && frames > 1) {
        view.style.setProperty("--skin-strip-end", -img.naturalWidth * scale + "px");
        view.style.animation = "skin-frames " + frames * FRAME_MS + "ms steps(" + frames + ") infinite";
      }
    };
    img.onerror = function () {
      view.classList.add("is-missing");
      if (onMissing) onMissing();
    };
    img.src = url;
    return view;
  }

  /* ---------- cards ---------- */

  function buildCard(skin) {
    const card = document.createElement("article");
    card.className = "skin-card";
    card.tabIndex = 0;
    card.setAttribute("role", "button");
    card.setAttribute("aria-label", "预览皮肤 " + (skin.name || skin.hash));

    const preview = document.createElement("div");
    preview.className = "skin-card__preview";
    const idle = skin.states && skin.states.idle;
    frameView(
      preview,
      "/skins/" + skin.hash + "/file/idle.png",
      idle ? idle.framewidth : 0,
      idle ? idle.frames : 1,
      false,
      96,
      function () { preview.textContent = "无预览"; }
    );

    const name = document.createElement("h3");
    name.className = "skin-card__name";
    name.textContent = skin.name || "（未命名）";

    const maker = document.createElement("p");
    maker.className = "skin-card__maker";
    maker.textContent = skin.maker ? "作者：" + skin.maker : "作者未知";

    const foot = document.createElement("div");
    foot.className = "skin-card__foot";
    const source = document.createElement("span");
    source.className = "skin-card__source";
    source.textContent = skin.source || "";
    const dl = document.createElement("a");
    dl.className = "btn btn--sm";
    dl.href = "/skins/" + skin.hash + ".zip";
    dl.setAttribute("download", "");
    dl.textContent = "下载";
    dl.addEventListener("click", function (e) { e.stopPropagation(); });
    foot.appendChild(source);
    foot.appendChild(dl);

    card.appendChild(preview);
    card.appendChild(name);
    card.appendChild(maker);
    card.appendChild(foot);
    card.addEventListener("click", function () { openModal(skin); });
    card.addEventListener("keydown", function (e) {
      if (e.key === "Enter" || e.key === " ") {
        e.preventDefault();
        openModal(skin);
      }
    });
    return card;
  }

  /* ---------- filter / sort / render ---------- */

  function getFiltered() {
    const q = searchEl.value.trim().toLowerCase();
    const list = allSkins.filter(function (s) {
      if (!q) return true;
      return (s.name || "").toLowerCase().includes(q)
        || (s.maker || "").toLowerCase().includes(q)
        || (s.source || "").toLowerCase().includes(q);
    });
    const mode = sortEl.value;
    list.sort(function (a, b) {
      if (mode === "name-asc" || mode === "name-desc") {
        const an = (a.name || "").toLowerCase();
        const bn = (b.name || "").toLowerCase();
        if (an === bn) return 0;
        return (an < bn ? -1 : 1) * (mode === "name-asc" ? 1 : -1);
      }
      const d = (a.addedAt || 0) - (b.addedAt || 0);
      return mode === "new-asc" ? d : -d;
    });
    return list;
  }

  function render() {
    const list = getFiltered();
    countEl.textContent = allSkins.length ? list.length + " / " + allSkins.length + " 款皮肤" : "";
    grid.innerHTML = "";
    if (!allSkins.length) {
      grid.innerHTML = '<div class="empty">皮肤库是空的——来上传第一个吧。</div>';
      return;
    }
    if (!list.length) {
      grid.innerHTML = '<div class="empty">没有匹配的皮肤。</div>';
      return;
    }
    list.forEach(function (s) { grid.appendChild(buildCard(s)); });
  }

  /* ---------- detail modal ---------- */

  let lastFocus = null;

  function formatDate(ts) {
    const d = new Date(ts * 1000);
    return d.getFullYear() + " 年 " + (d.getMonth() + 1) + " 月 " + d.getDate() + " 日";
  }

  function openModal(skin) {
    modalBody.innerHTML = "";

    const title = document.createElement("h2");
    title.className = "skin-modal__name";
    title.id = "skin-modal-name";
    title.textContent = skin.name || "（未命名）";

    const meta = document.createElement("p");
    meta.className = "skin-modal__meta";
    meta.textContent = "作者：" + (skin.maker || "未知")
      + " · 来源：" + (skin.source || "未知")
      + (skin.addedAt ? " · 入库于 " + formatDate(skin.addedAt) : "");

    const hash = document.createElement("p");
    hash.className = "skin-modal__hash mono";
    hash.textContent = skin.hash;

    const anims = document.createElement("div");
    anims.className = "skin-anims";
    let stateCount = 0;
    let totalFrames = 0;
    STATES.forEach(function (state) {
      const info = skin.states && skin.states[state];
      if (!info) return; // state not in the package: skip
      stateCount++;
      totalFrames += info.frames;
      const fig = document.createElement("figure");
      fig.className = "skin-anim";
      const box = document.createElement("div");
      box.className = "skin-anim__box";
      frameView(
        box,
        "/skins/" + skin.hash + "/file/" + state + ".png",
        info.framewidth,
        info.frames,
        true,
        108,
        function () { fig.remove(); } // file missing despite metadata
      );
      const cap = document.createElement("figcaption");
      cap.textContent = STATE_LABEL[state] + " · " + info.frames + " 帧";
      fig.appendChild(box);
      fig.appendChild(cap);
      anims.appendChild(fig);
    });

    const frames = document.createElement("p");
    frames.className = "skin-modal__frames";
    frames.textContent = "共 " + stateCount + " 个动作 · " + totalFrames + " 帧";

    const dl = document.createElement("a");
    dl.className = "btn btn--primary";
    dl.href = "/skins/" + skin.hash + ".zip";
    dl.setAttribute("download", "");
    dl.textContent = "下载皮肤包（.zip）";

    modalBody.appendChild(title);
    modalBody.appendChild(meta);
    modalBody.appendChild(hash);
    modalBody.appendChild(anims);
    modalBody.appendChild(frames);
    modalBody.appendChild(dl);

    lastFocus = document.activeElement;
    modal.hidden = false;
    document.body.style.overflow = "hidden";
    const close = modal.querySelector(".skin-modal__close");
    if (close) close.focus();
  }

  function closeModal() {
    modal.hidden = true;
    document.body.style.overflow = "";
    if (lastFocus && lastFocus.focus) lastFocus.focus();
  }

  /* ---------- upload ---------- */

  function setMsg(text, isError) {
    uploadMsg.textContent = text;
    uploadMsg.classList.toggle("is-error", !!isError);
    uploadMsg.classList.toggle("is-ok", !isError && !!text);
  }

  async function submitUpload(e) {
    e.preventDefault();
    const fileInput = document.getElementById("upload-files");
    const files = Array.prototype.slice.call(fileInput.files || []);
    if (!files.length) {
      setMsg("请选择皮肤文件，或一个 .zip 皮肤包。", true);
      return;
    }
    const isZip = files.length === 1 && /\.zip$/i.test(files[0].name);
    if (!isZip) {
      const names = files.map(function (f) { return f.name.toLowerCase(); });
      if (names.indexOf("idle.png") === -1 || names.indexOf("info.ini") === -1) {
        setMsg("多选上传时必须包含 idle.png 与 info.ini。", true);
        return;
      }
    }

    const fd = new FormData();
    fd.append("name", document.getElementById("up-name").value.trim());
    fd.append("maker", document.getElementById("up-maker").value.trim());
    fd.append("source", document.getElementById("up-source").value.trim());
    files.forEach(function (f) { fd.append("files", f); });

    const btn = uploadPanel.querySelector('button[type="submit"]');
    btn.disabled = true;
    setMsg("正在上传…", false);
    try {
      const res = await fetch("/skins/upload", { method: "POST", body: fd });
      let data = null;
      try { data = await res.json(); } catch { /* non-json reply */ }
      if (res.ok && data && data.success) {
        setMsg("入库完成，游戏内即可自动下载。", false);
        uploadPanel.reset();
        await load();
      } else {
        setMsg("上传失败：" + ((data && data.error) || ("HTTP " + res.status)), true);
      }
    } catch (err) {
      setMsg("上传失败：" + ((err && err.message) || "网络错误"), true);
    } finally {
      btn.disabled = false;
    }
  }

  /* ---------- data ---------- */

  async function load() {
    grid.innerHTML = '<div class="loading">正在加载皮肤库…</div>';
    try {
      const res = await fetch("/skins", { cache: "no-store" });
      if (!res.ok) throw new Error("HTTP " + res.status);
      const data = await res.json();
      if (!data || !data.success || !Array.isArray(data.skins)) throw new Error("bad payload");
      allSkins = data.skins;
    } catch {
      allSkins = [];
      countEl.textContent = "";
      grid.innerHTML = '<div class="empty">皮肤库加载失败，请稍后刷新重试。</div>';
      return;
    }
    render();
  }

  /* ---------- wiring ---------- */

  function init() {
    searchEl.addEventListener("input", render);
    sortEl.addEventListener("change", render);

    uploadToggle.addEventListener("click", function () {
      const show = uploadPanel.hidden;
      uploadPanel.hidden = !show;
      uploadToggle.textContent = show ? "收起上传" : "上传皮肤";
      uploadToggle.setAttribute("aria-expanded", show ? "true" : "false");
    });
    uploadPanel.addEventListener("submit", submitUpload);

    modal.addEventListener("click", function (e) {
      if (e.target.hasAttribute("data-close")) closeModal();
    });
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && !modal.hidden) closeModal();
    });

    load();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
