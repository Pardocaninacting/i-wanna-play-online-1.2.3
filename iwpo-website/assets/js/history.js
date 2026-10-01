/* ============================================================
   IWPO Online — release axis (about page)
   Three development lines on one time axis; every dot is a release.
   Dates: GitLab i-wanna-play-online tags/commits, the README history
   of gitlab.com/TheBiob/modder, and this project's git tags.
   ============================================================ */

(function () {
  "use strict";

  // [date, version, label shown on the axis?, label anchor, current release?]
  const LANES = [
    {
      name: "原版 · DapperMink",
      start: "2019-12-22",
      releases: [
        ["2020-01-24", "1.0.0", "1.0.0", "end"],
        ["2020-01-25", "1.1.0 – 1.1.3"],
        ["2020-02-01", "1.1.4"],
        ["2020-02-10", "1.1.5"],
        ["2021-06-02", "1.1.6", "1.1.6"],
        ["2022-01-16", "1.1.7"],
        ["2022-02-25", "1.1.8"],
        ["2022-02-27", "1.1.9", "1.1.9", "start"],
      ],
    },
    {
      name: "TheBiob 分支 · 1.1.10",
      start: "2023-02-11",
      releases: [
        ["2023-09-16", "b5", "b5", "end"],
        ["2023-10-07", "b6"],
        ["2023-12-16", "b7 – b9"],
        ["2023-12-20", "b10"],
        ["2024-01-20", "b11"],
        ["2024-03-16", "b12"],
        ["2024-03-23", "b13 · mod 框架", "b13", "start"],
        ["2024-04-07", "b14 – b15"],
        ["2024-07-03", "b16"],
        ["2024-08-24", "b17"],
        ["2024-12-14", "b18 · 自动重连"],
        ["2025-04-20", "b19"],
        ["2025-10-11", "b20"],
        ["2026-04-11", "b21 – b22"],
        ["2026-06-20", "b23 · 自动更新", "b23", "start"],
      ],
    },
    {
      name: "1.2.3 · 本项目",
      releases: [
        ["2026-04-14", "beta 1", "beta 1", "end"],
        ["2026-04-16", "beta 2"],
        ["2026-04-17", "beta 3"],
        ["2026-05-03", "beta 4"],
        ["2026-05-28", "beta 5"],
        ["2026-09-29", "beta 6", "beta 6", "start", true],
      ],
    },
  ];

  const SVG_NS = "http://www.w3.org/2000/svg";
  const WIDTH = 720;
  const X0 = 142;
  const X1 = 708;
  const T0 = Date.UTC(2019, 9, 1);
  const T1 = Date.UTC(2027, 5, 1);
  const LANE_TOP = 50;
  const LANE_GAP = 40;

  function time(iso) {
    const [y, m, d] = iso.split("-").map(Number);
    return Date.UTC(y, m - 1, d);
  }

  function xAt(iso) {
    return X0 + ((time(iso) - T0) / (T1 - T0)) * (X1 - X0);
  }

  function el(name, attrs, parent, text) {
    const node = document.createElementNS(SVG_NS, name);
    for (const key of Object.keys(attrs)) node.setAttribute(key, attrs[key]);
    if (text != null) node.textContent = text;
    if (parent) parent.appendChild(node);
    return node;
  }

  function render(figure) {
    const height = LANE_TOP + LANE_GAP * (LANES.length - 1) + 22;
    const svg = el("svg", {
      viewBox: "0 0 " + WIDTH + " " + height,
      role: "img",
      "aria-label": "版本时间轴：原版 1.0.0（2020-01-24）至 1.1.9（2022-02-27）；"
        + "TheBiob 分支 1.1.10 测试版 2023 至 2026（b23，2026-06-20）；1.2.3 beta 1（2026-04-14）至 beta 6。",
    });

    for (let year = 2020; year <= 2027; year += 1) {
      const x = xAt(year + "-01-01");
      el("line", { class: "ax-grid", x1: x, x2: x, y1: 20, y2: height - 6 }, svg);
      el("text", { class: "ax-year", x: x + 3, y: 12 }, svg, String(year));
    }

    LANES.forEach((lane, index) => {
      const y = LANE_TOP + index * LANE_GAP;
      const first = lane.start || lane.releases[0][0];
      const last = lane.releases[lane.releases.length - 1][0];
      el("text", { class: "ax-lane", x: 0, y: y + 4 }, svg, lane.name);
      el("line", { class: "ax-track", x1: xAt(first), x2: xAt(last), y1: y, y2: y }, svg);
      if (lane.start) {
        const start = el("circle", { class: "ax-start", cx: xAt(lane.start), cy: y, r: 3 }, svg);
        el("title", {}, start, (index === 0 ? "项目创建" : "分支开始") + " · " + lane.start);
      }
      for (const [date, version, label, anchor, current] of lane.releases) {
        const x = xAt(date);
        if (current) el("circle", { class: "ax-ring", cx: x, cy: y, r: 6.5 }, svg);
        const dot = el("circle", { class: current ? "ax-now" : "ax-dot", cx: x, cy: y, r: 3 }, svg);
        el("title", {}, dot, version + " · " + date);
        if (!label) continue;
        const shift = anchor === "end" ? -5 : anchor === "start" ? 5 : 0;
        el("text", { class: "ax-tag", x: x + shift, y: y - 9, "text-anchor": anchor || "middle" }, svg, label);
      }
    });

    figure.querySelector(".relaxis__scroll").appendChild(svg);
    figure.hidden = false;
  }

  const figure = document.getElementById("release-axis");
  if (figure) render(figure);
})();
