import { registerRootComponent } from "expo";
import TrackPlayer from "react-native-track-player";

import App from "./App";

TrackPlayer.registerPlaybackService(() => require("./src/services/playbackService").default);

registerRootComponent(App);
