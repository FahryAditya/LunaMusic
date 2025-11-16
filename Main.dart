// main.dart

import 'package:flutter/material.dart';
import 'package:on_audio_query/on_audio_query.dart';
import 'music_player.dart'; // Import wajib file kedua

void main() {
  // Pastikan binding Flutter sudah diinisialisasi
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MusicPlayerApp());
}
