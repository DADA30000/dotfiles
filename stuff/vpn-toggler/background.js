const API_URL = "http://127.0.0.1:9090/proxies/zen-toggle";
const CONNECTIONS_URL = "http://127.0.0.1:9090/connections";

async function updateIcon(state) {
    const iconPath = state === "direct" ? "icon-direct.svg" : "icon-proxy.svg";
    await browser.action.setIcon({ path: iconPath });
    await browser.action.setTitle({ title: `sing-box: ${state.toUpperCase()}` });
}

async function killZenConnections() {
    try {
        const res = await fetch(CONNECTIONS_URL);
        const data = await res.json();
        const connections = data.connections || [];
        
        for (const conn of connections) {
            const isZenToggle = conn.chains && conn.chains.includes("zen-toggle");
            const isZenProcess = conn.metadata && conn.metadata.processPath && 
                                 conn.metadata.processPath.toLowerCase().includes("zen");
            
            if (isZenToggle || isZenProcess) {
                await fetch(`${CONNECTIONS_URL}/${conn.id}`, { method: 'DELETE' });
            }
        }
    } catch (e) {
        console.error("Failed to drop connections:", e);
    }
}

browser.action.onClicked.addListener(async () => {
    try {
        const res = await fetch(API_URL);
        const data = await res.json();
        const newState = data.now === "direct" ? "proxy" : "direct";

        await fetch(API_URL, {
            method: 'PUT',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ name: newState })
        });

        await killZenConnections();

        updateIcon(newState);
    } catch (e) {
        console.error("sing-box API offline or unreachable.", e);
    }
});

fetch(API_URL)
    .then(res => res.json())
    .then(data => updateIcon(data.now))
    .catch(() => console.log("sing-box not running yet."));
