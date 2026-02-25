const API_URL = "http://127.0.0.1:9090/proxies/zen-toggle";
const CONNECTIONS_URL = "http://127.0.0.1:9090/connections";

async function updateIcon(state) {
    const isProxy = (state !== "direct"); 
    const titleText = isProxy ? "VPN active" : "Direct mode";
    
    try {
        await browser.browserAction.setTitle({ title: titleText });
    } catch (e) { /* ignore */ }

    try {
        const svgPath = isProxy ? "icon-proxy.svg" : "icon-direct.svg";
        await browser.browserAction.setIcon({ path: svgPath });
    } catch (e1) {
        try {
            const pngPath = isProxy ? "icon-proxy.png" : "icon-direct.png";
            await browser.browserAction.setIcon({ path: pngPath });
        } catch (e2) { /* ignore */ }
    }
}

async function killZenConnections() {
    try {
        const res = await fetch(CONNECTIONS_URL, { cache: "no-store" });
        const data = await res.json();
        const connections = data.connections || [];
        
        for (const conn of connections) {
            const isZenToggle = conn.chains && conn.chains.includes("zen-toggle");
            const isZenProcess = conn.metadata && conn.metadata.processPath && 
                                 conn.metadata.processPath.toLowerCase().includes("zen");
            
            if (isZenToggle || isZenProcess) {
                fetch(`${CONNECTIONS_URL}/${conn.id}`, { method: 'DELETE' }).catch(() => {});
            }
        }
    } catch (e) {
        console.error("Connection kill error:", e);
    }
}

async function checkStatus() {
    try {
        const res = await fetch(API_URL, { cache: "no-store" });
        const data = await res.json();
        await updateIcon(data.now);
    } catch (e) {
        await updateIcon("direct");
    }
}

// Click Handler
browser.browserAction.onClicked.addListener(async () => {
    try {
        const res = await fetch(API_URL, { cache: "no-store" });
        const data = await res.json();
        
        const newState = (data.now === "direct") ? "proxy" : "direct"; 

        await updateIcon(newState);

        await fetch(API_URL, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name: newState })
        });

        await killZenConnections();
        
    } catch (e) {
        console.error("Toggle failed:", e);
    }
});

checkStatus();

setInterval(checkStatus, 500);
