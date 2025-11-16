// lib/luna_music.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_visualizer/flutter_visualizer.dart';

// ====================================================================
// GLOBAL STATE & DATA MODELS
// ====================================================================

// --- 🌐 Configuration ---
// Ganti dengan Base URL API backend Anda (Node.js/PHP)
const String API_BASE_URL = 'http://10.0.2.2:3000'; 
const int CURRENT_USER_ID = 1; // Contoh User ID

// --- 🎵 Song Model ---
class Song {
  final int id;
  final String title;
  final String artist;
  final String album;
  final int duration; // in seconds
  final String fileUrl;
  final String coverUrl;
  bool isFavorite;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.fileUrl,
    required this.coverUrl,
    this.isFavorite = false,
  });

  factory Song.fromJson(Map<String, dynamic> json) {
    return Song(
      id: json['id'],
      title: json['title'],
      artist: json['artist'],
      album: json['album'],
      duration: json['duration'] ?? 180, // Default 3 minutes if not provided
      fileUrl: json['file_url'],
      coverUrl: json['cover_url'],
      isFavorite: json['is_favorite'] ?? false, // Asumsi API bisa kasih flag ini
    );
  }
}

// --- 🎧 Player State Management (Just Audio related) ---
class PlayerStateNotifier {
  final AudioPlayer _player = AudioPlayer();
  final List<Song> _currentPlaylist = [];
  int _currentIndex = 0;

  AudioPlayer get player => _player;
  List<Song> get currentPlaylist => _currentPlaylist;
  Song? get currentSong => _currentPlaylist.isNotEmpty ? _currentPlaylist[_currentIndex] : null;

  // Stream position, buffered position, and duration
  Stream<PositionData> get positionDataStream => Rx.combineLatest3<Duration, Duration, Duration?, PositionData>(
        _player.positionStream,
        _player.bufferedPositionStream,
        _player.durationStream,
        (position, bufferedPosition, duration) => PositionData(
          position,
          bufferedPosition,
          duration ?? Duration.zero,
        ),
      );

  // Initializer
  Future<void> init(List<Song> songs, {int initialIndex = 0}) async {
    _currentPlaylist.clear();
    _currentPlaylist.addAll(songs);
    _currentIndex = initialIndex;
    if (_currentPlaylist.isNotEmpty) {
      final initialUri = Uri.parse(_currentPlaylist[_currentIndex].fileUrl);
      await _player.setAudioSource(
        AudioSource.uri(initialUri, tag: _currentPlaylist[_currentIndex].title),
      );
    }
  }

  // Controls
  void play() => _player.play();
  void pause() => _player.pause();
  void seek(Duration position) => _player.seek(position);

  Future<void> next() async {
    if (_currentPlaylist.isEmpty) return;
    _currentIndex = (_currentIndex + 1) % _currentPlaylist.length;
    await _loadCurrentSong();
    play();
  }

  Future<void> previous() async {
    if (_currentPlaylist.isEmpty) return;
    _currentIndex = (_currentIndex - 1 + _currentPlaylist.length) % _currentPlaylist.length;
    await _loadCurrentSong();
    play();
  }

  Future<void> toggleShuffle() async {
    await _player.setShuffleModeEnabled(!_player.shuffleModeEnabled);
  }

  Future<void> toggleRepeat() async {
    final newMode = _player.loopMode == LoopMode.off ? LoopMode.one : (_player.loopMode == LoopMode.one ? LoopMode.all : LoopMode.off);
    await _player.setLoopMode(newMode);
  }

  Future<void> _loadCurrentSong() async {
    if (_currentPlaylist.isNotEmpty) {
      final uri = Uri.parse(_currentPlaylist[_currentIndex].fileUrl);
      await _player.setAudioSource(
        AudioSource.uri(uri, tag: _currentPlaylist[_currentIndex].title),
      );
    }
  }

  void dispose() {
    _player.dispose();
  }
}

// Data class for position stream
class PositionData {
  final Duration position;
  final Duration bufferedPosition;
  final Duration duration;

  PositionData(this.position, this.bufferedPosition, this.duration);
}

// Global instance for simple state management
final playerNotifier = PlayerStateNotifier();

