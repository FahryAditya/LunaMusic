// music_player.dart

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'package:just_audio/just_audio.dart';

// Enum untuk mode pengulangan
enum RepeatState { off, one, all }

// Class untuk data lagu yang disederhanakan
class Song {
  final int id;
  final String title;
  final String artist;
  final String uri;
  final int duration;

  Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.uri,
    required this.duration,
  });

  // Factory untuk konversi dari SongModel
  factory Song.fromSongModel(SongModel model) {
    return Song(
      id: model.id,
      title: model.title.isEmpty ? "Unknown Title" : model.title,
      artist: model.artist?.isEmpty ?? true ? "Unknown Artist" : model.artist!,
      uri: model.uri!,
      duration: model.duration ?? 0,
    );
  }
}

// Widget utama aplikasi
class MusicPlayerApp extends StatelessWidget {
  const MusicPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlayerManager();
  }
}

// Stateful Widget untuk manajemen state dan UI utama
class PlayerManager extends StatefulWidget {
  const PlayerManager({super.key});

  @override
  State<PlayerManager> createState() => _PlayerManagerState();
}

class _PlayerManagerState extends State<PlayerManager> with TickerProviderStateMixin {
  // MARK: - Core Services & State
  final OnAudioQuery _audioQuery = OnAudioQuery();
  final AudioPlayer _player = AudioPlayer();

  List<Song> _allSongs = [];
  List<Song> _currentPlaylist = [];
  int _currentIndex = 0;

  // Player State
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  RepeatState _repeatMode = RepeatState.off;
  bool _isShuffle = false;

  // UI State
  bool _isDarkMode = true;
  bool _isPlayerOpen = false;
  String _sortCriteria = 'title'; // title, artist, duration

  // Advanced State
  List<int> _favoriteSongIds = [];

  // MARK: - Animation Controllers
  late AnimationController _diskController;
  late Animation<double> _diskRotation;
  late AnimationController _waveformController;

  // MARK: - Initialization & Disposal

