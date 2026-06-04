export type LocalTrack = {
  id: string;
  title: string;
  artist: string;
  uri: string;
  fileName: string;
  importedAt: number;
  duration?: number;
  artworkColor: string;
};

export type PlayerMode = "idle" | "ready" | "playing" | "paused" | "loading";