// ====================================================================
// API SERVICE (Hanya implementasi fetching all songs dan toggle favorite)
// ====================================================================
class ApiService {
  static Future<List<Song>> fetchSongs() async {
    try {
      final response = await http.get(Uri.parse('$API_BASE_URL/songs'));
      if (response.statusCode == 200) {
        List jsonResponse = json.decode(response.body);
        return jsonResponse.map((song) => Song.fromJson(song)).toList();
      } else {
        throw Exception('Failed to load songs: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching songs: $e');
      return []; // Return empty list on failure
    }
  }

  static Future<bool> toggleFavorite(int songId, bool isFavorite) async {
    final endpoint = isFavorite ? '/favorite/add' : '/favorite/remove';
    try {
      final response = await http.post(
        Uri.parse('$API_BASE_URL$endpoint'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'user_id': CURRENT_USER_ID,
          'song_id': songId,
        }),
      );
      // Asumsi API mengembalikan status 200/201 jika sukses
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('Error toggling favorite: $e');
      return false;
    }
  }
}

// ====================================================================
// MAIN APPLICATION
// ====================================================================
class LunaMusicApp extends StatelessWidget {
  const LunaMusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Luna Music',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.purple,
        scaffoldBackgroundColor: const Color(0xFF121212), // Dark mode default
        useMaterial3: true,
        // UI minimalis: rounded corners besar
        cardTheme: CardTheme(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          margin: EdgeInsets.zero,
        ),
        textTheme: const TextTheme(
          headlineSmall: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          bodyMedium: TextStyle(color: Colors.white70),
          titleMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

// ====================================================================
// SCREEN STRUCTURE (StatefulWidget untuk menampung seluruh state UI)
// ====================================================================
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  List<Song> _allSongs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchAndLoadData();
  }

  // Ambil data lagu dari API dan inisialisasi player
  Future<void> _fetchAndLoadData() async {
    _allSongs = await ApiService.fetchSongs();
    if (_allSongs.isNotEmpty) {
      // Inisialisasi player dengan semua lagu
      await playerNotifier.init(_allSongs); 
    }
    setState(() => _isLoading = false);
  }

  // List Halaman
  late final List<Widget> _pages = [
    HomePage(
      songs: _allSongs, 
      onSongTap: (song) => _playSelectedSong(song),
      onFavoriteToggle: _toggleFavorite,
    ),
    FavoritePage(onSongTap: (song) => _playSelectedSong(song)),
    const PlaylistPage(),
  ];

  // Logic memutar lagu yang dipilih
  void _playSelectedSong(Song selectedSong) {
    final index = _allSongs.indexWhere((s) => s.id == selectedSong.id);
    if (index != -1 && index != playerNotifier._currentIndex) {
      playerNotifier._currentIndex = index;
      playerNotifier._loadCurrentSong().then((_) => playerNotifier.play());
    } else if (index != -1) {
      playerNotifier.play();
    }
    // Jika lagu ada di playlist, tapi player sedang pause, maka play saja.
  }

  // Logic toggle favorite
  Future<void> _toggleFavorite(Song song) async {
    final success = await ApiService.toggleFavorite(song.id, !song.isFavorite);
    if (success) {
      setState(() {
        song.isFavorite = !song.isFavorite;
      });
      // Tampilkan feedback ke user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${song.title} ${song.isFavorite ? 'ditambahkan' : 'dihapus'} dari favorit!')),
        );
      }
    }
  }

  // Navigasi Bottom Bar
  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Colors.purple)),
      );
    }
    
    return Scaffold(
      body: Stack(
        children: [
          // Content Halaman
          Padding(
            padding: const EdgeInsets.only(bottom: 90.0), // Padding untuk MiniPlayer
            child: IndexedStack(
              index: _selectedIndex,
              children: _pages,
            ),
          ),
          // Mini Player
          Align(
            alignment: Alignment.bottomCenter,
            child: MiniPlayer(
              onTap: () {
                // Navigasi ke Player Page
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => const PlayerPage(),
                    transitionsBuilder: (context, animation, secondaryAnimation, child) {
                      const begin = Offset(0.0, 1.0);
                      const end = Offset.zero;
                      const curve = Curves.ease;

                      var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));

                      return SlideTransition(
                        position: animation.drive(tween),
                        child: child,
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.favorite_rounded), label: 'Favorite'),
          BottomNavigationBarItem(icon: Icon(Icons.playlist_play_rounded), label: 'Playlists'),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Colors.purpleAccent,
        unselectedItemColor: Colors.white54,
        backgroundColor: const Color(0xFF1D1D1D),
        type: BottomNavigationBarType.fixed,
        onTap: _onItemTapped,
      ),
    );
  }

  @override
  void dispose() {
    // playerNotifier.dispose(); // Biasanya player tidak didispose di sini agar musik tetap berjalan
    super.dispose();
  }
}


