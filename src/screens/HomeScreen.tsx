import { useMemo, useState } from "react";
import { ActivityIndicator, Pressable, ScrollView, StyleSheet, Text, View } from "react-native";
import { LinearGradient } from "expo-linear-gradient";
import { SafeAreaView } from "react-native-safe-area-context";
import { BlurView } from "expo-blur";
import Animated, { FadeIn, FadeOut, SlideInDown, SlideOutDown } from "react-native-reanimated";

import { AlbumCardStack } from "@/components/AlbumCardStack";
import { GlassPlayer } from "@/components/GlassPlayer";
import { ProgressBar } from "@/components/ProgressBar";
import { TrackList } from "@/components/TrackList";
import { WaveformVisualizer } from "@/components/WaveformVisualizer";
import { colors } from "@/constants/theme";
import { useAudioPlayer } from "@/hooks/useAudioPlayer";

export function HomeScreen() {
  const [isNowPlayingOpen, setIsNowPlayingOpen] = useState(false);
  const player = useAudioPlayer();

  const headline = useMemo(() => {
    if (player.isBooting) return "starting audio engine";
    if (!player.tracks.length) return "local MP3 iPod";
    if (player.isPlaying) return "playing from Files";
    return "ready to play";
  }, [player.isBooting, player.isPlaying, player.tracks.length]);

  return (
    <LinearGradient colors={["#050509", "#090915", "#121018"]} style={styles.root}>
      <SafeAreaView style={styles.safe}>
        <ScrollView contentContainerStyle={styles.content} showsVerticalScrollIndicator={false}>
          <View style={styles.header}>
            <View>
              <Text style={styles.kicker}>mo1</Text>
              <Text style={styles.headline}>{headline}</Text>
            </View>
            {player.isImporting || player.isBooting ? <ActivityIndicator color={colors.cyan} /> : null}
          </View>

          <View style={styles.hero}>
            <AlbumCardStack tracks={player.tracks} />
            <View style={styles.orbOne} />
            <View style={styles.orbTwo} />
            <GlassPlayer
              currentTrack={player.currentTrack}
              isPlaying={player.isPlaying}
              onExpand={() => setIsNowPlayingOpen(true)}
              onImport={player.importTracks}
              onNext={player.skipNext}
              onPlayPause={player.togglePlayback}
              onPrevious={player.skipPrevious}
            />
          </View>

          <View style={styles.sectionHeader}>
            <Text style={styles.sectionTitle}>Library</Text>
            <Text style={styles.sectionCount}>{player.tracks.length} tracks</Text>
          </View>
          <TrackList currentId={player.currentTrack?.id} onDeleteTrack={player.deleteTrack} onPlayTrack={player.playTrack} tracks={player.tracks} />
        </ScrollView>

        {isNowPlayingOpen ? (
          <Animated.View entering={FadeIn.duration(160)} exiting={FadeOut.duration(130)} style={styles.overlay}>
            <Pressable style={StyleSheet.absoluteFill} onPress={() => setIsNowPlayingOpen(false)} />
            <Animated.View entering={SlideInDown.springify().damping(17).stiffness(150)} exiting={SlideOutDown.duration(180)} style={styles.sheet}>
              <BlurView intensity={68} tint="dark" style={styles.sheetBlur}>
                <View style={styles.sheetTop}>
                  <View>
                    <Text style={styles.nowKicker}>Now Playing</Text>
                    <Text numberOfLines={1} style={styles.nowTitle}>
                      {player.currentTrack?.title ?? "Import MP3s"}
                    </Text>
                    <Text numberOfLines={1} style={styles.nowArtist}>
                      {player.currentTrack?.artist ?? "Local files only"}
                    </Text>
                  </View>
                  <Pressable onPress={() => setIsNowPlayingOpen(false)} style={styles.closeButton}>
                    <Text style={styles.closeText}>X</Text>
                  </Pressable>
                </View>

                <WaveformVisualizer isPlaying={player.isPlaying} />
                <ProgressBar duration={player.progress.duration} onSeek={player.seekTo} position={player.progress.position} />

                <View style={styles.sheetControls}>
                  <Pressable onPress={player.skipPrevious} style={styles.sheetSmallButton}>
                    <Text style={styles.sheetSmallText}>prev</Text>
                  </Pressable>
                  <Pressable onPress={player.togglePlayback} style={styles.sheetPlayButton}>
                    <Text style={styles.sheetPlayText}>{player.isPlaying ? "Pause" : "Play"}</Text>
                  </Pressable>
                  <Pressable onPress={player.skipNext} style={styles.sheetSmallButton}>
                    <Text style={styles.sheetSmallText}>next</Text>
                  </Pressable>
                </View>
              </BlurView>
            </Animated.View>
          </Animated.View>
        ) : null}
      </SafeAreaView>
    </LinearGradient>
  );
}

