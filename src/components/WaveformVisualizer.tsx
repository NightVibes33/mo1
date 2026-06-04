import { memo, useEffect } from "react";
import { StyleSheet, View } from "react-native";
import { LinearGradient } from "expo-linear-gradient";
import Animated, {
  Easing,
  interpolate,
  useAnimatedStyle,
  useSharedValue,
  withRepeat,
  withTiming
} from "react-native-reanimated";

import { colors } from "@/constants/theme";

const BAR_COUNT = 34;

function Bar({ index, isPlaying }: { index: number; isPlaying: boolean }) {
  const phase = useSharedValue(0);

  useEffect(() => {
    phase.value = withRepeat(
      withTiming(1, {
        duration: isPlaying ? 650 + index * 28 : 1600 + index * 18,
        easing: Easing.inOut(Easing.sin)
      }),
      -1,
      true
    );
  }, [index, isPlaying, phase]);

  const style = useAnimatedStyle(() => {
    const base = 18 + ((index * 13) % 34);
    const height = interpolate(phase.value, [0, 1], [base, isPlaying ? base + 42 : base + 8]);
    return {
      height,
      opacity: isPlaying ? 0.82 + phase.value * 0.18 : 0.35 + phase.value * 0.2
    };
  });

  return (
    <Animated.View style={[styles.bar, style]}>
      <LinearGradient
        colors={[index % 3 === 0 ? colors.green : colors.cyan, index % 4 === 0 ? colors.pink : colors.violet]}
        style={StyleSheet.absoluteFill}
      />
    </Animated.View>
  );
}

export const WaveformVisualizer = memo(function WaveformVisualizer({ isPlaying }: { isPlaying: boolean }) {
  return (
    <View style={styles.wrap}>
      {Array.from({ length: BAR_COUNT }, (_, index) => (
        <Bar key={index} index={index} isPlaying={isPlaying} />
      ))}
    </View>
  );
});

const styles = StyleSheet.create({
  bar: {
    borderRadius: 999,
    overflow: "hidden",
    width: 6
  },
  wrap: {
    alignItems: "center",
    backgroundColor: "rgba(255,255,255,0.05)",
    borderColor: "rgba(255,255,255,0.14)",
    borderRadius: 18,
    borderWidth: 1,
    flexDirection: "row",
    gap: 3,
    height: 108,
    justifyContent: "center",
    overflow: "hidden",
    paddingHorizontal: 12
  }
});
