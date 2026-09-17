(() => {
  "use strict";

  const config = window.CROOKCOOKED_SITE_CONFIG || {};

  function pagesRepositoryURL() {
    if (!location.hostname.endsWith(".github.io")) return "";
    const owner = location.hostname.slice(0, -".github.io".length);
    const repository = location.pathname.split("/").filter(Boolean)[0];
    return owner && repository ? `https://github.com/${owner}/${repository}` : "";
  }

  const repositoryURL = (config.repositoryURL || pagesRepositoryURL()).replace(/\/+$/, "");
  const downloadURL = config.downloadURL || (repositoryURL
    ? `${repositoryURL}/releases/latest/download/crookcooked-mac.zip`
    : "");

  function configureLinks(selector, url, unavailableLabel) {
    for (const link of document.querySelectorAll(selector)) {
      if (url) {
        link.href = url;
        link.rel = "noopener noreferrer";
      } else if (link.classList.contains("button")) {
        link.removeAttribute("href");
        link.setAttribute("aria-disabled", "true");
        link.classList.add("button-disabled");
        link.textContent = unavailableLabel;
      }
    }
  }

  configureLinks(".source-link", repositoryURL, "Source URL not configured");
  configureLinks(".download-link", downloadURL, "Release download coming soon");

  const linkNote = document.querySelector("[data-link-note]");
  if (linkNote && !repositoryURL) {
    linkNote.textContent = "Set repositoryURL in site-config.js before publishing on a custom domain.";
  }

  const year = document.querySelector("#year");
  if (year) year.textContent = String(new Date().getFullYear());
})();
