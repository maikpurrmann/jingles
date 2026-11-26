import streamDeck, {
    action, type DidReceiveSettingsEvent, type KeyAction, type KeyDownEvent,
    type SendToPluginEvent, SingletonAction, Target, type WillAppearEvent, type WillDisappearEvent
} from "@elgato/streamdeck";

type Settings = { filename?: string; preview?: boolean };
type Status = {
    playingFilename: string | null;
    isLowered: boolean;
    remainingSeconds?: number | null;
    pausedRemainingSeconds?: number | null;
    playbackProgress?: number | null;
};
type Kind = "jingle" | "fade" | "countdown";
type VisibleKey = {
    key: KeyAction<Settings>;
    kind: Kind;
    settings: Settings;
    fadeActive?: boolean;
    countdownPaused?: boolean;
    progressStep?: number;
    title?: string;
};

const ports = [17639, 17640] as const;
const portFor = (settings: Settings) => settings.preview === true ? 17640 : 17639;

async function request(port: number, path: string): Promise<Response> {
    const response = await fetch(`http://127.0.0.1:${port}${path}`, {
        signal: AbortSignal.timeout(700),
        redirect: "error"
    });
    if (!response.ok) {
        await response.body?.cancel();
        throw new Error(`Jingles HTTP ${response.status}`);
    }
    return response;
}

const visibleKeys = new Map<string, VisibleKey>();
let nextPoll: ReturnType<typeof setTimeout> | undefined;
let polling = false;

function schedulePoll(delay: number): void {
    if (polling || nextPoll !== undefined || visibleKeys.size === 0) return;
    nextPoll = setTimeout(() => {
        nextPoll = undefined;
        void poll();
    }, delay);
}

function countdownTitle(seconds?: number | null): string {
    if (typeof seconds !== "number" || !Number.isSafeInteger(seconds) || seconds < 0) {
        return "0:00";
    }
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
}

const progressSteps = 40;
const borderLength = 4 * (25 + 2 * Math.PI);

