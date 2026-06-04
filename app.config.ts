import type { ExpoConfig } from "expo/config";

const config: ExpoConfig = {
  name: "mo1",
  slug: "mo1",
  version: "0.1.0",
  orientation: "portrait",
  scheme: "mo1",
  userInterfaceStyle: "dark",
  icon: "./assets/icon.png",
  splash: {
    image: "./assets/splash.png",
    resizeMode: "contain",
    backgroundColor: "#050509"
  },
  assetBundlePatterns: ["**/*"],
  ios: {
    supportsTablet: false,
    bundleIdentifier: "app.mo1.player",
    infoPlist: {
      UIBackgroundModes: ["audio"],
      ITSAppUsesNonExemptEncryption: false,
      LSSupportsOpeningDocumentsInPlace: true,
      UISupportsDocumentBrowser: true,
      NSDocumentsFolderUsageDescription:
        "mo1 imports MP3 files you choose from the Files app into its local music library.",
      NSAppleMusicUsageDescription:
        "mo1 only plays files you import locally and does not access Apple Music."
    }
  },
  plugins: [
    "expo-document-picker",
    [
      "expo-build-properties",
      {
        ios: {
                deploymentTarget: "15.1",
          useFrameworks: "static"
        }
      }
    ]
  ]
};

export default config;
