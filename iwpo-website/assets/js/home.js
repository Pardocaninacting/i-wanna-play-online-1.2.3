/* ============================================================
   IWPO Online — home page data wiring
   /getGames → the room table + the globe (window.IWPO_GLOBE.setState)
   ?mock=1 renders sample data; ?mock=empty previews a quiet server.
   ============================================================ */

(function () {
  "use strict";

  const { esc, postJSON } = window.IWPO || {};
  const params = new URLSearchParams(location.search);
  const MOCK = params.get("mock") === "1";
  const MOCK_EMPTY = params.get("mock") === "empty";

  const MOCK_GAMES = [
    { name: "I wanna be the Guy", players: 3, hasPassword: false },
    { name: "Needle Maze 2", players: 2, hasPassword: false },
    { name: "I wanna Kyuuketsuki", players: 1, hasPassword: false },
    { name: "", players: 2, hasPassword: true },
    { name: "Boshy Hard", players: 1, hasPassword: false },
  ];

  function feedGlobe(players, rooms) {
    const apply = () => {
      try {
        if (window.IWPO_GLOBE) window.IWPO_GLOBE.setState({ players, rooms });
        return !!window.IWPO_GLOBE;
      } catch (err) {
        // the globe is decoration — it must never take the lobby data down with it
        console.warn("[globe] setState failed", err);
        return true;
      }
    };
    if (apply()) return;
    // globe.js is a module: it may finish after us. Wait for it, but give up.
    let tries = 0;
    const timer = setInterval(() => {
      tries += 1;
      if (apply() || tries > 20) clearInterval(timer);
    }, 250);
  }

  /* ---------- rooms ---------- */
  function renderRooms(games) {
    const body = document.getElementById("rooms-body");
    const meta = document.getElementById("rooms-count");
    if (!body) return;

    if (meta) meta.textContent = games.length + " 个房间";

    const head =
      '<div class="trow trow--head" role="row">' +
      '<span role="columnheader">房间 / 游戏</span>' +
      '<span role="columnheader">玩家</span>' +
      '<span role="columnheader">状态</span>' +
      "</div>";

    if (!games.length) {
      body.innerHTML = head + '<div class="empty">当前没有人在线。</div>';
      return;
    }

    body.innerHTML =
      head +
      games
        .slice()
        .sort((a, b) => (b.players || 0) - (a.players || 0))
        .map((g) => {
          const locked = !!g.hasPassword;
          const players = g.players || 0;
          return (
            '<div class="trow" role="row">' +
            '<span class="trow__name" role="cell">' +
            (locked ? '<span class="muted">密码房间（名称隐藏）</span>' : esc(g.name || "(未命名房间)")) +
            "</span>" +
            '<span class="num ' + (players > 0 ? "num--live" : "num--zero") + '" role="cell">' + players + "</span>" +
            '<span role="cell"><span class="pill ' + (locked ? "pill--locked\">密码" : "pill--open\">公开") + "</span></span>" +
            "</div>"
          );
        })
        .join("");
  }

  async function loadGames() {
    try {
      const data = MOCK
        ? { success: true, games: MOCK_GAMES }
        : MOCK_EMPTY
          ? { success: true, games: [] }
          : await postJSON("/getGames");
      if (!data || !data.success || !Array.isArray(data.games)) throw new Error("bad payload");

      const games = data.games;
      const players = games.reduce((t, g) => t + (g.players || 0), 0);

      renderRooms(games);
      feedGlobe(players, games.length);
      window.dispatchEvent(new CustomEvent("iwpo:live", { detail: { players, rooms: games.length } }));
    } catch (err) {
      const body = document.getElementById("rooms-body");
      if (body) {
        body.innerHTML =
          '<div class="trow trow--head" role="row"><span role="columnheader">房间 / 游戏</span>' +
          '<span role="columnheader">玩家</span><span role="columnheader">状态</span></div>' +
          '<div class="empty">无法连接联机服务器<br><span class="muted mono" style="font-size:12px;">' +
          esc(err && err.message ? err.message : "") + "</span></div>";
      }
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    loadGames();
    const refresh = document.getElementById("rooms-refresh");
    if (refresh) refresh.addEventListener("click", loadGames);
    setInterval(() => { if (!document.hidden) loadGames(); }, 30000);
  });
})();
