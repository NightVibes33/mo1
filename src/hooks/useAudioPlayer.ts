import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import * as Haptics from "expo-haptics";
import TrackPlayer, { usePlaybackState, useProgress } from "react-native-track-player";

import type { LocalTrack } from "@/types/music";
import { deleteTrack as deleteStoredTrack, importMp3Files, loadLibrary } from "@/services/library";
import { loadQueue, normalizePlaybackState, setupTrackPlayer, State } from "@/services/trackPlayer";

const queueKeyFor = (tracks: LocalTrack[]) => tracks.map((track) => track.id).join("|");

export function useAudioPlayer() {
  const [tracks, setTracks] = useState<LocalTrack[]>([]);
  const [currentId, setCurrentId] = useState<string | undefined>();
  const [isBooting, setIsBooting] = useState(true);
  const [isImporting, setIsImporting] = useState(false);
  const queueKeyRef = useRef("");
  const playback = usePlaybackState();
  const progress = useProgress(250);
  const playbackState = normalizePlaybackState(playback);

  useEffect(() => {
    let mounted = true;

    async function boot() {
      await setupTrackPlayer();
      const stored = await loadLibrary();
      if (!mounted) return;
      setTracks(stored);
      setCurrentId(stored[0]?.id);
      setIsBooting(false);
    }

    boot().catch(() => setIsBooting(false));

    return () => {
      mounted = false;
    };
  }, []);

  const currentTrack = useMemo(
    () => tracks.find((track) => track.id === currentId) ?? tracks[0],
    [currentId, tracks]
  );

  const currentIndex = useMemo(
    () => tracks.findIndex((track) => track.id === currentTrack?.id),
    [currentTrack?.id, tracks]
  );

  const ensureQueue = useCallback(
    async (startId?: string) => {
      if (!tracks.length) return;
      const nextKey = queueKeyFor(tracks);
      if (queueKeyRef.current !== nextKey) {
        await loadQueue(tracks, startId ?? currentTrack?.id);
        queueKeyRef.current = nextKey;
        return;
      }

      if (startId) {
        const index = tracks.findIndex((track) => track.id === startId);
        if (index >= 0) {
          await TrackPlayer.skip(index);
        }
      }
    },
    [currentTrack?.id, tracks]
  );

  const playTrack = useCallback(
    async (track: LocalTrack) => {
      await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
      setCurrentId(track.id);
      await ensureQueue(track.id);
      await TrackPlayer.play();
    },
    [ensureQueue]
  );

  const togglePlayback = useCallback(async () => {
    await Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);

    if (!tracks.length) return;

    if (!currentTrack) {
      await playTrack(tracks[0]);
      return;
    }

    await ensureQueue(currentTrack.id);

    if (playbackState === State.Playing) {
      await TrackPlayer.pause();
    } else {
      await TrackPlayer.play();
    }
  }, [currentTrack, ensureQueue, playTrack, playbackState, tracks]);

  const skipToIndex = useCallback(
    async (index: number) => {
      if (!tracks.length) return;
      const wrapped = (index + tracks.length) % tracks.length;
      const track = tracks[wrapped];
      setCurrentId(track.id);
      await Haptics.selectionAsync();
      await ensureQueue(track.id);
      await TrackPlayer.play();
    },
    [ensureQueue, tracks]
  );

  const skipNext = useCallback(() => skipToIndex(currentIndex + 1), [currentIndex, skipToIndex]);
  const skipPrevious = useCallback(() => skipToIndex(currentIndex - 1), [currentIndex, skipToIndex]);

  const seekTo = useCallback(async (position: number) => {
    await TrackPlayer.seekTo(position);
  }, []);

  const importTracks = useCallback(async () => {
    setIsImporting(true);
    try {
      const next = await importMp3Files(tracks);
      setTracks(next);
      setCurrentId((id) => id ?? next[0]?.id);
      queueKeyRef.current = "";
      await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
    } finally {
      setIsImporting(false);
    }
  }, [tracks]);

  const deleteTrack = useCallback(
    async (track: LocalTrack) => {
      const next = await deleteStoredTrack(track, tracks);
      setTracks(next);
      setCurrentId((id) => (id === track.id ? next[0]?.id : id));
      queueKeyRef.current = "";
      await Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
      if (currentTrack?.id === track.id) {
        await TrackPlayer.reset();
      }
    },
    [currentTrack?.id, tracks]
  );

  return {
    tracks,
    currentTrack,
    currentIndex,
    isBooting,
    isImporting,
    isPlaying: playbackState === State.Playing,
    isBuffering: playbackState === State.Buffering || playbackState === State.Loading,
    progress,
    importTracks,
    playTrack,
    togglePlayback,
    skipNext,
    skipPrevious,
    seekTo,
    deleteTrack
  };
}
