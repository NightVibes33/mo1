const EXTENSION_RE = /\.(mp3|mpeg|m4a|aac|wav|flac)$/i;

const pretty = (value: string) =>
  value
    .replace(EXTENSION_RE, "")
    .replace(/[_-]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();

const titleCase = (value: string) =>
  value.replace(/\b\w/g, (char) => char.toUpperCase());

export function metadataFromFilename(fileName: string) {
  const cleaned = pretty(fileName);
  const split = cleaned.split(/\s+-\s+/);

  if (split.length >= 2) {
    return {
      artist: titleCase(split[0] || "Unknown Artist"),
      title: titleCase(split.slice(1).join(" - ") || cleaned)
    };
  }

  return {
    artist: "Local MP3",
    title: titleCase(cleaned || "Untitled Track")
  };
}
