/* ==========================================================================
   HOCCO PM TOOL — theme lock
   Loaded first in <head>, before the stylesheet, so the theme is set before
   the first paint (no flash). Resolution order:
     1. ?theme=light|dark in the URL  (how the presentation files enter)
     2. a saved choice in localStorage
     3. the operating-system preference
   A theme chosen by (1) or (2) is "forced": every in-app link then carries it,
   so clicking through the prototype stays locked to one theme — even from a
   file:// double-click where localStorage may be unavailable.
   ========================================================================== */
(function () {
  var root = document.documentElement;

  function readParam() {
    try {
      var m = location.search.match(/[?&]theme=(light|dark)\b/);
      return m ? m[1] : null;
    } catch (e) { return null; }
  }
  function readStore() {
    try { return localStorage.getItem("hocco-theme"); } catch (e) { return null; }
  }
  function systemTheme() {
    try {
      return window.matchMedia("(prefers-color-scheme: dark)").matches ? "dark" : "light";
    } catch (e) { return "light"; }
  }

  var param = readParam();
  if (param) { try { localStorage.setItem("hocco-theme", param); } catch (e) {} }

  var stored = param || readStore();
  var theme = stored || systemTheme();
  var forced = !!stored;   /* explicit choice vs. following the OS */

  root.setAttribute("data-theme", theme);
  if (forced) root.setAttribute("data-theme-forced", "1");
  /* Colour-scheme hint so native form controls / scrollbars match. */
  root.style.colorScheme = theme;

  /* When forced, thread the theme onto every internal navigation so it never
     drops between screens. Capture phase, so it runs before the link fires. */
  if (forced) {
    document.addEventListener("click", function (e) {
      var a = e.target.closest && e.target.closest("a[href]");
      if (!a) return;
      var href = a.getAttribute("href");
      if (!href || href.charAt(0) === "#") return;
      if (/^(https?:|mailto:|tel:|javascript:)/i.test(href)) return;
      if (!/\.html(\?|#|$)/.test(href)) return;
      if (/[?&]theme=/.test(href)) return;
      a.setAttribute("href", href + (href.indexOf("?") > -1 ? "&" : "?") + "theme=" + theme);
    }, true);
  }

  /* Expose for any UI that wants to show or change the current theme. */
  window.HoccoTheme = {
    current: theme,
    forced: forced,
    set: function (t) {
      try { localStorage.setItem("hocco-theme", t); } catch (e) {}
      location.search = "?theme=" + t;
    }
  };
})();
