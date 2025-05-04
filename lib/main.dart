import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:share_plus/share_plus.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(NewsApp());
}

class NewsApp extends StatefulWidget {
  @override
  _NewsAppState createState() => _NewsAppState();
}

class _NewsAppState extends State<NewsApp> {
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadThemePreference();
  }

  void _loadThemePreference() async {
    final prefs = await SharedPreferences.getInstance();
    final themeString = prefs.getString('themeMode') ?? 'system';
    setState(() {
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.toString().split('.').last == themeString,
        orElse: () => ThemeMode.system,
      );
    });
  }

  void toggleTheme() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
      prefs.setString('themeMode', _themeMode.toString().split('.').last);
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BareNews',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.grey.shade100,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white, // Keep solid white
          elevation: 0, // No shadow, change to 1–4 for subtle shadow
          iconTheme: IconThemeData(color: Colors.black),
          titleTextStyle: GoogleFonts.openSans(
            color: Colors.black,
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
        ),
        textTheme: GoogleFonts.openSansTextTheme(),
        colorScheme: ColorScheme.fromSwatch(primarySwatch: Colors.indigo),
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Color(0xFF121212), // darker background
        textTheme: GoogleFonts.openSansTextTheme(
          ThemeData(brightness: Brightness.dark).textTheme,
        ),
        colorScheme: ColorScheme.fromSwatch(
          primarySwatch: Colors.indigo,
          brightness: Brightness.dark,
        ),
      ),
      themeMode: _themeMode,
      home: NewsHomePage(toggleTheme: toggleTheme),
    );
  }
}

class NewsHomePage extends StatefulWidget {
  final VoidCallback toggleTheme;
  NewsHomePage({required this.toggleTheme});

  @override
  _NewsHomePageState createState() => _NewsHomePageState();
}

class _NewsHomePageState extends State<NewsHomePage> {
  List articles = [];
  bool loading = false;
  String selectedCategory = 'general';

  int page = 1;
  final int limit = 10;

  final ScrollController _scrollController = ScrollController();

  final List<String> categories = [
    'general', 'business', 'entertainment', 'health', 'science', 'sports', 'technology'
  ];

