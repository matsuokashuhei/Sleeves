/* ==========================================================================
   Sleeves Website — Language Switcher & Interactive Record Shelf Preview
   ========================================================================== */

(function () {
  "use strict";

  const STORAGE_KEY = "sleeves_site_lang";

  function detectInitialLang() {
    const params = new URLSearchParams(window.location.search);
    const urlLang = params.get("lang");
    if (urlLang === "ja" || urlLang === "en") {
      return urlLang;
    }
    try {
      const saved = localStorage.getItem(STORAGE_KEY);
      if (saved === "ja" || saved === "en") {
        return saved;
      }
    } catch (_) {
      // Ignore storage errors in restricted contexts
    }
    const browserLang = (navigator.language || "ja").toLowerCase();
    return browserLang.startsWith("ja") ? "ja" : "en";
  }

  function applyLang(lang) {
    document.documentElement.setAttribute("data-lang", lang);
    document.documentElement.setAttribute("lang", lang);

    const buttons = document.querySelectorAll("[data-set-lang]");
    buttons.forEach((btn) => {
      const active = btn.getAttribute("data-set-lang") === lang;
      btn.setAttribute("aria-pressed", active ? "true" : "false");
    });

    const titleJa = document.documentElement.getAttribute("data-title-ja");
    const titleEn = document.documentElement.getAttribute("data-title-en");
    if (lang === "ja" && titleJa) document.title = titleJa;
    if (lang === "en" && titleEn) document.title = titleEn;

    try {
      localStorage.setItem(STORAGE_KEY, lang);
    } catch (_) {
      // Ignore storage errors
    }
  }

  function initLanguageSwitcher() {
    applyLang(detectInitialLang());
    document.querySelectorAll("[data-set-lang]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const lang = btn.getAttribute("data-set-lang");
        if (lang === "ja" || lang === "en") {
          applyLang(lang);
        }
      });
    });
  }

  function initInteractiveShelf() {
    const shelfWindow = document.getElementById("shelf-preview");
    if (!shelfWindow) return;

    // Style buttons
    document.querySelectorAll("[data-shelf-style]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const val = btn.getAttribute("data-shelf-style");
        shelfWindow.setAttribute("data-style", val);
        document.querySelectorAll("[data-shelf-style]").forEach((b) => {
          b.setAttribute("aria-pressed", b === btn ? "true" : "false");
        });
      });
    });

    // Wood swatches
    document.querySelectorAll("[data-shelf-wood]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const val = btn.getAttribute("data-shelf-wood");
        shelfWindow.setAttribute("data-wood", val);
        document.querySelectorAll("[data-shelf-wood]").forEach((b) => {
          b.setAttribute("aria-pressed", b === btn ? "true" : "false");
        });
      });
    });

    // Wall swatches
    document.querySelectorAll("[data-shelf-wall]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const val = btn.getAttribute("data-shelf-wall");
        shelfWindow.setAttribute("data-wall", val);
        document.querySelectorAll("[data-shelf-wall]").forEach((b) => {
          b.setAttribute("aria-pressed", b === btn ? "true" : "false");
        });
      });
    });

    // Vintage wear toggle
    const vintageBtn = document.getElementById("toggle-vintage");
    if (vintageBtn) {
      vintageBtn.addEventListener("click", () => {
        const next = shelfWindow.getAttribute("data-vintage") !== "true";
        shelfWindow.setAttribute("data-vintage", next ? "true" : "false");
        vintageBtn.setAttribute("aria-pressed", next ? "true" : "false");
      });
    }

    // Record sleeve click-to-play demo
    const statusJa = document.getElementById("now-playing-ja");
    const statusEn = document.getElementById("now-playing-en");
    const sleeves = shelfWindow.querySelectorAll(".record-sleeve");

    sleeves.forEach((sleeve) => {
      sleeve.addEventListener("click", () => {
        const alreadyPlaying = sleeve.classList.contains("is-playing");
        sleeves.forEach((s) => s.classList.remove("is-playing"));

        if (alreadyPlaying) {
          if (statusJa) statusJa.innerHTML = "レコードをクリックすると再生イメージを体験できます";
          if (statusEn) statusEn.innerHTML = "Click any sleeve to preview one-click playback";
          return;
        }

        sleeve.classList.add("is-playing");
        const album = sleeve.getAttribute("data-album") || "";
        const artist = sleeve.getAttribute("data-artist") || "";
        const service = sleeve.getAttribute("data-service") || "Apple Music";

        if (statusJa) {
          statusJa.innerHTML = `再生中: <strong>${album}</strong> — ${artist} (${service})`;
        }
        if (statusEn) {
          statusEn.innerHTML = `Now Playing: <strong>${album}</strong> — ${artist} (${service})`;
        }
      });
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    initLanguageSwitcher();
    initInteractiveShelf();
  });
})();
