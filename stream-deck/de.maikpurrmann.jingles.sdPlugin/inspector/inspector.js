const app = document.getElementById("app");
const filename = document.getElementById("filename");
const keyTitle = document.getElementById("key-title");
const reload = document.getElementById("reload");
const status = document.getElementById("status");

window.connectElgatoStreamDeckSocket = (port, uuid, registrationEvent, _info, actionInfo) => {
    const { action, payload } = JSON.parse(actionInfo);
    const isJingle = action === "de.maikpurrmann.jingles.jingle";
    const settings = { ...payload.settings };
    let latestRequest;
    let requestTimeout;
    const socket = new WebSocket(`ws://127.0.0.1:${port}`);

    document.getElementById("jingle").hidden = !isJingle;
    app.value = settings.preview ? "preview" : "release";

    // Stream Deck maps the registered inspector UUID to the selected action.
    const send = (event, payload) => socket.send(JSON.stringify({ event, action, context: uuid, payload }));

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

    function showKeyTitle() {
        keyTitle.value = settings.keyTitle ?? settings.filename ?? "";
        keyTitle.disabled = socket.readyState !== WebSocket.OPEN || !settings.filename;
    }

    function loadFilenames() {
        if (!isJingle) return;
        latestRequest = crypto.randomUUID();
        status.textContent = "Lade Einspieler …";
        clearTimeout(requestTimeout);
        requestTimeout = setTimeout(() => {
            status.textContent = "Keine Antwort vom Stream-Deck-Plugin. Lade die Liste erneut.";
        }, 2000);
        send("sendToPlugin", { requestId: latestRequest, preview: settings.preview === true });
    }

    showFilenames(null);
    showKeyTitle();

    socket.onopen = () => {
        socket.send(JSON.stringify({ event: registrationEvent, uuid }));
        app.disabled = false;
        reload.disabled = false;
        showKeyTitle();
        loadFilenames();
    };

    socket.onmessage = ({ data }) => {
        const message = JSON.parse(data);
        if (message.event !== "sendToPropertyInspector" || message.payload.requestId !== latestRequest) return;
        clearTimeout(requestTimeout);
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
        showKeyTitle();
        send("setSettings", settings);
    };
    keyTitle.onchange = () => {
        const value = keyTitle.value.trim();
        if (value && value !== settings.filename) settings.keyTitle = value;
        else delete settings.keyTitle;
        showKeyTitle();
        send("setSettings", settings);
    };
    keyTitle.onkeydown = (event) => {
        if (event.key === "Enter") keyTitle.blur();
    };
    reload.onclick = loadFilenames;
};
