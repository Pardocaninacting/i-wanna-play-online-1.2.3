/* ============================================================
   IWPO Online — download page
   latest version from /version (POST, same-origin);
   archive files live in files/ (served by nginx).
   ============================================================ */

(function () {
  "use strict";

  const { esc, postJSON } = window.IWPO || {};

  const ARCHIVES = [
    { file: "iwpo 1.2.3_beta_5.zip", note: "beta.5" },
    { file: "iwpo 1.2.3_beta_4.zip", note: "beta.4" },
    { file: "iwpo 1.2.3_beta_3.zip", note: "beta.3" },
    { file: "iwpo 1.2.3_beta_2.zip", note: "beta.2" },
    // 最初版本（历史上曾误命名为 iwpo 1.2.3.zip，已改名为 beta_1）
    { file: "iwpo 1.2.3_beta_1.zip", note: "beta.1（最初版本）" },
  ];

  function render(version) {
    const list = document.getElementById("archive");
    const verEl = document.getElementById("dl-version");
    const btn = document.getElementById("dl-button");
    if (verEl) verEl.textContent = version ? "v" + version : "v—";
    if (btn && version) {
      btn.textContent = "下载 v" + version;
      btn.href = "files/iwpo " + encodeURIComponent(version) + ".zip";
    }
    if (!list) return;

    const latest = version
      ? '<div class="dl__item">' +
        '<a class="dl__file" href="files/iwpo ' + esc(version) + '.zip">iwpo ' + esc(version) + ".zip</a>" +
        '<span class="dl__note">最新版本</span></div>'
      : "";

    list.innerHTML =
      latest +
      ARCHIVES.filter((a) => !version || a.file !== "iwpo " + version + ".zip")
        .map((a) =>
          '<div class="dl__item">' +
          '<a class="dl__file" href="files/' + esc(a.file) + '">' + esc(a.file) + "</a>" +
          (a.note ? '<span class="dl__note">' + esc(a.note) + "</span>" : "") +
          "</div>"
        )
        .join("");
  }

  document.addEventListener("DOMContentLoaded", async () => {
    try {
      const data = await postJSON("/version");
      render(data && data.success ? data.version : null);
    } catch {
      render(null);
    }
  });
})();
