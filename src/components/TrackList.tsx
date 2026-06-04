import { memo } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";

import { colors } from "@/constants/theme";
import type { LocalTrack } from "@/types/music";

export const TrackList = memo(function TrackList({
  tracks,
  currentId,
  onPlayTrack,
  onDeleteTrack
}: {
  tracks: LocalTrack[];
  currentId?: string;
  onPlayTrack: (track: LocalTrack) => void;
  onDeleteTrack: (track: LocalTrack) => void;
}) {
  if (!tracks.length) {
    return (
      <View style={styles.empty}>
        <Text style={styles.emptyIcon}>MP3</Text>
        <Text style={styles.emptyTitle}>No MP3s imported</Text>
        <Text style={styles.emptyBody}>Tap the MP3 button on the player and choose downloaded files from iOS Files.</Text>
      </View>
    );
  }

  return (
    <View style={styles.wrap}>
      {tracks.map((track, index) => {
        const active = track.id === currentId;
        return (
          <Pressable key={track.id} onPress={() => onPlayTrack(track)} style={({ pressed }) => [styles.row, active && styles.activeRow, pressed && styles.pressed]}>
            <View style={[styles.art, { backgroundColor: track.artworkColor }]}>
              <Text style={styles.artText}>{String(index + 1).padStart(2, "0")}</Text>
            </View>
            <View style={styles.meta}>
              <Text numberOfLines={1} style={styles.title}>
                {track.title}
              </Text>
              <Text numberOfLines={1} style={styles.artist}>
                {track.artist}
              </Text>
            </View>
            <Pressable hitSlop={12} onPress={() => onDeleteTrack(track)} style={styles.deleteButton}>
              <Text style={styles.deleteText}>DEL</Text>
            </Pressable>
          </Pressable>
        );
      })}
    </View>
  );
});

const styles = StyleSheet.create({
  activeRow: {
    borderColor: "rgba(86,255,226,0.48)"
  },
  art: {
    alignItems: "center",
    borderRadius: 14,
    height: 48,
    justifyContent: "center",
    width: 48
  },
  artist: {
    color: colors.muted,
    fontSize: 13,
    fontWeight: "700",
    marginTop: 4
  },
  artText: {
    color: colors.ink,
    fontSize: 12,
    fontWeight: "900"
  },
  deleteButton: {
    alignItems: "center",
    height: 38,
    justifyContent: "center",
    width: 38
  },
  deleteText: {
    color: "rgba(255,255,255,0.44)",
    fontSize: 11,
    fontWeight: "900"
  },
  empty: {
    alignItems: "center",
    backgroundColor: "rgba(255,255,255,0.06)",
    borderColor: colors.line,
    borderRadius: 24,
    borderWidth: 1,
    padding: 22
  },
  emptyBody: {
    color: colors.muted,
    fontSize: 14,
    fontWeight: "600",
    lineHeight: 20,
    marginTop: 8,
    textAlign: "center"
  },
  emptyIcon: {
    color: colors.cyan,
    fontSize: 13,
    fontWeight: "900"
  },
  emptyTitle: {
    color: colors.white,
    fontSize: 17,
    fontWeight: "900",
    marginTop: 10
  },
  meta: {
    flex: 1,
    minWidth: 0
  },
  pressed: {
    opacity: 0.75,
    transform: [{ scale: 0.99 }]
  },
  row: {
    alignItems: "center",
    backgroundColor: "rgba(255,255,255,0.06)",
    borderColor: colors.line,
    borderRadius: 18,
    borderWidth: 1,
    flexDirection: "row",
    gap: 12,
    marginBottom: 10,
    padding: 10
  },
  title: {
    color: colors.white,
    fontSize: 15,
    fontWeight: "900"
  },
  wrap: {
    gap: 0
  }
});