  Future<void> fetchArticles({int requestedPage = 1}) async {
    if (loading) return;

    setState(() => loading = true);

    final apiKey = dotenv.env['API_KEY'];
    final baseUrl = dotenv.env['API_BASE_URL'];

    if (apiKey == null || baseUrl == null) {
      debugPrint('Missing API key or base URL from .env');
      setState(() {
        loading = false;
        articles = [];
      });
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final blocked = prefs.getStringList('blockedSources') ?? [];
    final blockedQuery = blocked.join(',');

    final response = await http.get(
      Uri.parse('$baseUrl/articles?category=$selectedCategory&blocked_sources=$blockedQuery&page=$requestedPage&limit=$limit'),
      headers: {
        'X-Api-Key': apiKey,
      },
    );

    if (response.statusCode == 200) {
      final List newArticles = json.decode(response.body);
      final isLastPage = newArticles.length < limit;

      setState(() {
        page = requestedPage;
        if (requestedPage == 1) {
          articles = newArticles;
        } else {
          articles.addAll(newArticles);
        }
        loading = false;
      });

      if (isLastPage) {
        _scrollController.removeListener(_loadMore);
      }
    } else {
      debugPrint('Failed to load articles: ${response.statusCode}');
      setState(() => loading = false);
    }
  }

  void _loadMore() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200 && !loading) {
      fetchArticles(requestedPage: page + 1);
    }
  }

  void _fetchAndRefresh() {
    fetchArticles(requestedPage: 1);
  }

  @override
  void initState() {
    super.initState();
    fetchArticles();
    _scrollController.addListener(_loadMore);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('BareNews'),
        scrolledUnderElevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.search),
            onPressed: () {
              showSearch(
                context: context,
                delegate: ArticleSearchDelegate(),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: () => fetchArticles(requestedPage: 1),
            tooltip: 'Refresh Articles',
          ),
          IconButton(
            icon: Icon(Icons.brightness_6),
            onPressed: widget.toggleTheme,
            tooltip: 'Toggle Theme',
          ),
          IconButton(
            icon: Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => BlockedSourcesPage(onUnblock: _fetchAndRefresh)),
              );
            },
            tooltip: 'Manage Blocked Sources',
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: 50,
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: categories.map((category) {
                final isSelected = selectedCategory == category;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(category.toUpperCase()),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        selectedCategory = category;
                        page = 1;
                      });
                      _scrollController.removeListener(_loadMore);
                      _scrollController.addListener(_loadMore);
                      fetchArticles(requestedPage: 1);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Expanded(
            child: articles.isEmpty && loading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: articles.length + (loading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= articles.length) {
                        return Center(child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: CircularProgressIndicator(),
                        ));
                      }

                      final article = articles[index];
                      final sourceName = article['source_name'] ?? ''; // Replace with actual key

                      return Dismissible(
                        key: Key(article['url']),
                        direction: DismissDirection.endToStart,
                        background: Container(
                          color: Colors.red,
                          alignment: Alignment.centerRight,
                          padding: EdgeInsets.only(right: 20),
                          child: Icon(Icons.block, color: Colors.white),
                        ),
                        confirmDismiss: (direction) async {
                          return await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: Text('Block Source?'),
                              content: Text('Do you want to block "${sourceName}" and remove all its articles?'),
                              actions: [
                                ElevatedButton(
                                  onPressed: () => Navigator.of(context).pop(true),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                  child: Text('Block'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.of(context).pop(false),
                                  child: Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.indigo[200] // or any light accent color you prefer
                                          : Colors.indigo,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                        onDismissed: (_) async {
                          final prefs = await SharedPreferences.getInstance();
                          final blocked = prefs.getStringList('blockedSources') ?? [];
                          if (!blocked.contains(sourceName)) {
                            blocked.add(sourceName);
                            await prefs.setStringList('blockedSources', blocked);
                          }

                          setState(() {
                            articles.removeAt(index);
                          });
                        },
                        child: Card(
                          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.zero, // Removes rounding
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (article['url_to_image'] != null)
                                  Image.network(
                                    article['url_to_image'],
                                    width: double.infinity,
                                    height: 200,
                                    fit: BoxFit.cover,
                                  ),
                                SizedBox(height: 12),
                                Text(
                                  article['title'] ?? 'No Title',
                                  style: Theme.of(context).textTheme.titleMedium,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                SizedBox(height: 6),
                                Text(
                                  article['description'] ?? '',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (sourceName.isNotEmpty) ...[
                                  SizedBox(height: 8),
                                  Text(
                                    'Source: $sourceName',
                                    style: TextStyle(color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                                  ),
                                ],
                                SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ArticleWebView(
                                          url: article['url'],
                                          title: article['title'] ?? 'Article',
                                        ),
                                      ),
                                    ),
                                    child: Text(
                                      'Read More',
                                      style: TextStyle(
                                        color: Theme.of(context).brightness == Brightness.dark
                                            ? Colors.indigo[200] // or any light accent color you prefer
                                            : Colors.indigo,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  ),
          ),
        ],
      ),
    );
  }
}

class ArticleSearchDelegate extends SearchDelegate {
  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      IconButton(
        icon: Icon(Icons.clear),
        onPressed: () => query = '',
      )
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return FutureBuilder<List>(
      future: _searchArticles(query),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.isEmpty) {
          return Center(child: Text('No results found.'));
        }

        final results = snapshot.data!;
        return ListView.builder(
          itemCount: results.length,
          itemBuilder: (context, index) {
            final article = results[index];
            final sourceName = article['source_name'] ?? '';

            return Dismissible(
              key: Key(article['url']),
              direction: DismissDirection.endToStart,
              background: Container(
                color: Colors.red,
                alignment: Alignment.centerRight,
                padding: EdgeInsets.only(right: 20),
                child: Icon(Icons.block, color: Colors.white),
              ),
              confirmDismiss: (direction) async {
                return await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('Block Source?'),
                    content: Text('Block "$sourceName" and remove its articles?'),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                        child: Text('Block', style: TextStyle(color: Colors.white)),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: Text('Cancel'),
                      ),
                    ],
                  ),
                );
              },
              onDismissed: (_) async {
                final prefs = await SharedPreferences.getInstance();
                final blocked = prefs.getStringList('blockedSources') ?? [];
                if (!blocked.contains(sourceName)) {
                  blocked.add(sourceName);
                  await prefs.setStringList('blockedSources', blocked);
                }
              },
              child: Card(
                margin: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (article['url_to_image'] != null)
                        Image.network(
                          article['url_to_image'],
                          width: double.infinity,
                          height: 200,
                          fit: BoxFit.cover,
                        ),
                      SizedBox(height: 12),
                      Text(
                        article['title'] ?? 'No Title',
                        style: Theme.of(context).textTheme.titleMedium,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 6),
                      Text(
                        article['description'] ?? '',
                        style: Theme.of(context).textTheme.bodyMedium,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (sourceName.isNotEmpty) ...[
                        SizedBox(height: 8),
                        Text(
                          'Source: $sourceName',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                      SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ArticleWebView(
                                  url: article['url'],
                                  title: article['title'] ?? 'Article',
                                ),
                              ),
                            );
                          },
                          child: Text(
                            'Read More',
                            style: TextStyle(
                              color: Theme.of(context).brightness == Brightness.dark
                                  ? Colors.indigo[200]
                                  : Colors.indigo,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    return Container(); // Optional: show suggestions while typing
  }

  Future<List> _searchArticles(String keyword) async {
    final apiKey = dotenv.env['API_KEY'];
    final baseUrl = dotenv.env['API_BASE_URL'];
    final response = await http.get(
      Uri.parse('$baseUrl/search?q=$keyword&page=1&limit=20'),
      headers: { 'X-Api-Key': apiKey! },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body) as List;
    } else {
      return [];
    }
  }
}

class BlockedSourcesPage extends StatefulWidget {
  final VoidCallback onUnblock;
  const BlockedSourcesPage({super.key, required this.onUnblock});

  @override
  _BlockedSourcesPageState createState() => _BlockedSourcesPageState();
}

class _BlockedSourcesPageState extends State<BlockedSourcesPage> {
  List<String> blockedSources = [];

  @override
  void initState() {
    super.initState();
    _loadBlockedSources();
  }

  Future<void> _loadBlockedSources() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      blockedSources = prefs.getStringList('blockedSources') ?? [];
    });
  }

  Future<void> _unblockSource(String source) async {
    final prefs = await SharedPreferences.getInstance();
    blockedSources.remove(source);
    await prefs.setStringList('blockedSources', blockedSources);
    setState(() {});
    widget.onUnblock();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Blocked Sources')),
      body: blockedSources.isEmpty
          ? Center(child: Text('No blocked sources'))
          : ListView.builder(
              itemCount: blockedSources.length,
              itemBuilder: (context, index) {
                final source = blockedSources[index];
                return ListTile(
                  title: Text(source),
                  trailing: IconButton(
                    icon: Icon(Icons.delete),
                    onPressed: () => _unblockSource(source),
                  ),
                );
              },
            ),
    );
  }
}

