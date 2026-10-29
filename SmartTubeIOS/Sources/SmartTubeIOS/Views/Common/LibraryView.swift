import SmartTubeIOSCore
import SwiftUI

// MARK: - LibraryView
//
// Shows subscriptions, playlists, watch history and liked videos for the
// signed-in account.  Mirrors the Android launcher activities for
// Subscriptions, Playlists, History and Channels.

public struct LibraryView: View {
    @Environment(AuthService.self) private var auth
    @Environment(BrowseViewModel.self) private var browseVM
    @Environment(\.innerTubeAPI) private var api
    @Environment(SettingsStore.self) private var store
    @State private var selectedSection: LibrarySection = .subscriptions
    @State private var selectedVideo: Video?
    @State private var selectedPlaylist: Video?
    @State private var channelDestination: ChannelDestination?
    @State private var scrollStore = ScrollOffsetStore()
    @State private var savedScrollOffset: CGFloat? = nil
    @State private var restoreOffset: CGFloat? = nil
    @State private var queueVideosCount: Int = 0
    #if os(iOS)
    @Environment(PlayerRouter.self) private var playerRouter
    #endif
    #if os(tvOS)
    @FocusState private var focusedSection: LibrarySection?
    @FocusState private var queueRowFocused: Bool
    #endif

    enum LibrarySection: String, CaseIterable, Identifiable {
        case subscriptions = "Subs"
        case recommended = "Recommended"
        case channels = "Channels"
        case history = "History"
        case playlists = "Playlists"
        case rss = "RSS Feeds"
        case downloads = "Downloads"

        static var allCases: [LibrarySection] {
            #if os(tvOS)
            // History is its own tab. Downloads stay off tvOS.
            [.subscriptions, .recommended, .channels, .playlists, .rss]
            #elseif ENABLE_DOWNLOADS
            [.subscriptions, .history, .playlists, .rss, .downloads]
            #else
            [.subscriptions, .history, .playlists, .rss]
            #endif
        }

        var id: String { rawValue }
        var browseSectionType: BrowseSection.SectionType {
            switch self {
            case .subscriptions: return .subscriptions
            case .recommended: return .recommended
            case .channels: return .channels
            case .history: return .history
            case .playlists: return .playlists
            case .rss: return .history  // not used — RSS renders its own view
            case .downloads: return .history  // not used — DownloadsView renders its own content
            }
        }
    }

    public init() {}

