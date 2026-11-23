const app = document.getElementById("app");
const filename = document.getElementById("filename");
const reload = document.getElementById("reload");
const status = document.getElementById("status");

window.connectElgatoStreamDeckSocket = (port, uuid, registrationEvent, _info, actionInfo) => {
    const { action, context, payload } = JSON.parse(actionInfo);
    const isJingle = action === "de.maikpurrmann.jingles.jingle";
    const settings = { ...payload.settings };
    let latestRequest;
    const socket = new WebSocket(`ws://127.0.0.1:${port}`);

    document.getElementById("jingle").hidden = !isJingle;
    app.value = settings.preview ? "preview" : "release";

    const send = (event, payload) => socket.send(JSON.stringify({ event, action, context, payload }));

    function showFilenames(filenames) {
        filename.replaceChildren(new Option("Einspieler auswählen", ""));
        for (const name of filenames ?? []) {
            filename.add(new Option(name, name));
        }
        if (settings.filename && !filenames?.includes(settings.filename)) {
            const label = filenames ? `${settings.filename} (fehlt)` : settings.filename;
            filename.add(new Option(label, settings.filename));
        }
        filename.value = settings.filename ?? "";
        filename.disabled = !filenames;
    }

    function loadFilenames() {
        if (!isJingle) return;
        latestRequest = crypto.randomUUID();
        status.textContent = "Lade Einspieler …";
        send("sendToPlugin", { requestId: latestRequest, preview: settings.preview === true });
    }

    showFilenames(null);

    socket.onopen = () => {
        socket.send(JSON.stringify({ event: registrationEvent, uuid }));
        app.disabled = false;
        reload.disabled = false;
        loadFilenames();
    };

    socket.onmessage = ({ data }) => {
        const message = JSON.parse(data);
        if (message.event !== "sendToPropertyInspector" || message.payload.requestId !== latestRequest) return;
        const { filenames } = message.payload;
        showFilenames(filenames);
        status.textContent = filenames === null
            ? "Diese Jingles-App ist nicht erreichbar. Öffne die passende Version und lade die Liste neu."
            : filenames.length === 0 ? "Wähle in Jingles einen Ordner mit Einspielern." : "";
    };

    app.onchange = () => {
        settings.preview = app.value === "preview";
        send("setSettings", settings);
        showFilenames(null);
        loadFilenames();
    };

    filename.onchange = () => {
        settings.filename = filename.value;
        send("setSettings", settings);
    };
    reload.onclick = loadFilenames;
};
