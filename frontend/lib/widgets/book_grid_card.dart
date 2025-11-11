import 'package:flutter/material.dart';
import '../models/book.dart';
import '../screens/book_player_screen.dart';
import 'package:just_audio/just_audio.dart';
import '../services/tts_service.dart';
import '../models/voice.dart';

/// Card de libro para grid collage estilo Pinterest.
class BookGridCard extends StatefulWidget {
  final Book book;
  const BookGridCard({super.key, required this.book});

  @override
  State<BookGridCard> createState() => _BookGridCardState();
}

class _BookGridCardState extends State<BookGridCard> {
  final AudioPlayer _inlinePlayer = AudioPlayer();
  List<Voice> _voices = [];
  Voice? _voice; // voz seleccionada para inline preview
  bool _loadingVoice = true;
  bool _generating = false;
  bool _expanded = false; // para mostrar controles

  @override
  void initState() {
    super.initState();
    _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      _voices = await TtsService.instance.getVoices();
      _voice = _voices.isNotEmpty ? _voices.first : null;
    } catch (_) {}
    if (mounted) setState(() => _loadingVoice = false);
  }

  Future<void> _playPause() async {
    if (_voice == null || _generating) return;
    if (_inlinePlayer.playing) {
      await _inlinePlayer.pause();
      setState(() {});
      return;
    }
    if (_inlinePlayer.audioSource == null) {
      // Obtener playlist y primer segmento
      setState(() => _generating = true);
      try {
        final playlist = await TtsService.instance.getPlaylist(
          documentId: widget.book.id,
          voiceId: _voice!.id,
          fromOffsetChar: null,
        );
        if (playlist.items.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No hay segmentos listos todavía.')),
          );
        } else {
          final first = playlist.items.first;
          await _inlinePlayer.setUrl(first.url.toString());
          await _inlinePlayer.play();
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al reproducir: $e')),
        );
      } finally {
        if (mounted) setState(() => _generating = false);
      }
    } else {
      await _inlinePlayer.play();
      setState(() {});
    }
  }

  void _openFullPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookPlayerScreen(book: widget.book),
      ),
    );
  }

  @override
  void dispose() {
    _inlinePlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final book = widget.book;
    return Card(
      elevation: 3,
      margin: const EdgeInsets.all(6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      color: Theme.of(context).colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _openFullPlayer,
        onLongPress: () => setState(() => _expanded = !_expanded),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: book.portada != null && book.portada!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        child: Image.network(
                          book.portada!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                        ),
                      )
                    : Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                        ),
                        child: const Center(child: Icon(Icons.book, size: 48)),
                      ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book.titulo,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.autores.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      book.autores.map((a) => a.nombre).join(', '),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: Colors.grey[400],
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      // Botón Play/Pause inline
                      IconButton(
                        iconSize: 28,
                        tooltip: 'Escuchar rápido',
                        icon: _generating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Icon(
                                _inlinePlayer.playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                        onPressed: _generating ? null : _playPause,
                      ),
                      if (_expanded && !_loadingVoice)
                        Expanded(
                          child: DropdownButton<Voice>(
                            value: _voice,
                            isExpanded: true,
                            items: _voices.map((v) {
                              return DropdownMenuItem(
                                value: v,
                                child: Text(
                                  v.voiceCode.split('-').last,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (v) => setState(() => _voice = v),
                          ),
                        )
                      else if (_expanded && _loadingVoice)
                        const Padding(
                          padding: EdgeInsets.only(left: 8.0),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      IconButton(
                        tooltip: 'Abrir reproductor',
                        icon: const Icon(Icons.open_in_full),
                        onPressed: _openFullPlayer,
                      ),
                    ],
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
