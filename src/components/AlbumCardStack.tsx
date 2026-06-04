import { memo } from "react";
import { StyleSheet, Text, View } from "react-native";
import { LinearGradient } from "expo-linear-gradient";
import Animated, {
  Easing,
  interpolate,
  useAnimatedStyle,
  useSharedValue,
  withRepeat,
  withTiming
} from "react-native-reanimated";

import { albumGradients, colors } from "@/constants/theme";
import type { LocalTrack } from "@/types/music";

const AnimatedLinearGradient = Animated.createAnimatedComponent(LinearGradient);

function Card({ track, index }: { track?: LocalTrack; index: number }) {
  const float = useSharedValue(0);

  if (float.value === 0) {
    float.value = withRepeat(
      withTiming(1, {
        duration: 3200 + index * 450,
        easing: Easing.inOut(Easing.sin)
      }),
      -1,
      true
    );
  }

  const animatedStyle = useAnimatedStyle(() => {
    const y = interpolate(float.value, [0, 1], [0, -8 - index * 2]);
    const rotate = interpolate(float.value, [0, 1], [-3 + index * 4, 3 + index * 4]);

    return {
      transform: [
        { translateY: y + index * 18 },
        { translateX: (index - 1) * 48 },
        { rotateZ: `${rotate}deg` },
        { scale: 1 - index * 0.07 }
      ],
      opacity: 1 - index * 0.16
    };
  });

  const gradient = albumGradients[index % albumGradients.length] as [string, string];

  return (
    <AnimatedLinearGradient colors={gradient} start={{ x: 0, y: 0 }} end={{ x: 1, y: 1 }} style={[styles.card, animatedStyle]}>
      <View style={styles.cardGlass}>
        <Text numberOfLines={1} style={styles.cardTitle}>
          {track?.title ?? "import MP3s"}
        </Text>
        <Text numberOfLines={1} style={styles.cardArtist}>
          {track?.artist ?? "local files"}
        </Text>
      </View>
    </AnimatedLinearGradient>
  );
}

export const AlbumCardStack = memo(function AlbumCardStack({ tracks }: { tracks: LocalTrack[] }) {
  const cards = [tracks[0], tracks[1], tracks[2]];

  return (
    <View pointerEvents="none" style={styles.wrap}>
      {[2, 1, 0].map((index) => (
        <Card key={index} track={cards[index]} index={index} />
      ))}
    </View>
  );
});

const styles = StyleSheet.create({
  wrap: {
    alignItems: "center",
    height: 210,
    justifyContent: "center",
    left: 0,
    position: "absolute",
    right: 0,
    top: 12
  },
  card: {
    borderColor: "rgba(255,255,255,0.38)",
    borderRadius: 28,
    borderWidth: 1,
    height: 170,
    overflow: "hidden",
    padding: 16,
    position: "absolute",
    shadowColor: colors.cyan,
    shadowOffset: { width: 0, height: 18 },
    shadowOpacity: 0.32,
    shadowRadius: 28,
    width: 170
  },
  cardGlass: {
    backgroundColor: "rgba(5,5,9,0.26)",
    borderColor: "rgba(255,255,255,0.22)",
    borderRadius: 22,
    borderWidth: 1,
    flex: 1,
    justifyContent: "flex-end",
    padding: 12
  },
  cardTitle: {
    color: colors.white,
    fontSize: 17,
    fontWeight: "800"
  },
  cardArtist: {
    color: "rgba(255,255,255,0.72)",
    fontSize: 12,
    fontWeight: "700",
    marginTop: 4,
    textTransform: "uppercase"
  }
});
