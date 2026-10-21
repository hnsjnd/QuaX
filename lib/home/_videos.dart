import 'package:dart_twitter_api/twitter_api.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:quax/client/client.dart';
import 'package:quax/constants.dart';
import 'package:quax/generated/l10n.dart';
import 'package:quax/profile/profile.dart';
import 'package:quax/status.dart';
import 'package:quax/tweet/_video.dart';
import 'package:quax/tweet/tweet_context_scope.dart';
import 'package:quax/ui/errors.dart';

/// Vertical, video-only swipe feed (TikTok-style).
class VideoFeedScreen extends StatefulWidget {
  final ScrollController? scrollController;
  final bool showAppBar;

  const VideoFeedScreen({super.key, this.scrollController, this.showAppBar = false});

  @override
  State<VideoFeedScreen> createState() => _VideoFeedScreenState();
}

class _VideoFeedScreenState extends State<VideoFeedScreen> with AutomaticKeepAliveClientMixin<VideoFeedScreen> {
  final List<_VideoTweet> _items = [];
  final PageController _pageController = PageController();
  String? _cursor;
  bool _loading = false;
  bool _hasMore = true;
  Object? _error;
  StackTrace? _stackTrace;
  int _currentPage = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadMore();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() {
      _loading = true;
      _error = null;
      _stackTrace = null;
    });

    final previousCursor = _cursor;
    try {
      final result = await Twitter.searchTweets('filter:videos', cursor: _cursor, product: 'Latest');
      final extracted = <_VideoTweet>[];
      for (final chain in result.chains) {
        for (final tweet in chain.tweets) {
          final video = _firstVideoMedia(tweet);
          if (video != null) {
            extracted.add(_VideoTweet(tweet: tweet, media: video));
          }
        }
      }

      final next = result.cursorBottom;
      final advanced = next != null && next.isNotEmpty && next != previousCursor;

      setState(() {
        _items.addAll(extracted);
        _cursor = next;
        _hasMore = extracted.isNotEmpty && advanced;
        _loading = false;
      });
    } catch (e, st) {
      setState(() {
        _error = e;
        _stackTrace = st;
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _cursor = null;
      _hasMore = true;
      _currentPage = 0;
      _error = null;
      _stackTrace = null;
    });
    await _loadMore();
  }

  void _onPageChanged(int index) {
    setState(() => _currentPage = index);
    if (index >= _items.length - 3) {
      _loadMore();
    }
  }

  void _openComments(_VideoTweet item) {
    final tweet = item.tweet;
    Navigator.pushNamed(
      context,
      routeStatus,
      arguments: StatusScreenArguments(
        id: tweet.idStr!,
        username: tweet.user?.screenName,
        tweetOpened: true,
        initialTweet: tweet,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final l10n = L10n.of(context);

    final body = TweetContextScope(child: _buildBody(l10n));

    if (!widget.showAppBar) {
      return body;
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.videos)),
      body: body,
    );
  }

  Widget _buildBody(L10n l10n) {
    if (_items.isEmpty && _loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_items.isEmpty && _error != null) {
      return FullPageErrorWidget(
        prefix: (l) => l.unable_to_load_the_tweets,
        error: _error,
        stackTrace: _stackTrace,
        onRetry: _refresh,
      );
    }

    if (_items.isEmpty) {
      return Center(child: Text(l10n.unable_to_load_the_tweets_for_the_feed));
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        itemCount: _items.length + (_hasMore || _loading ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _items.length) {
            if (_error != null) {
              return Center(
                child: TextButton(
                  onPressed: _loadMore,
                  child: Text(l10n.retry),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          return _VideoFeedPage(
            item: _items[index],
            active: index == _currentPage,
            onOpenComments: () => _openComments(_items[index]),
          );
        },
      ),
    );
  }
}

Media? _firstVideoMedia(TweetWithCard tweet) {
  final media = tweet.extendedEntities?.media;
  if (media == null) return null;
  for (final m in media) {
    if (m.type == 'video') return m;
  }
  return null;
}

class _VideoTweet {
  final TweetWithCard tweet;
  final Media media;

  _VideoTweet({required this.tweet, required this.media});
}

class _VideoFeedPage extends StatelessWidget {
  final _VideoTweet item;
  final bool active;
  final VoidCallback onOpenComments;

  const _VideoFeedPage({
    required this.item,
    required this.active,
    required this.onOpenComments,
  });

  @override
  Widget build(BuildContext context) {
    final tweet = item.tweet;
    final user = tweet.user;
    final sensitive = tweet.possiblySensitive ?? false;

    return Consumer<TweetContextState>(
      builder: (context, model, _) {
        // Respect the existing hide-sensitive preference; do not hardcode hide.
        if (model.hideSensitive && sensitive) {
          return ColoredBox(
            color: Colors.black,
            child: EmojiErrorWidget(
              emoji: '🍆🙈🍆',
              message: L10n.current.possibly_sensitive,
              errorMessage: L10n.current.possibly_sensitive_tweet,
              retryText: L10n.current.yes_please,
              onRetry: () async => model.setHideSensitive(false),
              showBackButton: false,
            ),
          );
        }

        final metadata = TweetVideoMetadata.fromMedia(item.media);
        final username = user?.screenName ?? '';
        final caption = tweet.fullText ?? tweet.text ?? '';

        return ColoredBox(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: TweetVideo(
                  username: username,
                  loop: true,
                  metadata: metadata,
                  alwaysPlay: active,
                  tweetId: tweet.idStr,
                  mediaIndex: 0,
                  longPressDoubleSpeed: true,
                ),
              ),
              Positioned(
                left: 12,
                right: 72,
                bottom: 88,
                child: GestureDetector(
                  onTap: onOpenComments,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (user != null)
                        Text(
                          '@${user.screenName}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      if (caption.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          caption,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Colors.white, fontSize: 14),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 12,
                bottom: 100,
                child: IconButton(
                  icon: const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 28),
                  tooltip: L10n.of(context).replies,
                  onPressed: onOpenComments,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
