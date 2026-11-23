import streamDeck, {
    action, type DidReceiveSettingsEvent, type KeyAction, type KeyDownEvent,
    type SendToPluginEvent, SingletonAction, type WillAppearEvent, type WillDisappearEvent
} from "@elgato/streamdeck";

type Settings = { filename?: string; preview?: boolean };
type Status = { playingFilename: string | null; isLowered: boolean; remainingSeconds?: number | null };
type Kind = "jingle" | "fade" | "countdown";
type VisibleKey = {
    key: KeyAction<Settings>;
    kind: Kind;
    settings: Settings;
    display?: 0 | 1 | string;
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

function countdownTitle(status?: Status): string {
    const seconds = status?.remainingSeconds;
    if (!status?.playingFilename || typeof seconds !== "number" || !Number.isSafeInteger(seconds) || seconds < 0) {
        return "";
    }
    return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
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
                    const title = countdownTitle(status);
                    if (entry.display !== title) {
                        await entry.key.setTitle(title);
                        entry.display = title;
                    }
                    continue;
                }
                const active = entry.kind === "fade"
                    ? status?.isLowered === true
                    : typeof status?.playingFilename === "string" && status.playingFilename === entry.settings.filename;
                const state = active ? 1 : 0;
                if (entry.display !== state) {
                    await entry.key.setState(state);
                    entry.display = state;
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
        if (this.kind === "countdown") return;
        const { settings } = payload;
        const path = this.kind === "fade" ? "/fade"
            : settings.filename ? `/play/${encodeURIComponent(settings.filename)}` : undefined;
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