  @override
  void initState() {
    super.initState();
    _diskController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 15),
    )..repeat();
    _diskRotation = Tween<double>(begin: 0, end: 2 * math.pi).animate(_diskController);

    _waveformController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    )..repeat(reverse: true);

    _requestPermissionAndLoadSongs();
    _listenToPlayerState();
    _listenToPosition();
  }

  @override
  void dispose() {
    _player.dispose();
    _diskController.dispose();
    _waveformController.dispose();
    super.dispose();
  }

  // MARK: - Permissions & Song Loading

  Future<void> _requestPermissionAndLoadSongs() async {
    // Meminta izin untuk Android.
    if (!await _audioQuery.permissionsStatus()) {
      await _audioQuery.permissionsRequest();
    }
    await _loadSongs();
  }

  Future<void> _loadSongs() async {
    try {
      List<SongModel> songs = await _audioQuery.querySongs(
        sortType: SongSortType.TITLE,
        orderType: OrderType.ASC_OR_SMALLER,
        uriType: UriType.EXTERNAL,
      );
      // Filter lagu dengan durasi minimal (misal, 5 detik) untuk menghindari file sistem.
      _allSongs = songs.where((s) => (s.duration ?? 0) > 5000 && s.isMusic!).map(Song.fromSongModel).toList();
      _applySorting();
      setState(() {});

      if (_allSongs.isNotEmpty) {
        // Inisialisasi playlist pertama
        _currentPlaylist = List.from(_allSongs);
        _currentIndex = 0;
        await _loadAndPlaySong(_currentPlaylist.first, autoPlay: false);
      }
    } catch (e) {
      // Handle error jika gagal load lagu
      debugPrint('Error loading songs: $e');
    }
  }

  // MARK: - Just Audio Listeners

  void _listenToPlayerState() {
    _player.playerStateStream.listen((state) async {
      final playing = state.playing;
      final processingState = state.processingState;

      if (playing != _isPlaying) {
        setState(() {
          _isPlaying = playing;
        });
        if (playing) {
          _diskController.forward(); // Animasi disc berputar
          _waveformController.forward();
        } else {
          _diskController.stop(); // Animasi disc berhenti
          _waveformController.stop();
        }
      }

      if (processingState == ProcessingState.completed) {
        // Auto play next track setelah selesai
        await _nextTrack(autoPlay: true);
      }
    });

    _player.durationStream.listen((duration) {
      setState(() {
        _totalDuration = duration ?? Duration.zero;
      });
    });
  }

  void _listenToPosition() {
    _player.positionStream.listen((position) {
      setState(() {
        _currentPosition = position;
      });
    });
  }

  // MARK: - Player Controls

  Future<void> _loadAndPlaySong(Song song, {bool autoPlay = true}) async {
    try {
      await _player.setAudioSource(
        AudioSource.uri(Uri.parse(song.uri)),
        initialPosition: Duration.zero,
      );
      if (autoPlay) {
        await _player.play();
      }
      setState(() {
        _totalDuration = _player.duration ?? Duration.zero;
      });
    } catch (e) {
      debugPrint("Error setting audio source: $e");
      // Coba lagu berikutnya jika gagal
      await _nextTrack(autoPlay: true);
    }
  }

  Future<void> _togglePlayPause() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _nextTrack({bool autoPlay = false}) async {
    if (_currentPlaylist.isEmpty) return;

    int newIndex;

    if (_repeatMode == RepeatState.one) {
      // Jika repeat one, putar lagu yang sama lagi.
      newIndex = _currentIndex;
    } else {
      // Logika next (looping)
      newIndex = (_currentIndex + 1) % _currentPlaylist.length;
    }

    setState(() {
      _currentIndex = newIndex;
    });

    await _loadAndPlaySong(_currentPlaylist[_currentIndex], autoPlay: autoPlay);
  }

  Future<void> _previousTrack() async {
    if (_currentPlaylist.isEmpty) return;
    
    // Jika lagu sudah berjalan lebih dari 3 detik, restart lagu
    if (_currentPosition.inSeconds > 3) {
      await _player.seek(Duration.zero);
      return;
    }

    // Logika previous (looping)
    int newIndex = (_currentIndex - 1 + _currentPlaylist.length) % _currentPlaylist.length;

    setState(() {
      _currentIndex = newIndex;
    });

    await _loadAndPlaySong(_currentPlaylist[_currentIndex], autoPlay: true);
  }

  Future<void> _seekTo(double value) async {
    final position = Duration(milliseconds: value.round());
    await _player.seek(position);
  }

  void _toggleRepeatMode() {
    setState(() {
      _repeatMode = RepeatState.values[(_repeatMode.index + 1) % RepeatState.values.length];
      // Atur mode repeat di just_audio
      switch (_repeatMode) {
        case RepeatState.off:
          _player.setLoopMode(LoopMode.off);
          break;
        case RepeatState.one:
          _player.setLoopMode(LoopMode.one);
          break;
        case RepeatState.all:
          _player.setLoopMode(LoopMode.all);
          break;
      }
    });
  }

  void _toggleShuffle() {
    setState(() {
      _isShuffle = !_isShuffle;
      if (_isShuffle) {
        // Membangun ulang playlist dengan urutan acak
        final currentSong = _currentPlaylist[_currentIndex];
        final remainingSongs = _allSongs.where((s) => s.id != currentSong.id).toList();
        remainingSongs.shuffle();
        _currentPlaylist = [currentSong, ...remainingSongs];
        _currentIndex = 0; // Pastikan lagu yang sedang diputar tetap di awal
      } else {
        // Kembali ke urutan sorting asli
        _applySorting();
        _currentIndex = _currentPlaylist.indexWhere((s) => s.id == _player.audioSource?.sequence.first.tag?.id);
        if (_currentIndex == -1) _currentIndex = 0;
      }
    });
  }
  
  // MARK: - Sorting & Filtering

  void _applySorting() {
    _currentPlaylist = List.from(_allSongs); // Reset dari daftar utama

    switch (_sortCriteria) {
      case 'title':
        _currentPlaylist.sort((a, b) => a.title.compareTo(b.title));
        break;
      case 'artist':
        _currentPlaylist.sort((a, b) => a.artist.compareTo(b.artist));
        break;
      case 'duration':
        _currentPlaylist.sort((a, b) => a.duration.compareTo(b.duration));
        break;
    }

    if (_currentIndex >= 0 && _currentIndex < _currentPlaylist.length) {
      // Coba temukan index lagu yang sedang diputar setelah sorting
      final currentPlayingId = _currentPlaylist[_currentIndex].id;
      final newIndex = _currentPlaylist.indexWhere((s) => s.id == currentPlayingId);
      if (newIndex != -1) {
        _currentIndex = newIndex;
      }
    }
  }

  void _onSortChanged(String? newSortCriteria) {
    if (newSortCriteria != null && newSortCriteria != _sortCriteria) {
      setState(() {
        _sortCriteria = newSortCriteria;
        _applySorting();
        // Non-aktifkan shuffle ketika sorting berubah untuk konsistensi
        if (_isShuffle) {
          _isShuffle = false;
        }
      });
    }
  }

  // MARK: - Favorite System

  void _toggleFavorite(int songId) {
    setState(() {
      if (_favoriteSongIds.contains(songId)) {
        _favoriteSongIds.remove(songId);
      } else {
        _favoriteSongIds.add(songId);
      }
    });
  }

  bool _isFavorite(int songId) {
    return _favoriteSongIds.contains(songId);
  }

  // MARK: - UI Builder Methods

  // Helper untuk format durasi
  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    String twoDigitMinutes = twoDigits(d.inMinutes.remainder(60));
    String twoDigitSeconds = twoDigits(d.inSeconds.remainder(60));
    return "${twoDigits(d.inHours)}:$twoDigitMinutes:$twoDigitSeconds".replaceFirst("00:", "");
  }

  // MARK: - Widgets

  // 1. Full Player Screen
  Widget _buildNowPlayingScreen(BuildContext context) {
    if (_currentPlaylist.isEmpty) return const Center(child: Text("No songs loaded"));

    final currentSong = _currentPlaylist[_currentIndex];
    final isFav = _isFavorite(currentSong.id);
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! > 0) { // Swipe kanan
          _previousTrack();
        } else if (details.primaryVelocity! < 0) { // Swipe kiri
          _nextTrack();
        }
      },
      child: Container(
        padding: const EdgeInsets.all(24.0),
        decoration: BoxDecoration(
          color: theme.colorScheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 20,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Column(
          children: [
            // Handle Bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onBackground.withOpacity(0.5),
                borderRadius: BorderRadius.circular(2),
              ),
              margin: const EdgeInsets.only(bottom: 20),
            ),

            // Disc/Cover Art Section
            Expanded(
              child: Column(
                children: [
                  RotationTransition(
                    turns: _diskRotation,
                    child: QueryArtworkWidget(
                      id: currentSong.id,
                      type: ArtworkType.AUDIO,
                      nullArtworkWidget: Container(
                        width: size.width * 0.7,
                        height: size.width * 0.7,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.5),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Icon(Icons.music_note, size: 80, color: theme.colorScheme.onSurface),
                      ),
                      artworkBorder: BorderRadius.circular(size.width * 0.35),
                      artworkFit: BoxFit.cover,
                      size: (size.width * 0.7).toInt(),
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Title and Artist
                  Text(
                    currentSong.title,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onBackground,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    currentSong.artist,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: theme.colorScheme.onBackground.withOpacity(0.7),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),

                  const Spacer(),
                ],
              ),
            ),

            // Waveform (Simulasi)
            _buildWaveformVisualization(theme),
            
            const SizedBox(height: 10),

            // Seek Slider and Timestamps
            Column(
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  ),
                  child: Slider(
                    min: 0.0,
                    max: _totalDuration.inMilliseconds.toDouble(),
                    value: math.min(_currentPosition.inMilliseconds.toDouble(), _totalDuration.inMilliseconds.toDouble()),
                    activeColor: theme.colorScheme.primary,
                    inactiveColor: theme.colorScheme.onBackground.withOpacity(0.3),
                    onChanged: (double value) {
                      _seekTo(value);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatDuration(_currentPosition), style: theme.textTheme.labelSmall),
                      Text(_formatDuration(_totalDuration), style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Main Playback Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Shuffle Button
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: _isShuffle ? theme.colorScheme.primary : theme.colorScheme.onBackground.withOpacity(0.7),
                    size: 24,
                  ),
                  onPressed: _toggleShuffle,
                ),
                // Previous Button
                _buildMediaButton(
                  icon: Icons.skip_previous_rounded,
                  onPressed: _previousTrack,
                  size: 50,
                  iconSize: 30,
                  theme: theme,
                ),
                // Play/Pause Button
                _buildMediaButton(
                  icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  onPressed: _togglePlayPause,
                  size: 70,
                  iconSize: 45,
                  theme: theme,
                  isPrimary: true,
                ),
                // Next Button
                _buildMediaButton(
                  icon: Icons.skip_next_rounded,
                  onPressed: () => _nextTrack(autoPlay: true),
                  size: 50,
                  iconSize: 30,
                  theme: theme,
                ),
                // Repeat Button
                IconButton(
                  icon: Icon(
                    _repeatMode == RepeatState.off ? Icons.repeat_rounded : (_repeatMode == RepeatState.one ? Icons.repeat_one_rounded : Icons.repeat_rounded),
                    color: _repeatMode != RepeatState.off ? theme.colorScheme.primary : theme.colorScheme.onBackground.withOpacity(0.7),
                    size: 24,
                  ),
                  onPressed: _toggleRepeatMode,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Volume Slider & Favorite
            _buildAuxiliaryControls(theme, isFav, currentSong.id),
          ],
        ),
      ),
    );
  }

  // Media Button Helper
  Widget _buildMediaButton({
    required IconData icon,
    required VoidCallback onPressed,
    required double size,
    required double iconSize,
    required ThemeData theme,
    bool isPrimary = false,
  }) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isPrimary ? theme.colorScheme.primary : theme.colorScheme.surface,
        shape: BoxShape.circle,
        boxShadow: isPrimary
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.5),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                )
              ]
            : null,
      ),
      child: IconButton(
        icon: Icon(icon, size: iconSize),
        color: isPrimary ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface,
        onPressed: onPressed,
      ),
    );
  }
  
  // Auxiliary Controls (Volume and Favorite)
  Widget _buildAuxiliaryControls(ThemeData theme, bool isFav, int songId) {
    return Row(
      children: [
        // Volume Control
        Expanded(
          child: Row(
            children: [
              // Mute/Unmute
              IconButton(
                icon: Icon(
                  _player.volume == 0 ? Icons.volume_off : Icons.volume_up,
                  color: theme.colorScheme.onBackground.withOpacity(0.7),
                ),
                onPressed: () {
                  final newVolume = _player.volume > 0 ? 0.0 : 0.5;
                  _player.setVolume(newVolume);
                  setState(() {}); // Untuk update ikon mute/unmute
                },
              ),
              // Volume Slider
              Expanded(
                child: Slider(
                  min: 0.0,
                  max: 1.0,
                  value: _player.volume,
                  activeColor: theme.colorScheme.primary.withOpacity(0.7),
                  inactiveColor: theme.colorScheme.onBackground.withOpacity(0.3),
                  onChanged: (value) {
                    _player.setVolume(value);
                    setState(() {});
                  },
                ),
              ),
            ],
          ),
        ),
        
        // Favorite Button
        IconButton(
          icon: Icon(
            isFav ? Icons.favorite : Icons.favorite_border,
            color: isFav ? Colors.redAccent : theme.colorScheme.onBackground.withOpacity(0.7),
            size: 28,
          ),
          onPressed: () => _toggleFavorite(songId),
        ),
      ],
    );
  }

  // Waveform Visualization (Simulasi)
  Widget _buildWaveformVisualization(ThemeData theme) {
    return SizedBox(
      height: 30,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(20, (index) {
          double minHeight = 5.0;
          double maxHeight = 25.0;
          
          // Animasi naik turun sederhana
          final heightFactor = math.sin((index / 20.0 * math.pi) + (_waveformController.value * 2 * math.pi)).abs();
          final height = minHeight + (maxHeight - minHeight) * heightFactor;

          // Animasi progres bar
          double progressRatio = _currentPosition.inMilliseconds / _totalDuration.inMilliseconds;
          Color color = index / 20.0 < progressRatio
              ? theme.colorScheme.primary // Warna aktif
              : theme.colorScheme.onBackground.withOpacity(0.3); // Warna pasif
          
          // Animasi fade in/out warna
          return AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            width: 4.0,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              boxShadow: color == theme.colorScheme.primary ? [
                BoxShadow(
                  color: color.withOpacity(0.4),
                  blurRadius: 4,
                )
              ] : null,
            ),
          );
        }),
      ),
    );
  }


  // 2. Mini Player
  Widget _buildMiniPlayer(ThemeData theme) {
    if (_currentPlaylist.isEmpty) return const SizedBox.shrink();

    final currentSong = _currentPlaylist[_currentIndex];

    // Progress bar animasi halus
    final double progress = _totalDuration.inMilliseconds > 0
        ? _currentPosition.inMilliseconds / _totalDuration.inMilliseconds
        : 0.0;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _isPlayerOpen = true;
        });
      },
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Mini Player Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
                child: Row(
                  children: [
                    // Cover Art
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: QueryArtworkWidget(
                        id: currentSong.id,
                        type: ArtworkType.AUDIO,
                        nullArtworkWidget: Container(
                          width: 40,
                          height: 40,
                          color: theme.colorScheme.background,
                          child: Icon(Icons.music_note, size: 20, color: theme.colorScheme.onBackground),
                        ),
                        artworkFit: BoxFit.cover,
                        size: 50,
                      ),
                    ),
                    
                    const SizedBox(width: 12),
                    
                    // Song Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            currentSong.title,
                            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                          Text(
                            currentSong.artist,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withOpacity(0.7),
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    
                    // Play/Pause Button
                    IconButton(
                      icon: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, size: 28),
                      color: theme.colorScheme.primary,
                      onPressed: _togglePlayPause,
                    ),
                  ],
                ),
              ),
              
              // Animated Progress Bar
              ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: LinearProgressIndicator(
                  value: progress,
                  valueColor: AlwaysStoppedAnimation<Color>(theme.colorScheme.primary),
                  backgroundColor: Colors.transparent, // Background progress bar dibuat transparan
                  minHeight: 2.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 3. Song List View

  Widget _buildSongList(ThemeData theme) {
    if (_allSongs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      itemCount: _currentPlaylist.length,
      itemBuilder: (context, index) {
        final song = _currentPlaylist[index];
        final isPlayingThis = _currentPlaylist.indexOf(song) == _currentIndex && _isPlaying;
        final isSelected = _currentPlaylist.indexOf(song) == _currentIndex;
        final isFav = _isFavorite(song.id);

        return ListTile(
          leading: QueryArtworkWidget(
            id: song.id,
            type: ArtworkType.AUDIO,
            nullArtworkWidget: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.music_note, color: theme.colorScheme.onSurface, size: 24),
            ),
            artworkBorder: BorderRadius.circular(8),
            artworkFit: BoxFit.cover,
          ),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isPlayingThis ? theme.colorScheme.primary : theme.colorScheme.onBackground,
            ),
          ),
          subtitle: Text(
            song.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onBackground.withOpacity(0.7),
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Favorite Button
              IconButton(
                icon: Icon(
                  isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? Colors.redAccent : theme.colorScheme.onBackground.withOpacity(0.5),
                  size: 20,
                ),
                onPressed: () => _toggleFavorite(song.id),
              ),
              // Duration
              Text(_formatDuration(Duration(milliseconds: song.duration))),
            ],
          ),
          onTap: () {
            // Putar lagu yang dipilih
            setState(() {
              _currentIndex = _currentPlaylist.indexOf(song);
            });
            _loadAndPlaySong(song, autoPlay: true);
          },
        );
      },
    );
  }

  // MARK: - Main Build Method

  @override
  Widget build(BuildContext context) {
    // Tema gelap/terang
    final ThemeData theme = _isDarkMode
        ? ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF1DB954), // Warna Spotify Green
              secondary: Color(0xFF535353),
              background: Color(0xFF121212),
              surface: Color(0xFF282828),
              onBackground: Colors.white,
              onSurface: Colors.white,
            ),
            useMaterial3: true,
          )
        : ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF007AFF), // Warna Apple Music Blue
              secondary: Color(0xFFDCDCDC),
              background: Colors.white,
              surface: Color(0xFFF7F7F7),
              onBackground: Colors.black,
              onSurface: Colors.black,
            ),
            useMaterial3: true,
          );
      
    // Dropdown Sorting
    final dropdown = DropdownButton<String>(
      value: _sortCriteria,
      dropdownColor: theme.colorScheme.surface,
      icon: Icon(Icons.sort, color: theme.colorScheme.onBackground),
      underline: const SizedBox.shrink(),
      onChanged: _onSortChanged,
      items: [
        DropdownMenuItem(value: 'title', child: Text('Judul (A-Z)', style: TextStyle(color: theme.colorScheme.onSurface))),
        DropdownMenuItem(value: 'artist', child: Text('Artist', style: TextStyle(color: theme.colorScheme.onSurface))),
        DropdownMenuItem(value: 'duration', child: Text('Durasi', style: TextStyle(color: theme.colorScheme.onSurface))),
      ],
    );

    return MaterialApp(
      title: 'Flutter Music Player',
      theme: theme,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Local Music Player'),
          backgroundColor: theme.colorScheme.background.withOpacity(0.9),
          actions: [
            // Sorting Dropdown
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: Center(child: dropdown),
            ),
            // Light/Dark Mode Toggle
            IconButton(
              icon: Icon(_isDarkMode ? Icons.light_mode : Icons.dark_mode),
              onPressed: () {
                setState(() {
                  _isDarkMode = !_isDarkMode;
                });
              },
            ),
          ],
        ),
        body: Stack(
          children: [
            // Song List
            _buildSongList(theme),

            // Mini Player (Selalu di bawah jika lagu sedang diputar)
            if (_currentPlaylist.isNotEmpty)
              Align(
                alignment: Alignment.bottomCenter,
                child: AnimatedOpacity(
                  opacity: _isPlayerOpen ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: IgnorePointer(
                    ignoring: _isPlayerOpen,
                    child: _buildMiniPlayer(theme),
                  ),
                ),
              ),

            // Full Player Modal
            if (_currentPlaylist.isNotEmpty)
              AnimatedPositioned(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                left: 0,
                right: 0,
                bottom: _isPlayerOpen ? 0 : -MediaQuery.of(context).size.height,
                height: MediaQuery.of(context).size.height,
                child: Column(
                  children: [
                    Expanded(
                      child: _buildNowPlayingScreen(context),
                    ),
                    // Tombol tutup (opsional, tapi memudahkan navigasi)
                    Container(
                      color: theme.colorScheme.background,
                      padding: const EdgeInsets.only(bottom: 40, top: 10),
                      child: IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                        onPressed: () {
                          setState(() {
                            _isPlayerOpen = false;
                          });
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
