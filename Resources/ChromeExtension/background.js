// Valora-only Chrome handoff. It never reads cookies, tokens, page contents or
// Chrome history. A download is handed to the signed Valora native host only
// after the host confirms the Valora app and bridge are available; otherwise
// Chrome keeps the download and the extension shows why it was not taken over.
const NATIVE_HOST = "com.wangqing.valora.chrome";
const PROTOCOL_VERSION = 1;
const MAX_URL_LENGTH = 16384;
// Overridable only by the isolated Node fixture; production uses 8 seconds.
const NATIVE_DEADLINE_MS = Number(globalThis.__valoraNativeDeadlineMs) || 8000;

function isHTTPURL(value) {
  try {
    const url = new URL(value);
    return (url.protocol === "http:" || url.protocol === "https:") &&
      Boolean(url.hostname) && !url.username && !url.password &&
      value.length <= MAX_URL_LENGTH;
  } catch {
    return false;
  }
}

// Every native call has a finite deadline. A callback that arrives after the
// deadline is ignored by the `done` latch, so it cannot cancel a download that
// already fell back to Chrome.
function nativeRequest(message) {
  return new Promise((resolve) => {
    let done = false;
    let timer = null;
    const finish = (value) => {
      if (done) return;
      done = true;
      if (timer !== null) clearTimeout(timer);
      resolve(value);
    };
    timer = setTimeout(() => finish({
      ok: false, timeout: true, error: "Valora native host did not respond"
    }), NATIVE_DEADLINE_MS);
    try {
      chrome.runtime.sendNativeMessage(NATIVE_HOST, message, (response) => {
        const error = chrome.runtime.lastError;
        if (error) {
          finish({
            ok: false,
            hostMissing: /not found|no such native/i.test(error.message || ""),
            error: error.message
          });
        } else {
          finish(response || { ok: false, error: "Valora returned no response" });
        }
      });
    } catch (error) {
      finish({ ok: false, error: String(error) });
    }
  });
}

function isValoraStatus(response) {
  return response?.ok === true &&
    response.appRunning === true &&
    response.bridgeEnabled === true &&
    response.protocolVersion === PROTOCOL_VERSION &&
    response.app === "Valora";
}

function isValoraAccepted(response) {
  return response?.ok === true &&
    response.accepted === true &&
    response.protocolVersion === PROTOCOL_VERSION &&
    response.app === "Valora";
}

function notify(title, message) {
  chrome.notifications.create({
    type: "basic",
    iconUrl: chrome.runtime.getURL("icon128.png"),
    title: title,
    message: message
  });
}

async function notifyUnavailable(response) {
  if (response?.hostMissing) {
    notify("Valora 下载未启用", "请先在 Valora 设置的下载页完成 Chrome 扩展与本地桥接设置。Chrome 已保留这次下载。");
  } else if (response?.timeout) {
    notify("Valora 没有响应", "Chrome 已保留下载；请在 Valora 设置中检查本地桥接。");
  } else if (response?.appRunning === true && response?.bridgeEnabled === false) {
    notify("Valora 下载功能未开启", "Valora 正在运行，但下载功能或本地桥接未开启。Chrome 已保留这次下载。");
  } else {
    notify("Valora 未运行", "请打开 Valora 后重试。Chrome 已保留这次下载。");
  }
}

async function handoff(url, referrer) {
  if (!isHTTPURL(url)) {
    return { ok: false, error: "only-http" };
  }
  return nativeRequest({
    type: "download",
    protocolVersion: PROTOCOL_VERSION,
    url: url,
    referrer: referrer && isHTTPURL(referrer) ? referrer : undefined
  });
}

function createMenus() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: "valora-download-link",
      title: "使用 Valora 下载",
      contexts: ["link"]
    });
  });
}

chrome.runtime.onInstalled.addListener(createMenus);
chrome.runtime.onStartup.addListener(createMenus);

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== "valora-download-link") return;
  const url = info.linkUrl || info.srcUrl;
  if (!isHTTPURL(url)) {
    notify("Valora 下载未启用", "只支持 HTTP(S) 链接。");
    return;
  }
  const status = await nativeRequest({ type: "status", protocolVersion: PROTOCOL_VERSION });
  if (!isValoraStatus(status)) {
    await notifyUnavailable(status);
    return;
  }
  const response = await handoff(url, tab?.url);
  if (!isValoraAccepted(response)) {
    await notifyUnavailable(response);
  }
});

// Chrome requires every onDeterminingFilename listener to call suggest()
// exactly once. `settle` is the single atomic gate for every branch: success
// calls it after the Chrome cancel callback, a failed/timed-out handoff calls
// it while leaving the download with Chrome, and a late native/cancel callback
// is ignored. See:
// https://developer.chrome.com/docs/extensions/reference/api/downloads#event-onDeterminingFilename
chrome.downloads.onDeterminingFilename.addListener((item, suggest) => {
  let settled = false;
  const settle = () => {
    if (settled) return;
    settled = true;
    suggest();
  };

  const url = item.finalUrl || item.url;
  if (!isHTTPURL(url)) { settle(); return true; }
  if (item.byExtensionId === chrome.runtime.id) { settle(); return true; }
  if (item.state !== "in_progress") { settle(); return true; }
  const started = item.startTime ? new Date(item.startTime).getTime() : 0;
  const age = Date.now() - started;
  if (!started || age > 30000 || age < 0) { settle(); return true; }

  (async () => {
    const status = await nativeRequest({ type: "status", protocolVersion: PROTOCOL_VERSION });
    if (!isValoraStatus(status)) {
      await notifyUnavailable(status);
      settle();
      return;
    }

    const accepted = await handoff(url, item.referrer);
    if (!isValoraAccepted(accepted)) {
      await notifyUnavailable(accepted);
      settle();
      return;
    }

    // Valora accepted the request. Transfer ownership only after Chrome's
    // cancel callback. If cancel fails, never erase the still-valid Chrome
    // history row and tell the user it can be recovered from Chrome.
    let cancelSettled = false;
    const cancelDeadline = setTimeout(() => {
      if (cancelSettled || settled) return;
      cancelSettled = true;
      notify("Chrome 下载仍在进行", "Valora 已接收，但 Chrome 没有完成取消。请在原下载处重试或检查 Chrome 下载列表。");
      settle();
    }, NATIVE_DEADLINE_MS);
    try {
      chrome.downloads.cancel(item.id, () => {
        if (cancelSettled || settled) return;
        cancelSettled = true;
        clearTimeout(cancelDeadline);
        const error = chrome.runtime.lastError;
        if (error) {
          notify("Chrome 下载仍在进行", "Valora 已接收，但 Chrome 取消失败。Chrome 下载记录已保留，可重试或手动处理。");
          settle();
          return;
        }
        try {
          chrome.downloads.erase({ id: item.id });
        } catch (eraseError) {
          console.error("Valora could not erase the cancelled Chrome row", eraseError);
        }
        settle();
      });
    } catch (error) {
      if (!cancelSettled && !settled) {
        cancelSettled = true;
        clearTimeout(cancelDeadline);
        notify("Chrome 下载仍在进行", "Valora 已接收，但 Chrome 取消失败。Chrome 下载记录已保留。");
        settle();
      }
    }
  })().catch((error) => {
    console.error("Valora handoff failed; leaving the download with Chrome", error);
    settle();
  });
  return true;
});

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  if (message?.type !== "valoraStatus") return false;
  nativeRequest({ type: "status", protocolVersion: PROTOCOL_VERSION }).then(sendResponse);
  return true;
});
