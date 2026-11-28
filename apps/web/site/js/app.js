/* ==========================================================================
   Sleeves Website — Language Switcher
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

  document.addEventListener("DOMContentLoaded", () => {
    applyLang(detectInitialLang());
    document.querySelectorAll("[data-set-lang]").forEach((btn) => {
      btn.addEventListener("click", () => {
        const lang = btn.getAttribute("data-set-lang");
        if (lang === "ja" || lang === "en") {
          applyLang(lang);
        }
      });
    });
  });
})();
