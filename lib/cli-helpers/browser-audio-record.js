(() => {
    "use strict";

    if (window !== window.top) return;

    const mount = () => {
        const host = document.createElement("div");
        host.id = "browser-audio-recorder";
        host.style.cssText =
            "all:initial;position:fixed;top:12px;right:12px;z-index:2147483647";
        const shadow = host.attachShadow({mode: "closed"});
        const button = document.createElement("button");
        button.type = "button";
        button.disabled = true;
        button.textContent = "Connecting audio recorder…";
        button.style.cssText = [
            "all:initial", "box-sizing:border-box", "display:block", "margin-left:auto",
            "padding:8px 12px", "border:1px solid #667085", "border-radius:8px",
            "background:#202631", "color:white", "font:600 13px system-ui,sans-serif",
            "box-shadow:0 2px 8px #0005", "cursor:pointer", "outline:revert",
        ].join(";");
        const notice = document.createElement("div");
        notice.setAttribute("role", "status");
        notice.style.cssText = [
            "display:none", "margin-top:5px", "max-width:280px", "padding:6px 9px",
            "border-radius:6px", "background:#202631", "color:white",
            "font:12px system-ui,sans-serif", "overflow-wrap:anywhere",
        ].join(";");
        shadow.append(button, notice);

        globalThis.setBrowserAudioStatus = (active, message) => {
            button.disabled = false;
            button.style.background = active ? "#a52132" : "#202631";
            button.textContent = active ? "■ Stop recording" : "● Start recording";
            button.setAttribute("aria-pressed", String(active));
            notice.textContent = message;
            notice.style.display = message ? "block" : "none";
        };
        button.addEventListener("click", (event) => {
            if (!event.isTrusted) return;
            event.stopPropagation();
            button.disabled = true;
            browserAudioControl("toggle");
        });

        document.documentElement.append(host);
        browserAudioControl("ready");
        window.addEventListener("pageshow", (event) => {
            if (event.persisted) browserAudioControl("ready");
        });
    };

    if (document.readyState === "loading") {
        document.addEventListener("DOMContentLoaded", mount, {once: true});
    } else {
        mount();
    }
})();
