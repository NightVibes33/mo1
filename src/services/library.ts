import AsyncStorage from "@react-native-async-storage/async-storage";
import * as DocumentPicker from "expo-document-picker";
import * as FileSystem from "expo-file-system/legacy";

import { albumGradients } from "@/constants/theme";
import type { LocalTrack } from "@/types/music";
import { metadataFromFilename } from "./filenameMetadata";

const LIBRARY_KEY = "mo1.library.v1";
const TRACK_DIR = `${FileSystem.documentDirectory ?? ""}tracks/`;

const safeFileName = (name: string) =>
  name
    .replace(/[^a-z0-9. _-]/gi, "")
    .replace(/\s+/g, "-")
    .toLowerCase();

const uniqueId = () => `${Date.now()}-${Math.random().toString(36).slice(2, 9)}`;

async function ensureTrackDir() {
  const info = await FileSystem.getInfoAsync(TRACK_DIR);
  if (!info.exists) {
    await FileSystem.makeDirectoryAsync(TRACK_DIR, { intermediates: true });
  }
}

export async function loadLibrary(): Promise<LocalTrack[]> {
  const raw = await AsyncStorage.getItem(LIBRARY_KEY);
  if (!raw) {
    return [];
  }

  try {
    const tracks = JSON.parse(raw) as LocalTrack[];
    return Array.isArray(tracks) ? tracks : [];
  } catch {
    return [];
  }
}

export async function saveLibrary(tracks: LocalTrack[]) {
  await AsyncStorage.setItem(LIBRARY_KEY, JSON.stringify(tracks));
}

export async function deleteTrack(track: LocalTrack, current: LocalTrack[]) {
  await FileSystem.deleteAsync(track.uri, { idempotent: true });
  const next = current.filter((item) => item.id !== track.id);
  await saveLibrary(next);
  return next;
}

export async function importMp3Files(existing: LocalTrack[]) {
  const result = await DocumentPicker.getDocumentAsync({
    type: ["audio/mpeg", "audio/mp3", "audio/x-mp3", "audio/*"],
    multiple: true,
    copyToCacheDirectory: true
  });

  if (result.canceled) {
    return existing;
  }

  await ensureTrackDir();

  const imported: LocalTrack[] = [];
  for (const asset of result.assets) {
    if (!asset.uri) continue;

    const id = uniqueId();
    const fileName = asset.name || `track-${id}.mp3`;
    const targetName = `${id}-${safeFileName(fileName) || "track.mp3"}`;
    const targetUri = `${TRACK_DIR}${targetName}`;
    await FileSystem.copyAsync({ from: asset.uri, to: targetUri });

    const metadata = metadataFromFilename(fileName);
    imported.push({
      id,
      uri: targetUri,
      fileName,
      importedAt: Date.now(),
      title: metadata.title,
      artist: metadata.artist,
      artworkColor: albumGradients[(existing.length + imported.length) % albumGradients.length][0]
    });
  }

  const next = [...imported, ...existing];
  await saveLibrary(next);
  return next;
}