// ====================================================================
// COMPONENTS / PAGES
// ====================================================================

// ------------------- Player Page -------------------
class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  double _volume = 0.5;

  @override
  void initState() {
    super.initState();
    playerNotifier.player.volumeStream.listen((volume) {
      if (mounted) setState(() => _volume = volume);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Now Playing'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: StreamBuilder<Song?>(
        stream: playerNotifier.player.currentIndexStream.map((_) => playerNotifier.currentSong).whereType<Song>(),
        builder: (context, snapshot) {
          final song = snapshot.data ?? playerNotifier.currentSong;
          if (song == null) {
            return const Center(child: Text("No song is currently playing."));
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. Cover Album (Hero Animation)
                Hero(
                  tag: 'album-cover-${song.id}',
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    height: MediaQuery.of(context).size.width * 0.7,
                    width: MediaQuery.of(context).size.width * 0.7,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.5),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                      image: DecorationImage(
                        image: NetworkImage(song.coverUrl),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // 2. Song Title + Artist
                Text(
                  song.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.purpleAccent),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // 3. Progress Bar + Duration
                _buildProgressBar(context),
                const SizedBox(height: 32),

                // 4. Animated Audio Visualizer
                _buildVisualizer(context),
                const SizedBox(height: 32),

                // 5. Control Buttons
                _buildControlButtons(context),
                const SizedBox(height: 24),

                // 6. Volume Control
                _buildVolumeControl(context),
              ],
            ),
          );
        },
      ),
    );
  }

  // Component: Progress Bar
  Widget _buildProgressBar(BuildContext context) {
    return StreamBuilder<PositionData>(
      stream: playerNotifier.positionDataStream,
      builder: (context, snapshot) {
        final positionData = snapshot.data;
        final duration = positionData?.duration ?? Duration.zero;
        final position = positionData?.position ?? Duration.zero;

        return Column(
          children: [
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4.0,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10.0),
                activeTrackColor: Colors.purpleAccent,
                inactiveTrackColor: Colors.white30,
                thumbColor: Colors.white,
                overlayColor: Colors.purple.withOpacity(0.3),
              ),
              child: Slider(
                min: 0.0,
                max: duration.inMilliseconds.toDouble(),
                value: position.inMilliseconds.toDouble().clamp(0.0, duration.inMilliseconds.toDouble()),
                onChanged: (double value) {
                  playerNotifier.seek(Duration(milliseconds: value.round()));
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(_formatDuration(position), style: Theme.of(context).textTheme.bodySmall),
                  Text(_formatDuration(duration), style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // Utility: Format Duration
  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}:${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    }
    return '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  }

  // Component: Control Buttons
  Widget _buildControlButtons(BuildContext context) {
    return StreamBuilder<PlayerState>(
      stream: playerNotifier.player.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final processingState = playerState?.processingState;
        final playing = playerState?.playing ?? false;

        final isLoading = processingState == ProcessingState.loading || processingState == ProcessingState.buffering;

        return StreamBuilder<LoopMode>(
          stream: playerNotifier.player.loopModeStream,
          builder: (context, loopSnapshot) {
            final loopMode = loopSnapshot.data ?? LoopMode.off;
            return StreamBuilder<bool>(
              stream: playerNotifier.player.shuffleModeEnabledStream,
              builder: (context, shuffleSnapshot) {
                final shuffleEnabled = shuffleSnapshot.data ?? false;

                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    // Shuffle Button
                    IconButton(
                      icon: Icon(Icons.shuffle_rounded, color: shuffleEnabled ? Colors.purpleAccent : Colors.white54, size: 28),
                      onPressed: playerNotifier.toggleShuffle,
                    ),

                    // Previous Button
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, color: Colors.white, size: 48),
                      onPressed: playerNotifier.previous,
                    ),

                    // Play/Pause Button
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purpleAccent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.purple.withOpacity(0.4),
                            blurRadius: 10,
                            spreadRadius: 2,
                          )
                        ],
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : IconButton(
                              icon: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 50),
                              onPressed: playing ? playerNotifier.pause : playerNotifier.play,
                            ),
                    ),

                    // Next Button
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 48),
                      onPressed: playerNotifier.next,
                    ),

                    // Repeat Button
                    IconButton(
                      icon: Icon(
                        loopMode == LoopMode.one
                            ? Icons.repeat_one_rounded
                            : (loopMode == LoopMode.all ? Icons.repeat_rounded : Icons.repeat_rounded),
                        color: loopMode != LoopMode.off ? Colors.purpleAccent : Colors.white54,
                        size: 28,
                      ),
                      onPressed: playerNotifier.toggleRepeat,
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  // Component: Volume Control
  Widget _buildVolumeControl(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.volume_down_rounded, color: Colors.white54),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              activeTrackColor: Colors.white,
              inactiveTrackColor: Colors.white30,
              thumbColor: Colors.white,
              overlayColor: Colors.white.withOpacity(0.1),
            ),
            child: Slider(
              min: 0.0,
              max: 1.0,
              value: _volume,
              onChanged: (double value) {
                playerNotifier.player.setVolume(value);
                setState(() => _volume = value);
              },
            ),
          ),
        ),
        const Icon(Icons.volume_up_rounded, color: Colors.white54),
      ],
    );
  }

  // Component: Animated Visualizer
  Widget _buildVisualizer(BuildContext context) {
    return Container(
      height: 80,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Center(
        child: SizedBox(
          height: 60,
          // Anda mungkin perlu menyesuaikan implementasi Visualizer tergantung pada package yang Anda gunakan
          child: Visualizer(
            builder: (BuildContext context, List<int> wave) {
              return BarVisualizer(
                wave: wave,
                height: 60.0,
                width: MediaQuery.of(context).size.width - 80,
                color: Colors.purpleAccent,
                numberOfBars: 30,
              );
            },
          ),
        ),
      ),
    );
  }
}


