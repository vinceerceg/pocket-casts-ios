import SwiftUI
import PocketCastsServer
import PocketCastsDataModel

struct TopOnePodcastStory: StoryView {
    var duration: TimeInterval = 5.seconds

    let topPodcast: TopPodcast

    var backgroundColor: Color {
        Color(topPodcast.podcast.bgColor())
    }

    var tintColor: Color {
        .white
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                backgroundColor.ignoresSafeArea()

                VStack {
                    VStack {
                        ImageView(ServerHelper.imageUrl(podcastUuid: topPodcast.podcast.uuid, size: 280))
                            .frame(width: 230, height: 230)
                            .aspectRatio(1, contentMode: .fit)
                            .cornerRadius(4)
                            .shadow(radius: 2, x: 0, y: 1)
                            .accessibilityHidden(true)
                        Text(L10n.eoyStoryTopPodcast(topPodcast.podcast.title ?? "", topPodcast.podcast.author ?? ""))
                            .multilineTextAlignment(.center)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(tintColor)
                            .padding(.top)
                        Text(L10n.eoyStoryTopPodcastSubtitle(topPodcast.numberOfPlayedEpisodes, topPodcast.totalPlayedTime.localizedTimeDescription ?? ""))
                            .multilineTextAlignment(.center)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(tintColor)
                            .padding(.top)
                    }
                    .padding(.leading, 40)
                    .padding(.trailing, 40)
                }
            }
        }
    }
}

struct TopOnePodcastStory_Previews: PreviewProvider {
    static var previews: some View {
        TopOnePodcastStory(topPodcast: TopPodcast(podcast: Podcast.previewPodcast(), numberOfPlayedEpisodes: 10, totalPlayedTime: 3600))
    }
}
