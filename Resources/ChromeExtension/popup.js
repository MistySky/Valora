const NATIVE_HOST = "com.wangqing.valora.chrome";
const PROTOCOL_VERSION = 1;
const NATIVE_DEADLINE_MS = 5000;
const dot = document.getElementById("dot");
const status = document.getElementById("status");
const open = document.getElementById("open");
const settings = document.getElementById("settings");

function request(message) {
  return new Promise((resolve) => {
    let done = false;
    let timer = null;
    const finish = (value) => {
      if (done) return;
      done = true;
      if (timer !== null) clearTimeout(timer);
      resolve(value);
    };
    timer = setTimeout(() => finish({ ok: false, timeout: true, error: "Valora native host did not respond" }),
                       NATIVE_DEADLINE_MS);
    try {
      chrome.runtime.sendNativeMessage(NATIVE_HOST, message, (response) => {
        const error = chrome.runtime.lastError;
        if (error) {
          finish({ ok: false, hostMissing: /not found|no such native/i.test(error.message || ""), error: error.message });
        } else {
          finish(response || { ok: false, error: "Valora returned no response" });
        }
      });
    } catch (error) {
      finish({ ok: false, error: String(error) });
    }
  });
}

function render(response) {
  const connected = response?.ok === true &&
    response.appRunning === true &&
    response.bridgeEnabled === true &&
    response.protocolVersion === PROTOCOL_VERSION &&
    response.app === "Valora";
  dot.className = "dot " + (connected ? "on" : "off");
  open.disabled = false;
  if (connected) {
    status.textContent = "已连接 Valora " + (response.appVersion || "");
    open.hidden = true;
  } else if (response?.hostMissing) {
    status.textContent = "尚未完成 Valora 本地桥接设置";
    open.hidden = true;
  } else if (response?.timeout) {
    status.textContent = "Valora 没有响应；请检查本地桥接";
    open.hidden = false;
    open.textContent = "打开 Valora";
  } else if (response?.appRunning === true && response?.bridgeEnabled === false) {
    status.textContent = "Valora 已运行，但下载功能或本地桥接未开启";
    open.hidden = false;
    open.textContent = "打开 Valora";
  } else if (response?.appRunning === false) {
    status.textContent = "Valora 未运行";
    open.hidden = false;
    open.textContent = "打开 Valora";
  } else {
    status.textContent = "Valora 桥接版本不匹配或未就绪";
    open.hidden = false;
    open.textContent = "打开 Valora";
  }
}

async function refresh() {
  render(await request({ type: "status", protocolVersion: PROTOCOL_VERSION }));
}

open.addEventListener("click", async () => {
  if (open.disabled || open.hidden) return;
  open.disabled = true;
  await request({ type: "launchApp", protocolVersion: PROTOCOL_VERSION });
  open.disabled = false;
  setTimeout(refresh, 500);
});

settings.addEventListener("click", () => {
  chrome.tabs.create({ url: "chrome://extensions" });
  window.close();
});
refresh();