// ------------------- Mini Player Component -------------------
class MiniPlayer extends StatelessWidget {
  final VoidCallback onTap;
  const MiniPlayer({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Song?>(
      stream: playerNotifier.player.currentIndexStream.map((_) => playerNotifier.currentSong).whereType<Song>(),
      builder: (context, songSnapshot) {
        final currentSong = songSnapshot.data ?? playerNotifier.currentSong;

        return StreamBuilder<PlayerState>(
          stream: playerNotifier.player.playerStateStream,
          builder: (context, stateSnapshot) {
            final playing = stateSnapshot.data?.playing ?? false;
            final isLoading = stateSnapshot.data?.processingState == ProcessingState.loading || 
                             stateSnapshot.data?.processingState == ProcessingState.buffering;

            if (currentSong == null) {
              return const SizedBox.shrink(); // Hide Mini Player if no song is loaded
            }

            return GestureDetector(
              onTap: onTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                height: 80,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFF282828), // Warna gelap Mini Player
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 15,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Hero Animation untuk Cover
                    Hero(
                      tag: 'album-cover-${currentSong.id}',
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          currentSong.coverUrl,
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.music_note, size: 50),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            currentSong.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            currentSong.artist,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    // Control Play/Pause
                    isLoading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(color: Colors.purpleAccent, strokeWidth: 2))
                        : IconButton(
                            icon: Icon(
                              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 30,
                            ),
                            onPressed: playing ? playerNotifier.pause : playerNotifier.play,
                          ),
                    // Control Next
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, color: Colors.white, size: 30),
                      onPressed: playerNotifier.next,
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}


// ------------------- Home Page -------------------
class HomePage extends StatelessWidget {
  final List<Song> songs;
  final Function(Song) onSongTap;
  final Function(Song) onFavoriteToggle;

  const HomePage({
    super.key,
    required this.songs,
    required this.onSongTap,
    required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          title: const Text('LunaMusic', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: Colors.purpleAccent)),
          floating: true,
          pinned: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          elevation: 0,
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16.0),
          sliver: SliverList(
            delegate: SliverChildListDelegate(
              [
                // Search Bar
                _buildSearchBar(context),
                const SizedBox(height: 24),
                // Recently Played/Featured Section
                _buildSectionTitle(context, 'Recently Played 🎶'),
                _buildHorizontalList(context),
                const SizedBox(height: 24),
                // Playlist Section (Placeholder)
                _buildSectionTitle(context, 'Your Playlists 💿'),
                _buildHorizontalList(context), // Reusing widget for placeholder
                const SizedBox(height: 24),
                // List Lagu dari MySQL
                _buildSectionTitle(context, 'All Songs 🎸'),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
        // List Lagu
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final song = songs[index];
                return SongTile(
                  song: song,
                  onTap: () => onSongTap(song),
                  onFavoriteToggle: () => onFavoriteToggle(song),
                );
              },
              childCount: songs.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 20)), // Footer padding
      ],
    );
  }

  // Component: Search Bar
  Widget _buildSearchBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.search_rounded, color: Colors.white54),
          SizedBox(width: 8),
          Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search songs, artists, or albums...',
                hintStyle: TextStyle(color: Colors.white54),
                border: InputBorder.none,
                isDense: true,
              ),
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // Component: Section Title
  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
      ),
    );
  }

  // Component: Horizontal List (Placeholder for Recently Played/Playlists)
  Widget _buildHorizontalList(BuildContext context) {
    return SizedBox(
      height: 150,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: 5,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(right: index == 4 ? 0 : 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.purple.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Icon(Icons.music_note_rounded, size: 50, color: Colors.purpleAccent),
                ),
                const SizedBox(height: 4),
                Text('Item $index', style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ------------------- Song Tile Component -------------------
class SongTile extends StatelessWidget {
  final Song song;
  final VoidCallback onTap;
  final VoidCallback onFavoriteToggle;

  const SongTile({
    super.key,
    required this.song,
    required this.onTap,
    required required this.onFavoriteToggle,
  });

  @override
  Widget build(BuildContext context) {
    // Gunakan ListTile untuk layout yang bagus
    return Card(
      color: Colors.transparent, // Transparan agar terlihat menyatu
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
          child: Row(
            children: [
              // Cover
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  song.coverUrl,
                  width: 50,
                  height: 50,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: 50,
                    height: 50,
                    color: Colors.purple,
                    child: const Icon(Icons.music_note, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Title + Artist
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      song.artist,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // Favorite Button
              IconButton(
                icon: Icon(
                  song.isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: song.isFavorite ? Colors.redAccent : Colors.white54,
                ),
                onPressed: onFavoriteToggle,
              ),
            ],
          ),
        ),
      ),
    );
  }
}


// ------------------- Favorite Page -------------------
class FavoritePage extends StatefulWidget {
  final Function(Song) onSongTap;
  const FavoritePage({super.key, required this.onSongTap});

  @override
  State<FavoritePage> createState() => _FavoritePageState();
}

class _FavoritePageState extends State<FavoritePage> {
  // Karena ini adalah contoh, kita akan ambil dari global state dan filter yang favorit
  // Dalam implementasi nyata, kita harus memanggil GET /favorites/{user_id}
  List<Song> _favoriteSongs = [];

  @override
  void initState() {
    super.initState();
    // Simulasi fetch dan filter lagu favorit
    _filterFavorites();
  }
  
  void _filterFavorites() {
    // Ini mengasumsikan data _allSongs sudah terisi dan memiliki flag isFavorite yang benar.
    // Dalam aplikasi nyata, panggil API /favorites/{user_id}
    setState(() {
      _favoriteSongs = playerNotifier.currentPlaylist.where((s) => s.isFavorite).toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    _filterFavorites(); // Panggil setiap build untuk update otomatis

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Favorites ❤️'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: _favoriteSongs.isEmpty
          ? const Center(child: Text('You have no favorite songs yet!', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _favoriteSongs.length,
              itemBuilder: (context, index) {
                final song = _favoriteSongs[index];
                return SongTile(
                  song: song,
                  onTap: () => widget.onSongTap(song),
                  onFavoriteToggle: () {
                    // Logika untuk menghapus dari favorit
                    final mainScreenState = context.findAncestorStateOfType<_MainScreenState>();
                    mainScreenState?._toggleFavorite(song);
                  },
                );
              },
            ),
    );
  }
}


// ------------------- Playlist Page (Placeholder) -------------------
class PlaylistPage extends StatelessWidget {
  const PlaylistPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Playlists 💿'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          // Add Playlist Button
          IconButton(
            icon: const Icon(Icons.add_box_rounded, color: Colors.purpleAccent),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Feature: Create Playlist (Not Implemented)')),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: const [
          // Placeholder for User Playlists
          ListTile(
            leading: Icon(Icons.list_alt_rounded, color: Colors.purpleAccent, size: 40),
            title: Text('My First Playlist'),
            subtitle: Text('5 Songs'),
            trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ),
          Divider(color: Colors.white10),
          ListTile(
            leading: Icon(Icons.local_fire_department_rounded, color: Colors.orange, size: 40),
            title: Text('Workout Jams'),
            subtitle: Text('15 Songs'),
            trailing: Icon(Icons.arrow_forward_ios_rounded, size: 16),
          ),
          Divider(color: Colors.white10),
          Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: Center(
              child: Text(
                'Full playlist management will be here!',
                style: TextStyle(color: Colors.white54),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
