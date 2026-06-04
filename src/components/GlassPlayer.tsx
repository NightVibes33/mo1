import { memo, useEffect } from "react";
import { Pressable, StyleSheet, Text, View } from "react-native";
import { BlurView } from "expo-blur";
import { LinearGradient } from "expo-linear-gradient";
import Animated, {
  Easing,
  useAnimatedStyle,
  useSharedValue,
  withRepeat,
  withSpring,
  withTiming
} from "react-native-reanimated";

import { colors } from "@/constants/theme";
import type { LocalTrack } from "@/types/music";

function IconButton({ children, onPress, label }: { children: React.ReactNode; onPress?: () => void; label: string }) {
  return (
    <Pressable accessibilityLabel={label} onPress={onPress} style={({ pressed }) => [styles.iconButton, pressed && styles.pressed]}>
      {children}
    </Pressable>
  );
}

export const GlassPlayer = memo(function GlassPlayer({
  currentTrack,
  isPlaying,
  onImport,
  onPlayPause,
  onPrevious,
  onNext,
  onExpand
}: {
  currentTrack?: LocalTrack;
  isPlaying: boolean;
  onImport: () => void;
  onPlayPause: () => void;
  onPrevious: () => void;
  onNext: () => void;
  onExpand: () => void;
}) {
  const pulse = useSharedValue(0);
  const tilt = useSharedValue(0);

  useEffect(() => {
    pulse.value = withRepeat(
      withTiming(1, { duration: isPlaying ? 950 : 1800, easing: Easing.inOut(Easing.sin) }),
      -1,
      true
    );
    tilt.value = withRepeat(withTiming(1, { duration: 5200, easing: Easing.inOut(Easing.sin) }), -1, true);
  }, [isPlaying, pulse, tilt]);

  const shellStyle = useAnimatedStyle(() => ({
    transform: [
      { perspective: 900 },
      { rotateX: `${-5 + tilt.value * 2}deg` },
      { rotateY: `${4 - tilt.value * 8}deg` },
      { scale: withSpring(isPlaying ? 1.015 : 1) }
    ]
  }));

  const ringStyle = useAnimatedStyle(() => ({
    opacity: 0.18 + pulse.value * 0.32,
    transform: [{ scale: 0.92 + pulse.value * 0.18 }]
  }));

  return (
    <Animated.View style={[styles.shell, shellStyle]}>
      <LinearGradient colors={["rgba(255,255,255,0.32)", "rgba(255,255,255,0.08)", "rgba(255,255,255,0.18)"]} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={styles.deviceBorder}>
        <BlurView intensity={46} tint="dark" style={styles.device}>
          <View style={styles.topBar}>
            <Text style={styles.logo}>mo1</Text>
            <Pressable onPress={onImport} style={({ pressed }) => [styles.importButton, pressed && styles.pressed]}>
              <Text style={styles.importText}>+ MP3</Text>
            </Pressable>
          </View>

          <Pressable onPress={onExpand} style={styles.display}>
            <LinearGradient colors={["rgba(86,255,226,0.22)", "rgba(255,78,234,0.16)", "rgba(255,255,255,0.05)"]} style={styles.displayGlow}>
              <Text numberOfLines={1} style={styles.trackTitle}>
                {currentTrack?.title ?? "No tracks yet"}
              </Text>
              <Text numberOfLines={1} style={styles.trackArtist}>
                {currentTrack?.artist ?? "Import downloaded MP3s"}
              </Text>
              <View style={styles.expandHint}>
                <Text style={styles.expandText}>now playing</Text>
                <Text style={styles.expandArrow}>OPEN</Text>
              </View>
            </LinearGradient>
          </Pressable>

          <View style={styles.wheelWrap}>
            <Animated.View pointerEvents="none" style={[styles.pulseRing, ringStyle]} />
            <LinearGradient colors={["rgba(255,255,255,0.32)", "rgba(255,255,255,0.08)"]} style={styles.wheelOuter}>
              <BlurView intensity={32} tint="dark" style={styles.wheel}>
                <View style={styles.wheelTop}>
                  <IconButton label="Previous track" onPress={onPrevious}>
                    <Text style={styles.controlGlyph}>PREV</Text>
                  </IconButton>
                  <IconButton label="Next track" onPress={onNext}>
                    <Text style={styles.controlGlyph}>NEXT</Text>
                  </IconButton>
                </View>
                <Pressable accessibilityLabel={isPlaying ? "Pause" : "Play"} onPress={onPlayPause} style={({ pressed }) => [styles.playButton, pressed && styles.playPressed]}>
                  <LinearGradient colors={[colors.white, colors.cyan]} style={styles.playGradient}>
                    <Text style={styles.playGlyph}>{isPlaying ? "II" : "PLAY"}</Text>
                  </LinearGradient>
                </Pressable>
                <View style={styles.wheelBottom}>
                  <Text style={styles.navGlyph}>BACK</Text>
                  <Text style={styles.menuText}>library</Text>
                  <Text style={styles.navGlyph}>OPEN</Text>
                </View>
              </BlurView>
            </LinearGradient>
          </View>
        </BlurView>
      </LinearGradient>
    </Animated.View>
  );
});