class ArticleWebView extends StatefulWidget {
  final String url;
  final String title;
  const ArticleWebView({required this.url, required this.title, super.key});

  @override
  State<ArticleWebView> createState() => _ArticleWebViewState();
}

class _ArticleWebViewState extends State<ArticleWebView> {
  bool loadFailed = false;
  Future<void> _openInBrowser() async {
    final uri = Uri.parse(widget.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not launch browser')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            icon: Icon(Icons.share),
            tooltip: 'Share',
            onPressed: () {
              SharePlus.instance.share(
                ShareParams(
                  text: '${widget.title} – ${widget.url}',
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            onPressed: _openInBrowser,
            tooltip: 'Open in browser',
          ),
        ],
      ),
      body: loadFailed
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text("This site can't be displayed in-app."),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: _openInBrowser,
                    child: const Text("Open in browser"),
                  ),
                ],
              ),
            )
          : InAppWebView(
              key: UniqueKey(),
              initialUrlRequest: URLRequest(url: WebUri(widget.url)),
              initialSettings: InAppWebViewSettings(
                javaScriptEnabled: true,
                allowsBackForwardNavigationGestures: true,
              ),
              onReceivedHttpError: (controller, request, errorResponse) async {
                if (request.isForMainFrame ?? true) {
                  final uri = Uri.tryParse(widget.url);
                  if (!mounted || uri == null) return;

                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  if (mounted) Navigator.of(context).pop();
                }
              },

              onReceivedError: (controller, request, error) async {
                if (request.isForMainFrame ?? true) {
                  final uri = Uri.tryParse(widget.url);
                  if (!mounted || uri == null) return;

                  await launchUrl(uri, mode: LaunchMode.externalApplication);
                  if (mounted) Navigator.of(context).pop();
                }
              },
          )
    );
  }
}