function progressBorder(step: number): string {
    // The rounded square starts at the top center and runs clockwise.
    const elapsed = borderLength * step / progressSteps;
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="144" height="144" viewBox="0 0 36 36">
        <rect width="36" height="36" fill="#000"/>
        <path d="M18 1.5 H30.5 A4 4 0 0 1 34.5 5.5 V30.5 A4 4 0 0 1 30.5 34.5 H5.5
                 A4 4 0 0 1 1.5 30.5 V5.5 A4 4 0 0 1 5.5 1.5 H18"
              fill="none" stroke="#38d58d" stroke-width="2.5" stroke-linecap="round"
              stroke-dasharray="${(borderLength - elapsed).toFixed(3)} ${borderLength.toFixed(3)}"
              stroke-dashoffset="${(-elapsed).toFixed(3)}"/>
    </svg>`;
    return `data:image/svg+xml,${encodeURIComponent(svg)}`;
}

async function poll(): Promise<void> {
    polling = true;
    try {
        await Promise.all(ports.map(async (port) => {
            if (![...visibleKeys.values()].some(({ settings }) => portFor(settings) === port)) return;
            let status: Status | undefined;
            try {
                const response = await request(port, "/status");
                status = await response.json() as Status;
            } catch {
                // A closed or older copy of Jingles leaves its keys idle.
            }
            for (const entry of visibleKeys.values()) {
                if (portFor(entry.settings) !== port) continue;
                if (entry.kind === "countdown") {
                    const pausedSeconds = status?.pausedRemainingSeconds;
                    const paused = typeof pausedSeconds === "number";
                    const title = countdownTitle(pausedSeconds ?? (status?.playingFilename ? status.remainingSeconds : null));
                    if (entry.title !== title) {
                        await entry.key.setTitle(title);
                        entry.title = title;
                    }
                    if (entry.countdownPaused !== paused) {
                        await entry.key.setImage(paused ? "images/fade-on.svg" : undefined, { target: Target.HardwareAndSoftware });
                        entry.countdownPaused = paused;
                    }
                    continue;
                }
                if (entry.kind === "jingle") {
                    const active = typeof status?.playingFilename === "string"
                        && status.playingFilename === entry.settings.filename;
                    const progress = status?.playbackProgress;
                    let step = -1;
                    if (active) {
                        step = typeof progress === "number" && Number.isFinite(progress)
                            ? Math.min(progressSteps - 1, Math.max(0, Math.floor(progress * progressSteps)))
                            : 0;
                    }
                    if (entry.progressStep !== step) {
                        const image = step < 0 ? undefined : step === 0 ? "images/jingle-on.svg" : progressBorder(step);
                        await entry.key.setImage(image, { target: Target.HardwareAndSoftware });
                        entry.progressStep = step;
                    }
                    continue;
                }
                const fadeActive = status?.isLowered === true;
                if (entry.fadeActive !== fadeActive) {
                    const image = fadeActive ? "images/fade-on.svg" : undefined;
                    await entry.key.setImage(image, { target: Target.HardwareAndSoftware });
                    entry.fadeActive = fadeActive;
                }
            }
        }));
    } catch (error) {
        streamDeck.logger.warn("Tastenstatus konnte nicht aktualisiert werden:", error);
    } finally {
        polling = false;
        schedulePoll(200);
    }
}

abstract class JinglesAction extends SingletonAction<Settings> {
    abstract readonly kind: Kind;

    override onWillAppear({ action: key, payload }: WillAppearEvent<Settings>): void {
        if (!key.isKey()) return;
        visibleKeys.set(key.id, { key, kind: this.kind, settings: payload.settings });
        schedulePoll(0);
    }

    override onWillDisappear(event: WillDisappearEvent<Settings>): void {
        visibleKeys.delete(event.action.id);
        if (visibleKeys.size === 0) {
            clearTimeout(nextPoll);
            nextPoll = undefined;
        }
    }

    override onDidReceiveSettings(event: DidReceiveSettingsEvent<Settings>): void {
        const entry = visibleKeys.get(event.action.id);
        if (entry) entry.settings = event.payload.settings;
        schedulePoll(0);
    }

    override async onKeyDown({ action: key, payload }: KeyDownEvent<Settings>): Promise<void> {
        const { settings } = payload;
        let path: string | undefined;
        switch (this.kind) {
            case "countdown": path = "/pause-toggle"; break;
            case "fade": path = "/fade"; break;
            case "jingle":
                if (settings.filename) path = `/play/${encodeURIComponent(settings.filename)}`;
                break;
        }
        if (!path) {
            await key.showAlert();
            return;
        }
        try {
            const response = await request(portFor(settings), path);
            await response.text();
        } catch {
            await key.showAlert();
        }
    }
}

@action({ UUID: "de.maikpurrmann.jingles.jingle" })
class JingleAction extends JinglesAction {
    readonly kind = "jingle";

    override async onSendToPlugin(event: SendToPluginEvent<{ requestId?: string; preview?: boolean }, Settings>): Promise<void> {
        const { requestId, preview } = event.payload;
        if (typeof requestId !== "string") return;
        let filenames: string[] | null = null;
        try {
            const response = await request(portFor({ preview }), "/jingles");
            ({ filenames } = await response.json() as { filenames: string[] });
        } catch {
            // The inspector displays a connection message and preserves the selected filename.
        }
        await streamDeck.ui.sendToPropertyInspector({ requestId, filenames });
    }
}

@action({ UUID: "de.maikpurrmann.jingles.fade" })
class FadeAction extends JinglesAction {
    readonly kind = "fade";
}

@action({ UUID: "de.maikpurrmann.jingles.countdown" })
class CountdownAction extends JinglesAction {
    readonly kind = "countdown";
}

streamDeck.actions.registerAction(new JingleAction());
streamDeck.actions.registerAction(new FadeAction());
streamDeck.actions.registerAction(new CountdownAction());
streamDeck.connect();
