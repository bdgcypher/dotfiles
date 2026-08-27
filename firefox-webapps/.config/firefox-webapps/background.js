// Hypr Web Apps background script.
//
// hypr-firefox-pwa triggers launches by opening a reserved URL
// (https://hypr-webapps.invalid/launch?url=...) as a new window. This script
// intercepts that navigation, opens the real URL as a chromeless popup window
// in the default profile (shared logins), and closes the transient launcher
// tab. New tabs opened inside a web app window are routed to a normal browser
// window so links are never hidden behind the popup's missing tab bar.

const webapps = new Map(); // windowId -> { appUrl, appTabId }

browser.runtime.onMessage.addListener(async (msg) => {
  if (msg && msg.type === "register-webapp") {
    webapps.set(msg.windowId, { appUrl: msg.appUrl, appTabId: msg.appTabId });
    await browser.storage.local.set({ webapps: [...webapps.entries()] });
    return { ok: true };
  }
  return undefined;
});

browser.windows.onRemoved.addListener((windowId) => {
  if (webapps.delete(windowId)) {
    browser.storage.local.set({ webapps: [...webapps.entries()] }).catch(() => {});
  }
});

browser.storage.local.get("webapps").then((data) => {
  for (const [id, info] of data.webapps || []) webapps.set(id, info);
}).catch(() => {});

function sameOrigin(a, b) {
  try {
    return new URL(a).origin === new URL(b).origin;
  } catch (e) {
    return false;
  }
}

function openInMainBrowser(url) {
  return browser.windows.getAll({ windowTypes: ["normal"], populate: true }).then((wins) => {
    // Prefer the window with the most tabs (the main browser window).
    wins.sort((a, b) => (b.tabs ? b.tabs.length : 0) - (a.tabs ? a.tabs.length : 0));
    const target = wins[0];
    return target && target.tabs && target.tabs.length
      ? browser.tabs.create({ windowId: target.id, url, active: true })
      : browser.windows.create({ url, type: "normal", focused: true });
  });
}

function routeTab(tab) {
  const info = webapps.get(tab.windowId);
  if (!info) return;
  if (tab.id === info.appTabId) return; // the app's own initial tab
  // Give pendingUrl a moment to populate, then decide.
  setTimeout(() => {
    browser.tabs.get(tab.id).then((t) => {
      if (!t) return;
      const url = t.url || t.pendingUrl || "";
      if (!url || url.startsWith("about:")) return;
      if (sameOrigin(url, info.appUrl)) return; // internal app navigation
      openInMainBrowser(url)
        .then(() => browser.tabs.remove(tab.id))
        .catch(() => {});
    }).catch(() => {});
  }, 150);
}

browser.tabs.onCreated.addListener((tab) => {
  if (webapps.has(tab.windowId)) routeTab(tab);
});

// Launch trigger: intercept the reserved URL and turn it into a popup window.
browser.webRequest.onBeforeRequest.addListener((details) => {
  let target = "";
  try {
    target = new URL(details.url).searchParams.get("url") || "";
  } catch (e) {}
  if (target) {
    browser.windows.create({
      url: target,
      type: "popup",
      width: 1280,
      height: 800,
      focused: true,
    }).then(async (win) => {
      const tabs = await browser.tabs.query({ windowId: win.id });
      webapps.set(win.id, {
        appUrl: target,
        appTabId: tabs.length ? tabs[0].id : undefined,
      });
      await browser.storage.local.set({ webapps: [...webapps.entries()] });
    }).catch(() => {});
  }
  if (details.tabId >= 0) {
    browser.tabs.remove(details.tabId).catch(() => {});
  }
  return { cancel: true };
}, { urls: ["https://hypr-webapps.invalid/*"] }, ["blocking"]);