    public var body: some View {
        Group {
            libraryContent
        }
        #if os(iOS) || os(tvOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        #if !os(iOS)
        .navigationDestination(item: $selectedVideo) { video in
            PlayerView(video: video, api: api)
        }
        #endif
        .navigationDestination(item: $selectedPlaylist) { stub in
            PlaylistView(playlistId: stub.id, playlistTitle: stub.title, api: api)
        }
        .navigationDestination(item: $channelDestination) { dest in
            ChannelView(channelId: dest.channelId)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openChannel)) { note in
            guard let channelId = note.userInfo?["channelId"] as? String, !channelId.isEmpty else { return }
            channelDestination = ChannelDestination(channelId: channelId)
        }
    }

    private var libraryContent: some View {
        VStack(spacing: 0) {
            #if os(tvOS)
            HStack(spacing: 8) {
                ForEach(LibrarySection.allCases) { sec in
                    let isSelected = selectedSection == sec
                    let isFocused = focusedSection == sec
                    Button {
                        guard selectedSection != sec else { return }
                        selectedSection = sec
                    } label: {
                        Text(sec.rawValue)
                            .font(.headline)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                isFocused
                                    ? TVFocusStyle.color
                                    : (isSelected ? Color.primary : Color.secondary.opacity(0.15)),
                                in: Capsule()
                            )
                            .foregroundStyle((isFocused || isSelected) ? Color.black : Color.primary)
                    }
                    .buttonStyle(TVImmediateSelectButtonStyle())
                    .focusEffectDisabled()
                    .scaleEffect(isFocused ? 1.04 : 1.0)
                    .animation(.easeInOut(duration: 0.15), value: focusedSection)
                    .animation(.easeInOut(duration: 0.15), value: selectedSection)
                    .accessibilityAddTraits(isSelected ? [.isSelected] : [])
                    .accessibilityIdentifier("library.chip.\(sec.rawValue.lowercased())")
                    .focused($focusedSection, equals: sec)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
            .focusSection()
            .defaultFocus($focusedSection, selectedSection)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("library.chipBar")
            #else
            Picker("Library Section", selection: $selectedSection) {
                ForEach(LibrarySection.allCases) { sec in
                    Text(sec.rawValue).tag(sec)
                        .accessibilityIdentifier("library.picker.\(sec.rawValue.lowercased())")
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("library.sectionPicker")
            .padding()
            #endif

            Group {
                if selectedSection == .rss {
                    RSSFeedsView()
                } else if selectedSection == .downloads {
                    downloadsContent
                } else if selectedSection == .channels {
                    ChannelListView(channels: browseVM.subscribedChannels) { channel in
                        channelDestination = ChannelDestination(channelId: channel.id)
                    }
                } else if !auth.isSignedIn && selectedSection != .subscriptions {
                    segmentSignInPrompt
                } else if browseVM.isLoading && browseVM.videoGroups.flatMap({ $0.videos }).isEmpty {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if browseVM.videoGroups.flatMap({ $0.videos }).isEmpty && !browseVM.isLoading {
                    emptyLibraryView
                } else {
                    let applyHideShorts = store.settings.hideShorts && selectedSection != .history
                    let videos = browseVM.videoGroups.flatMap { $0.videos }
                        .filter { !applyHideShorts || !$0.isShort }
                    ScrollView {
                        // KVO reader — always present; writes to ScrollOffsetStore
                        // without triggering SwiftUI re-renders on every scroll tick.
                        #if os(iOS) || os(tvOS)
                        ScrollOffsetReader(store: scrollStore)
                            .frame(width: 0, height: 0)
                        #endif

                        if browseVM.isLoading && videos.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                        if selectedSection == .playlists, queueVideosCount > 0 {
                            currentQueueRow
                        }
                        VideoGridSection(
                            videos: videos,
                            onSelect: { video in
                                if video.playlistId == video.id {
                                    selectedPlaylist = video
                                } else {
                                    #if os(iOS)
                                    playerRouter.open(video: video, api: api)
                                    #else
                                    selectedVideo = video
                                    #endif
                                }
                            },
                            loadMore: {
                                if let last = videos.last {
                                    browseVM.loadMoreIfNeeded(lastVideo: last)
                                }
                            }
                        )
                        // Offset restorer — always present; no-op when restoreOffset is nil.
                        #if os(iOS) || os(tvOS)
                        ScrollOffsetRestorer(targetOffset: restoreOffset) {
                            restoreOffset = nil
                        }
                        .frame(width: 0, height: 0)
                        #endif

                        if browseVM.isLoading && !videos.isEmpty {
                            ProgressView().frame(maxWidth: .infinity).padding()
                        }
                    }
                    .refreshable {
                        browseVM.loadContent(
                            for: BrowseSection(
                                id: selectedSection.id,
                                title: selectedSection.rawValue,
                                type: selectedSection.browseSectionType
                            ),
                            refresh: true
                        )
                    }
                }
            }
        }
        .onChange(of: selectedSection) { _, section in
            guard section != .rss && section != .downloads else { return }
            browseVM.select(
                section: BrowseSection(
                    id: section.id,
                    title: section.rawValue,
                    type: section.browseSectionType
                ))
        }
        #if os(tvOS)
        // tvOS: player is opened via navigationDestination(item: $selectedVideo).
        // Save offset when selectedVideo is set; restore when it clears.
        .onChange(of: selectedVideo) { old, new in
            if old == nil, new != nil {
                savedScrollOffset = scrollStore.scrollView?.contentOffset.y ?? 0
            } else if old != nil, new == nil, let saved = savedScrollOffset {
                restoreOffset = saved
                savedScrollOffset = nil
            }
        }
        #endif
        .onDisappear {
            // Snapshot scroll position whenever the Library view leaves the screen
            // (player opening, tab switch, navigation push). At onDisappear time the
            // UIScrollView is still in memory and contentOffset is accurate.
            #if os(iOS) || os(tvOS)
            if let offset = scrollStore.scrollView?.contentOffset.y, offset > 0 {
                savedScrollOffset = offset
            }
            #endif
        }
        .onAppear {
            guard selectedSection != .rss && selectedSection != .downloads else { return }
            browseVM.select(
                section: BrowseSection(
                    id: selectedSection.id,
                    title: selectedSection.rawValue,
                    type: selectedSection.browseSectionType
                ))
            // Restore scroll position when returning from the player, another tab,
            // or any navigation that caused onDisappear to fire.
            #if os(iOS) || os(tvOS)
            if let saved = savedScrollOffset {
                restoreOffset = saved
                savedScrollOffset = nil
            }
            #endif
        }
        .task(id: selectedSection) {
            guard selectedSection == .playlists else { return }
            queueVideosCount = await CurrentQueueStore.shared.videos.count
        }
    }

    @ViewBuilder private var currentQueueRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "list.number")
                .font(.title2)
                .frame(width: 44, height: 44)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Current Queue")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
                Text("\(queueVideosCount) video\(queueVideosCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        #if os(tvOS)
        .tvFocusRowChrome(isFocused: queueRowFocused)
        #endif
        .onTapGesture {
            selectedPlaylist = Video(
                id: CurrentQueueStore.playlistID,
                title: "Current Queue",
                channelTitle: ""
            )
        }
        #if os(tvOS)
        .background {
            Button {
                selectedPlaylist = Video(
                    id: CurrentQueueStore.playlistID,
                    title: "Current Queue",
                    channelTitle: ""
                )
            } label: {
                Color.clear.contentShape(Rectangle())
            }
            .buttonStyle(TVImmediateSelectButtonStyle())
            .focusEffectDisabled()
            .focused($queueRowFocused)
        }
        #endif
        .accessibilityIdentifier("library.currentQueueRow")
        Divider().padding(.horizontal)
    }

    @ViewBuilder private var emptyLibraryView: some View {
        if !auth.isSignedIn && selectedSection == .subscriptions {
            VStack(spacing: 16) {
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Follow channels to see their latest videos here")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Search") {
                    NotificationCenter.default.post(name: .navigateToSearch, object: nil)
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 16) {
                Image(systemName: AppSymbol.stackLayers)
                    .font(.system(size: 60))
                    .foregroundStyle(.secondary)
                Text("Nothing here yet")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var segmentSignInPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: AppSymbol.personCircleQuestion)
                .font(.system(size: 60))
                .foregroundStyle(.secondary)
            Text("Sign in to see your \(selectedSection.rawValue.lowercased())")
                .font(.headline)
                .foregroundStyle(.secondary)
            NavigationLink("Sign In") {
                SignInView()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension LibraryView {
    @ViewBuilder fileprivate var downloadsContent: some View {
        #if ENABLE_DOWNLOADS
        DownloadsView()
            .environment(DownloadStore.shared)
        #endif
    }
}
