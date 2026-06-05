import CarPlay
import Foundation
import UIKit

final class MO1CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  private var interfaceController: CPInterfaceController?
  private var rootTemplate: CPListTemplate?
  private var snapshot = MO1CarPlaySnapshot.empty

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    self.interfaceController = interfaceController
    let template = makeRootTemplate()
    rootTemplate = template
    interfaceController.setRootTemplate(template, animated: false)

    MO1CarPlayBridge.shared.observeSnapshots { [weak self] snapshot in
      self?.snapshot = snapshot
      self?.refreshRootTemplate()
    }
    MO1CarPlayBridge.shared.requestSnapshot()
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    if self.interfaceController === interfaceController {
      self.interfaceController = nil
      self.rootTemplate = nil
      MO1CarPlayBridge.shared.clearObserver()
    }
  }

  private func makeRootTemplate() -> CPListTemplate {
    return CPListTemplate(title: "mo1", sections: makeRootSections())
  }

  private func refreshRootTemplate() {
    rootTemplate?.updateSections(makeRootSections())
  }

  private func makeRootSections() -> [CPListSection] {
    let currentTitle = snapshot.current?.title ?? "Nothing Playing"
    let currentArtist = snapshot.current?.artist ?? "Pick a local song from your library."

    let nowPlayingItem = makeItem(
      text: "Now Playing",
      detailText: currentTitle == "Nothing Playing" ? currentArtist : "\(currentArtist) - \(currentTitle)",
      imagePath: snapshot.current?.artworkPath
    ) { [weak self] completion in
      self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
      completion()
    }

    let playPauseItem = makeItem(
      text: snapshot.isPlaying ? "Pause" : "Play",
      detailText: currentTitle
    ) { completion in
      MO1CarPlayBridge.shared.sendCommand("playPause") { _ in completion() }
    }

    let previousItem = makeItem(text: "Previous", detailText: currentTitle) { completion in
      MO1CarPlayBridge.shared.sendCommand("previous") { _ in completion() }
    }

    let nextItem = makeItem(text: "Next", detailText: currentTitle) { completion in
      MO1CarPlayBridge.shared.sendCommand("next") { _ in completion() }
    }

    let shuffleItem = makeItem(
      text: "Shuffle Songs",
      detailText: countText(snapshot.songCount, singular: "song", plural: "songs")
    ) { completion in
      MO1CarPlayBridge.shared.sendCommand("shuffleAll") { _ in completion() }
    }

    let songsItem = makeItem(
      text: "Songs",
      detailText: countText(snapshot.songCount, singular: "song", plural: "songs")
    ) { [weak self] completion in
      self?.pushSongsTemplate(
        title: "Songs",
        songs: self?.snapshot.songs ?? [],
        emptyText: "Import MP3s on iPhone first.",
        includeShuffle: true
      )
      completion()
    }

    let albumsItem = makeItem(
      text: "Albums",
      detailText: countText(snapshot.albumCount, singular: "album", plural: "albums")
    ) { [weak self] completion in
      self?.pushCollectionsTemplate(
        title: "Albums",
        collections: self?.snapshot.albums ?? [],
        emptyText: "No albums yet."
      )
      completion()
    }

    let artistsItem = makeItem(
      text: "Artists",
      detailText: countText(snapshot.artistCount, singular: "artist", plural: "artists")
    ) { [weak self] completion in
      self?.pushCollectionsTemplate(
        title: "Artists",
        collections: self?.snapshot.artists ?? [],
        emptyText: "No artists yet."
      )
      completion()
    }

    let playlistsItem = makeItem(
      text: "Playlists",
      detailText: countText(snapshot.playlistCount, singular: "playlist", plural: "playlists")
    ) { [weak self] completion in
      self?.pushCollectionsTemplate(
        title: "Playlists",
        collections: self?.snapshot.playlists ?? [],
        emptyText: "No saved playlists yet."
      )
      completion()
    }

    let recentItem = makeItem(
      text: "Recently Added",
      detailText: countText(snapshot.recentlyAdded.count, singular: "song", plural: "songs")
    ) { [weak self] completion in
      self?.pushSongsTemplate(
        title: "Recently Added",
        songs: self?.snapshot.recentlyAdded ?? [],
        emptyText: "No recent imports yet.",
        includeShuffle: false
      )
      completion()
    }

    return [
      CPListSection(items: [nowPlayingItem, playPauseItem, previousItem, nextItem, shuffleItem]),
      CPListSection(items: [songsItem, albumsItem, artistsItem, playlistsItem, recentItem])
    ]
  }

  private func pushCollectionsTemplate(
    title: String,
    collections: [MO1CarPlayCollection],
    emptyText: String
  ) {
    if collections.isEmpty {
      pushMessageTemplate(title: title, message: emptyText)
      return
    }

    let items = collections.map { collection in
      makeItem(
        text: collection.title,
        detailText: collectionDetail(collection),
        imagePath: collection.artworkPath
      ) { [weak self] completion in
        self?.pushSongsTemplate(
          title: collection.title,
          songs: collection.songs,
          emptyText: "No songs in this section.",
          includeShuffle: false
        )
        completion()
      }
    }

    interfaceController?.pushTemplate(
      CPListTemplate(title: title, sections: [CPListSection(items: items)]),
      animated: true
    )
  }

  private func pushSongsTemplate(
    title: String,
    songs: [MO1CarPlaySong],
    emptyText: String,
    includeShuffle: Bool
  ) {
    if songs.isEmpty {
      pushMessageTemplate(title: title, message: emptyText)
      return
    }

    var items: [CPListItem] = []
    if includeShuffle {
      items.append(makeItem(
        text: "Shuffle",
        detailText: countText(songs.count, singular: "song", plural: "songs")
      ) { completion in
        MO1CarPlayBridge.shared.sendCommand("shuffleAll") { _ in completion() }
      })
    }

    for song in songs.prefix(250) {
      items.append(makeSongItem(song))
    }

    if songs.count > 250 {
      items.append(makeItem(
        text: "Showing first 250 songs",
        detailText: "Use Albums, Artists, or Search on iPhone for the rest."
      ) { completion in completion() })
    }

    interfaceController?.pushTemplate(
      CPListTemplate(title: title, sections: [CPListSection(items: items)]),
      animated: true
    )
  }

  private func makeSongItem(_ song: MO1CarPlaySong) -> CPListItem {
    makeItem(
      text: song.title,
      detailText: songDetail(song),
      imagePath: song.artworkPath
    ) { [weak self] completion in
      MO1CarPlayBridge.shared.sendCommand(
        "playSong",
        arguments: ["originalIndex": song.originalIndex]
      ) { _ in
        self?.interfaceController?.pushTemplate(CPNowPlayingTemplate.shared, animated: true)
        completion()
      }
    }
  }

  private func pushMessageTemplate(title: String, message: String) {
    let item = makeItem(text: message, detailText: "") { completion in completion() }
    interfaceController?.pushTemplate(
      CPListTemplate(title: title, sections: [CPListSection(items: [item])]),
      animated: true
    )
  }

  private func makeItem(
    text: String,
    detailText: String?,
    imagePath: String? = nil,
    handler: @escaping (@escaping () -> Void) -> Void
  ) -> CPListItem {
    let item = CPListItem(
      text: text,
      detailText: detailText,
      image: listImage(path: imagePath),
      accessoryImage: nil,
      accessoryType: .none
    )
    item.handler = { _, completion in
      handler(completion)
    }
    return item
  }

  private func listImage(path: String?) -> UIImage? {
    guard let path,
          let image = UIImage(contentsOfFile: path) else {
      return nil
    }

    let maxSize = CPListItem.maximumImageSize
    guard maxSize.width > 0, maxSize.height > 0 else {
      return image
    }

    let ratio = min(maxSize.width / image.size.width, maxSize.height / image.size.height, 1)
    let targetSize = CGSize(width: image.size.width * ratio, height: image.size.height * ratio)
    let renderer = UIGraphicsImageRenderer(size: targetSize)
    return renderer.image { _ in
      image.draw(in: CGRect(origin: .zero, size: targetSize))
    }
  }

  private func songDetail(_ song: MO1CarPlaySong) -> String {
    if song.album.isEmpty || song.album == "Unknown Album" {
      return song.artist
    }
    return "\(song.artist) - \(song.album)"
  }

  private func collectionDetail(_ collection: MO1CarPlayCollection) -> String {
    let count = countText(collection.count, singular: "song", plural: "songs")
    if collection.subtitle.isEmpty {
      return count
    }
    return "\(collection.subtitle) - \(count)"
  }

  private func countText(_ count: Int, singular: String, plural: String) -> String {
    return "\(count) \(count == 1 ? singular : plural)"
  }
}