const styles = StyleSheet.create({
  controlGlyph: {
    color: colors.white,
    fontSize: 11,
    fontWeight: "900"
  },
  device: {
    borderColor: "rgba(255,255,255,0.22)",
    borderRadius: 42,
    borderWidth: 1,
    flex: 1,
    overflow: "hidden",
    padding: 20
  },
  deviceBorder: {
    borderRadius: 45,
    flex: 1,
    padding: 1
  },
  display: {
    borderRadius: 28,
    height: 122,
    marginTop: 16,
    overflow: "hidden"
  },
  displayGlow: {
    borderColor: "rgba(255,255,255,0.18)",
    borderRadius: 28,
    borderWidth: 1,
    flex: 1,
    justifyContent: "center",
    padding: 18
  },
  expandArrow: {
    color: colors.muted,
    fontSize: 10,
    fontWeight: "900"
  },
  expandHint: {
    alignItems: "center",
    flexDirection: "row",
    gap: 2,
    marginTop: 14
  },
  expandText: {
    color: colors.muted,
    fontSize: 11,
    fontWeight: "800",
    letterSpacing: 0,
    textTransform: "uppercase"
  },
  iconButton: {
    alignItems: "center",
    backgroundColor: "rgba(255,255,255,0.08)",
    borderColor: "rgba(255,255,255,0.12)",
    borderRadius: 999,
    borderWidth: 1,
    height: 52,
    justifyContent: "center",
    width: 52
  },
  importButton: {
    alignItems: "center",
    backgroundColor: colors.green,
    borderRadius: 999,
    flexDirection: "row",
    gap: 4,
    paddingHorizontal: 11,
    paddingVertical: 7
  },
  importText: {
    color: colors.ink,
    fontSize: 12,
    fontWeight: "900"
  },
  logo: {
    color: colors.white,
    fontSize: 28,
    fontWeight: "900"
  },
  menuText: {
    color: "rgba(255,255,255,0.58)",
    fontSize: 12,
    fontWeight: "900",
    textTransform: "uppercase"
  },
  navGlyph: {
    color: "rgba(255,255,255,0.58)",
    fontSize: 10,
    fontWeight: "900"
  },
  playButton: {
    alignSelf: "center",
    borderRadius: 999,
    height: 118,
    overflow: "hidden",
    shadowColor: colors.cyan,
    shadowOpacity: 0.72,
    shadowRadius: 24,
    width: 118
  },
  playGlyph: {
    color: colors.ink,
    fontSize: 18,
    fontWeight: "900"
  },
  playGradient: {
    alignItems: "center",
    flex: 1,
    justifyContent: "center"
  },
  playPressed: {
    transform: [{ scale: 0.96 }]
  },
  pressed: {
    opacity: 0.72,
    transform: [{ scale: 0.97 }]
  },
  pulseRing: {
    borderColor: colors.cyan,
    borderRadius: 130,
    borderWidth: 2,
    height: 260,
    left: -8,
    position: "absolute",
    top: -8,
    width: 260
  },
  shell: {
    height: 520,
    shadowColor: colors.pink,
    shadowOffset: { width: 0, height: 26 },
    shadowOpacity: 0.34,
    shadowRadius: 42,
    width: 338
  },
  topBar: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between"
  },
  trackArtist: {
    color: colors.muted,
    fontSize: 14,
    fontWeight: "700",
    marginTop: 7
  },
  trackTitle: {
    color: colors.white,
    fontSize: 23,
    fontWeight: "900"
  },
  wheel: {
    borderRadius: 128,
    flex: 1,
    overflow: "hidden",
    padding: 18
  },
  wheelBottom: {
    alignItems: "center",
    bottom: 18,
    flexDirection: "row",
    justifyContent: "space-between",
    left: 28,
    position: "absolute",
    right: 28
  },
  wheelOuter: {
    borderRadius: 130,
    height: 244,
    overflow: "hidden",
    padding: 1,
    width: 244
  },
  wheelTop: {
    flexDirection: "row",
    justifyContent: "space-between"
  },
  wheelWrap: {
    alignItems: "center",
    justifyContent: "center",
    marginTop: 24
  }
});
