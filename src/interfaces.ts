export interface PluginConfig {
    notesAcknowledgedV1: boolean;
    hrirName: string;
    channelCount: number;
    usePerAppProfiles?: boolean;
    // Map an app's display name to its mixer profile
    perAppProfiles?: {
        [appDisplayName: string]: MixerProfile;
    };
}

export interface MixerProfile {
    name: string;
    usePerAppProfile?: boolean;
    volumes?: {
        [code: string]: number
    };
}

export interface MixerVolumes {
    FL: number;
    FR: number;
    FC: number;
    LFE: number;
    RL: number;
    RR: number;
    SL: number;
    SR: number;
}

export interface Channel {
    code: string;
    label: string;
}

export interface RunningApp {
    display_name?: string;
}

export type PluginPage = "audio_controls" | "plugin_config";

export interface HrirFile {
    label: string;
    path: string;
    channel_count?: string;
}

export interface SinkInputFormat {
    format: string;
    sample_format: string;
    rate: string;
    channels: string;
}

export interface SinkInput {
    name: string;
    index: number;
    sink: number;
    format: SinkInputFormat;
    volume: string;
    target_object: string;
}

export interface SinkInputConsolidated {
    name: string;
    index: number;
    formats: SinkInputFormat[];
    volume: string;
    target_object: string;
    enabled: boolean;
}