const styles = StyleSheet.create({
  closeButton: {
    alignItems: "center",
    backgroundColor: "rgba(255,255,255,0.1)",
    borderRadius: 999,
    height: 44,
    justifyContent: "center",
    width: 44
  },
  closeText: {
    color: colors.white,
    fontSize: 18,
    fontWeight: "900"
  },
  content: {
    paddingBottom: 34,
    paddingHorizontal: 18
  },
  header: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
    paddingTop: 8
  },
  headline: {
    color: colors.white,
    fontSize: 25,
    fontWeight: "900",
    marginTop: 2
  },
  hero: {
    alignItems: "center",
    height: 650,
    justifyContent: "flex-end",
    marginTop: 4
  },
  kicker: {
    color: colors.green,
    fontSize: 13,
    fontWeight: "900",
    textTransform: "uppercase"
  },
  nowArtist: {
    color: colors.muted,
    fontSize: 15,
    fontWeight: "700",
    marginTop: 5
  },
  nowKicker: {
    color: colors.green,
    fontSize: 12,
    fontWeight: "900",
    textTransform: "uppercase"
  },
  nowTitle: {
    color: colors.white,
    fontSize: 27,
    fontWeight: "900",
    marginTop: 6,
    maxWidth: 260
  },
  orbOne: {
    backgroundColor: colors.cyan,
    borderRadius: 90,
    height: 180,
    left: -62,
    opacity: 0.18,
    position: "absolute",
    top: 224,
    width: 180
  },
  orbTwo: {
    backgroundColor: colors.pink,
    borderRadius: 120,
    height: 240,
    opacity: 0.13,
    position: "absolute",
    right: -120,
    top: 86,
    width: 240
  },
  overlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: "rgba(0,0,0,0.48)",
    justifyContent: "flex-end"
  },
  root: {
    flex: 1
  },
  safe: {
    flex: 1
  },
  sectionCount: {
    color: colors.muted,
    fontSize: 13,
    fontWeight: "800"
  },
  sectionHeader: {
    alignItems: "center",
    flexDirection: "row",
    justifyContent: "space-between",
    marginBottom: 12,
    marginTop: 8
  },
  sectionTitle: {
    color: colors.white,
    fontSize: 20,
    fontWeight: "900"
  },
  sheet: {
    padding: 12
  },
  sheetBlur: {
    borderColor: "rgba(255,255,255,0.18)",
    borderRadius: 34,
    borderWidth: 1,
    gap: 22,
    overflow: "hidden",
    padding: 20
  },
  sheetControls: {
    alignItems: "center",
    flexDirection: "row",
    gap: 12,
    justifyContent: "space-between"
  },
  sheetPlayButton: {
    alignItems: "center",
    backgroundColor: colors.white,
    borderRadius: 999,
    flex: 1,
    height: 56,
    justifyContent: "center"
  },
  sheetPlayText: {
    color: colors.ink,
    fontSize: 16,
    fontWeight: "900"
  },
  sheetSmallButton: {
    alignItems: "center",
    backgroundColor: "rgba(255,255,255,0.1)",
    borderColor: colors.line,
    borderRadius: 999,
    borderWidth: 1,
    height: 56,
    justifyContent: "center",
    width: 82
  },
  sheetSmallText: {
    color: colors.white,
    fontSize: 13,
    fontWeight: "900",
    textTransform: "uppercase"
  },
  sheetTop: {
    alignItems: "flex-start",
    flexDirection: "row",
    justifyContent: "space-between"
  }
});
