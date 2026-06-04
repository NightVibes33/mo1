import { memo, useMemo, useRef, useState } from "react";
import { PanResponder, StyleSheet, Text, View } from "react-native";
import { LinearGradient } from "expo-linear-gradient";

import { colors } from "@/constants/theme";

const formatTime = (seconds: number) => {
  if (!Number.isFinite(seconds) || seconds < 0) return "0:00";
  const min = Math.floor(seconds / 60);
  const sec = Math.floor(seconds % 60).toString().padStart(2, "0");
  return `${min}:${sec}`;
};

export const ProgressBar = memo(function ProgressBar({
  position,
  duration,
  onSeek
}: {
  position: number;
  duration: number;
  onSeek: (position: number) => void;
}) {
  const [width, setWidth] = useState(1);
  const durationSafe = duration || 1;
  const pct = Math.min(1, Math.max(0, position / durationSafe));
  const onSeekRef = useRef(onSeek);
  onSeekRef.current = onSeek;

  const panResponder = useMemo(
    () =>
      PanResponder.create({
        onStartShouldSetPanResponder: () => true,
        onMoveShouldSetPanResponder: () => true,
        onPanResponderGrant: (event) => {
          const x = event.nativeEvent.locationX;
          onSeekRef.current(Math.max(0, Math.min(1, x / width)) * durationSafe);
        },
        onPanResponderMove: (event) => {
          const x = event.nativeEvent.locationX;
          onSeekRef.current(Math.max(0, Math.min(1, x / width)) * durationSafe);
        }
      }),
    [durationSafe, width]
  );

  return (
    <View>
      <View
        {...panResponder.panHandlers}
        onLayout={(event) => setWidth(event.nativeEvent.layout.width)}
        style={styles.track}
      >
        <LinearGradient colors={[colors.cyan, colors.green, colors.pink]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 0 }} style={[styles.fill, { width: `${pct * 100}%` }]} />
        <View style={[styles.thumb, { left: `${pct * 100}%` }]} />
      </View>
      <View style={styles.times}>
        <Text style={styles.time}>{formatTime(position)}</Text>
        <Text style={styles.time}>{formatTime(duration)}</Text>
      </View>
    </View>
  );
});

const styles = StyleSheet.create({
  fill: {
    borderRadius: 999,
    bottom: 0,
    left: 0,
    position: "absolute",
    top: 0
  },
  thumb: {
    backgroundColor: colors.white,
    borderRadius: 7,
    height: 14,
    marginLeft: -7,
    marginTop: -4,
    position: "absolute",
    shadowColor: colors.cyan,
    shadowOpacity: 0.95,
    shadowRadius: 9,
    top: "50%",
    width: 14
  },
  time: {
    color: colors.muted,
    fontSize: 12,
    fontWeight: "700"
  },
  times: {
    flexDirection: "row",
    justifyContent: "space-between",
    marginTop: 9
  },
  track: {
    backgroundColor: "rgba(255,255,255,0.13)",
    borderRadius: 999,
    height: 7,
    overflow: "visible"
  }
});
