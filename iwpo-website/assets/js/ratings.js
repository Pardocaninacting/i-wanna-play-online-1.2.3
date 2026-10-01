/* ============================================================
   IWPO Online — ratings page
   Data: /ratings/api (same-origin, proxied by nginx).
   Search / filter / aggregate / sort happen client-side.
   ============================================================ */

(function () {
  "use strict";

  const { esc, getJSON } = window.IWPO || {};

  const state = {
    all: [],
    search: "",
    minStars: 0,
    cleared: "",
    sortKey: "timestamp",
    sortDesc: true,
    view: "games", // games = 按游戏聚合 / records = 逐条列表
    gKey: "avg",   // 聚合视图排序列
    gDesc: true,
  };

  const STAR = '<svg class="star" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><path d="M12 2l3 6.9 7.5.7-5.6 5 1.6 7.4L12 18.3 5.5 22l1.6-7.4-5.6-5 7.5-.7L12 2z"/></svg>';
  const starRow = (n) =>
    '<span class="stars" aria-label="' + n + ' 星">' +
    [1, 2, 3, 4, 5]
      .map((i) => STAR.replace('class="star"', 'class="star ' + (i <= n ? "star--on" : "star--off") + '"'))
      .join("") +
    "</span>";

  const GAME_COLS = [
    { key: "name", label: "游戏" },
    { key: "avg", label: "平均星级" },
    { key: "count", label: "评分人数" },
    { key: "cleared", label: "通关人数" },
  ];

  const RECORDS_HEAD =
    '<div class="rt__row rt__row--head" role="row">' +
    '<span role="columnheader">游戏</span><span role="columnheader">玩家</span>' +
    '<span role="columnheader">星级</span><span role="columnheader">通关</span></div>';

  const fmtDate = (ts) => {
    if (!ts) return "";
    const d = new Date(ts * 1000);
    const p = (x) => String(x).padStart(2, "0");
    return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate());
  };

  /* ---------- 数据规范化 ----------
     线上评分里有两类脏数据（2026-09-30 排查确认）：
       1) gameID 是「32 位 hex + 123 后缀」；早期客户端不带后缀，同一游戏
          会分裂成两个条目（实测 9 个旧 ID 中有 4 个存在带后缀的双胞胎）→ 统一
          去掉后缀再分组。
       2) gameID 前缀为 d41d8cd98f00b204e9800998ecf8427e（= MD5 空串）时，
          说明客户端没能算出游戏标识，这类评分全部落进同一个桶（实测 18 条里
          混了 14 个不同游戏）→ 按上报的游戏名归组；该游戏已有真实 ID 的评分时并入其中，
          连名字也没有的才标为「未知游戏」、不参与排行榜。 */
  const EMPTY_HASH = "d41d8cd98f00b204e9800998ecf8427e";
  const canonId = (id) => {
    const s = String(id == null ? "" : id);
    return /^[0-9a-f]{32}123$/.test(s) ? s.slice(0, 32) : s;
  };
  const isUnknownGame = (r) => {
    const id = canonId(r.gameID);
    return !!id && id.startsWith(EMPTY_HASH);
  };
  const nameOf = (r) => String(r.gameName || "").trim().toLowerCase();

  // lowercased game name -> group key of a record that carries a real ID
  let nameToKey = new Map();
  function indexNames(all) {
    nameToKey = new Map();
    all.forEach((r) => {
      const id = canonId(r.gameID);
      const name = nameOf(r);
      if (id && !isUnknownGame(r) && name && !nameToKey.has(name)) nameToKey.set(name, "id:" + id);
    });
  }

  const gameKey = (r) => {
    const id = canonId(r.gameID);
    if (id && !isUnknownGame(r)) return "id:" + id;
    const name = nameOf(r);
    if (!name) return id ? "unknown:" + id : "name:";
    return nameToKey.get(name) || "name:" + name;
  };

  function filtered() {
    const q = state.search.trim().toLowerCase();
    const list = state.all.filter((r) => {
      if (q) {
        const name = String(r.gameName || "").toLowerCase();
        const player = String(r.playerName || "").toLowerCase();
        if (!name.includes(q) && !player.includes(q)) return false;
      }
      if (state.minStars > 0 && (Number(r.stars) || 0) < state.minStars) return false;
      if (state.cleared !== "" && Number(r.cleared) !== Number(state.cleared)) return false;
      return true;
    });
    list.sort((a, b) => {
      const av = a[state.sortKey];
      const bv = b[state.sortKey];
      const cmp =
        typeof av === "string" && typeof bv === "string"
          ? av.localeCompare(bv, "zh")
          : (av || 0) - (bv || 0);
      return state.sortDesc ? -cmp : cmp;
    });
    return list;
  }

  function aggregate(list) {
    const map = new Map();
    list.forEach((r) => {
      const key = gameKey(r);
      let g = map.get(key);
      if (!g) {
        g = { name: "", count: 0, sum: 0, cleared: 0 };
        map.set(key, g);
      }
      if (key.startsWith("unknown:")) {
        g.unknown = true;         // 兜底桶：不采纳其中的游戏名
      } else if (r.gameName && !g.name) {
        g.name = String(r.gameName);
      }
      g.count += 1;
      g.sum += Number(r.stars) || 0;
      if (!g.dist) g.dist = [0, 0, 0, 0, 0, 0];
      const st = Math.max(0, Math.min(5, Number(r.stars) || 0));
      g.dist[st] += 1;
      if (Number(r.cleared) === 1) g.cleared += 1;
    });
    const rows = [];
    map.forEach((g) => {
      rows.push({
        name: g.unknown ? "未知游戏（无法识别游戏 ID）" : (g.name || "(未知游戏)"),
        unknown: !!g.unknown,
        avg: g.count ? g.sum / g.count : 0,
        count: g.count,
        cleared: g.cleared,
        dist: g.dist || [0, 0, 0, 0, 0, 0],
      });
    });
    rows.sort((a, b) => {
      if (a.unknown !== b.unknown) return a.unknown ? 1 : -1;   // 未知桶永远排最后
      const cmp =
        state.gKey === "name"
          ? a.name.localeCompare(b.name, "zh")
          : a[state.gKey] - b[state.gKey];
      return state.gDesc ? -cmp : cmp;
    });
    return rows;
  }

  function renderStats() {
    const all = state.all;
    const games = new Set(all.map(gameKey).filter((k) => !k.startsWith("unknown:")));
    const avg = all.length
      ? (all.reduce((t, r) => t + (Number(r.stars) || 0), 0) / all.length).toFixed(2)
      : "—";
    const cleared = all.filter((r) => Number(r.cleared) === 1).length;
    const set = (id, v) => {
      const el = document.getElementById(id);
      if (el) el.textContent = String(v);
    };
    set("st-games", games.size);
    set("st-total", all.length);
    set("st-avg", avg);
    set("st-cleared", cleared);
  }

  function gamesHead() {
    return (
      '<div class="rt__row rt__row--head" role="row">' +
      GAME_COLS.map((c) => {
        const active = state.gKey === c.key;
        const arrow = active ? (state.gDesc ? "↓" : "↑") : "";
        return (
          '<span role="columnheader"' +
          (active ? ' aria-sort="' + (state.gDesc ? "descending" : "ascending") + '"' : "") +
          '><button class="th-sort" type="button" data-key="' + c.key + '">' +
          c.label +
          '<span class="th-sort__arrow" aria-hidden="true">' + arrow + "</span>" +
          "</button></span>"
        );
      }).join("") +
      "</div>"
    );
  }

  const emptyMsg = () => (state.all.length ? "没有匹配的评分记录。" : "还没有评分记录。");

  function render() {
    const body = document.getElementById("rt-body");
    const shown = document.getElementById("rt-shown");
    if (!body) return;
    const list = filtered();

    if (state.view === "games") {
      const rows = aggregate(list);
      if (shown) {
        const known = rows.filter((r) => !r.unknown).length;
        const unknownCount = rows.filter((r) => r.unknown).reduce((t, r) => t + r.count, 0);
        shown.textContent =
          known + " 款游戏 / " + list.length + " 条评分" +
          (unknownCount ? "（另有 " + unknownCount + " 条无法识别游戏 ID，未参与排行）" : "");
      }
      if (!rows.length) {
        body.innerHTML = gamesHead() + '<div class="empty">' + emptyMsg() + "</div>";
        return;
      }
      body.innerHTML =
        gamesHead() +
        rows
          .map((g) => {
            // stacked 1-5 star share bar under the average
            const bar =
              '<span class="rt__dist" aria-hidden="true">' +
              g.dist
                .map((n, i) =>
                  n
                    ? '<i style="flex:' + n + ';opacity:' + (0.25 + i * 0.15) + '"></i>'
                    : ""
                )
                .join("") +
              "</span>";
            return (
              '<div class="rt__row rt__row--game" role="row" data-game="' + esc(g.name) + '" title="点击查看该游戏的逐条记录">' +
              '<span class="rt__name" role="cell">' + esc(g.name) + "</span>" +
              '<span role="cell">' + starRow(Math.round(g.avg)) +
              '<span class="rt__num rt__avg">' + g.avg.toFixed(2) + "</span>" + bar + "</span>" +
              '<span class="rt__num" role="cell">' + g.count + "</span>" +
              '<span class="rt__num" role="cell">' + g.cleared + "</span>" +
              "</div>"
            );
          })
          .join("");
      return;
    }

    if (shown) shown.textContent = list.length + " / " + state.all.length + " 条";
    if (!list.length) {
      body.innerHTML = RECORDS_HEAD + '<div class="empty">' + emptyMsg() + "</div>";
      return;
    }
    body.innerHTML =
      RECORDS_HEAD +
      list
        .slice(0, 400)
        .map((r) => {
          const cleared = Number(r.cleared) === 1;
          return (
            '<div class="rt__row" role="row">' +
            '<span class="rt__name" role="cell">' + esc(r.gameName || "(未知游戏)") + "</span>" +
            '<span class="muted" role="cell">' + esc(r.playerName || "Anonymous") + "</span>" +
            '<span role="cell">' + starRow(Number(r.stars) || 0) + "</span>" +
            '<span role="cell">' +
            (cleared
              ? '<span class="pill pill--open">已通关</span>'
              : '<span class="pill">未通关</span>') +
            '<span class="muted mono" style="font-size:11.5px;margin-left:8px;">' + fmtDate(r.timestamp) + "</span>" +
            "</span>" +
            "</div>"
          );
        })
        .join("");
  }

  async function load() {
    try {
      const data = await getJSON("/ratings/api");
      state.all = Array.isArray(data.ratings) ? data.ratings : [];
      indexNames(state.all);
      renderStats();
      render();
    } catch (err) {
      const body = document.getElementById("rt-body");
      if (body) {
        body.innerHTML =
          (state.view === "games" ? gamesHead() : RECORDS_HEAD) +
          '<div class="empty">读取评分失败：' + esc(err && err.message ? err.message : "") + "</div>";
      }
    }
  }

  // aggregate row click: drill into that game's individual records
  const rtBody = document.getElementById("rt-body");
  if (rtBody) {
    rtBody.addEventListener("click", (e) => {
      const row = e.target.closest(".rt__row--game");
      if (!row || !row.dataset.game) return;
      const input = document.getElementById("f-search");
      if (input) input.value = row.dataset.game;
      state.search = row.dataset.game;
      state.view = "records";
      document.querySelectorAll(".view-tab").forEach((b) => {
        b.setAttribute("aria-pressed", String(b.dataset.view === "records"));
      });
      render();
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    const search = document.getElementById("f-search");
    const stars = document.getElementById("f-stars");
    const cleared = document.getElementById("f-cleared");
    const reset = document.getElementById("btn-reset");
    const rtBody = document.getElementById("rt-body");
    const tabs = Array.prototype.slice.call(document.querySelectorAll(".view-tab"));

    tabs.forEach((tab) => {
      tab.addEventListener("click", () => {
        const view = tab.getAttribute("data-view");
        if (!view || view === state.view) return;
        state.view = view;
        tabs.forEach((t) => t.setAttribute("aria-pressed", String(t === tab)));
        render();
      });
    });

    if (rtBody) {
      rtBody.addEventListener("click", (e) => {
        const t = e.target;
        const btn = t && t.closest ? t.closest(".th-sort") : null;
        if (!btn) return;
        const key = btn.getAttribute("data-key");
        if (state.gKey === key) {
          state.gDesc = !state.gDesc;
        } else {
          state.gKey = key;
          state.gDesc = key !== "name";
        }
        render();
      });
    }

    if (search) search.addEventListener("input", (e) => { state.search = e.target.value; render(); });
    if (stars) stars.addEventListener("change", (e) => { state.minStars = Number(e.target.value); render(); });
    if (cleared) cleared.addEventListener("change", (e) => { state.cleared = e.target.value; render(); });
    if (reset) {
      reset.addEventListener("click", () => {
        state.search = ""; state.minStars = 0; state.cleared = "";
        if (search) search.value = "";
        if (stars) stars.value = "0";
        if (cleared) cleared.value = "";
        render();
      });
    }
    load();
  });
})();
