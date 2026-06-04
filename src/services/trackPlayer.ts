import TrackPlayer, {
  AppKilledPlaybackBehavior,
  Capability,
  Event,
  RepeatMode,
  State
} from "react-native-track-player";

import type { LocalTrack } from "@/types/music";

let setupPromise: Promise<void> | null = null;

export async function setupTrackPlayer() {
  if (setupPromise) return setupPromise;

  setupPromise = (async () => {
    try {
      await TrackPlayer.setupPlayer({
        autoHandleInterruptions: true
      });
    } catch (error) {
      const message = String(error);
      if (!message.includes("already been initialized")) {
        throw error;
      }
    }

    await TrackPlayer.updateOptions({
      android: {
        appKilledPlaybackBehavior: AppKilledPlaybackBehavior.StopPlaybackAndRemoveNotification
      },
      capabilities: [
        Capability.Play,
        Capability.Pause,
        Capability.Stop,
        Capability.SeekTo,
        Capability.SkipToNext,
        Capability.SkipToPrevious
      ],
      compactCapabilities: [Capability.Play, Capability.Pause, Capability.SkipToNext],
      progressUpdateEventInterval: 1
    });

    await TrackPlayer.setRepeatMode(RepeatMode.Queue);
  })();

  return setupPromise;
}

export function toTrackPlayerTrack(track: LocalTrack) {
  return {
    id: track.id,
    url: track.uri,
    title: track.title,
    artist: track.artist,
    album: "mo1 local library",
    artwork: undefined
  };
}

export async function loadQueue(tracks: LocalTrack[], startId?: string) {
  await setupTrackPlayer();
  await TrackPlayer.reset();
  await TrackPlayer.add(tracks.map(toTrackPlayerTrack));

  if (startId) {
    const index = tracks.findIndex((track) => track.id === startId);
    if (index >= 0) {
      await TrackPlayer.skip(index);
    }
  }
}

export function normalizePlaybackState(value: unknown) {
  if (value && typeof value === "object" && "state" in value) {
    return (value as { state?: State }).state;
  }

  return value as State | undefined;
}

export { Event, State };
