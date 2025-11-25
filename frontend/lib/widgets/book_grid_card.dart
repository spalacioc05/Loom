import 'package:flutter/material.dart';
import '../models/book.dart';
import '../screens/book_player_screen.dart';
import '../auth/google_auth_service.dart';
import '../services/api_service.dart';

/// Card de libro para grid collage estilo Pinterest.
class BookGridCard extends StatefulWidget {
  final Book book;
  final VoidCallback? onRemoved; // callback para refrescar lista tras "No leer"
  final String? currentUserId; // id del usuario actual para verificar autoría
  const BookGridCard({super.key, required this.book, this.onRemoved, this.currentUserId});

  @override
  State<BookGridCard> createState() => _BookGridCardState();
}

class _BookGridCardState extends State<BookGridCard> {
  bool _menuBusy = false;
  bool _editing = false;
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // No inline voices/playback in this card anymore
  }

  void _openFullPlayer() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookPlayerScreen(book: widget.book),
      ),
    );
  }

  Future<void> _removeFromLibrary() async {
    if (_menuBusy) return;
    setState(() => _menuBusy = true);
    try {
      final userId = await GoogleAuthService().getBackendUserId();
      if (userId == null) throw Exception('Usuario no autenticado');
      await ApiService.removeBookFromLibrary(userId, widget.book.intId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Libro removido de tu biblioteca')),
      );
      widget.onRemoved?.call();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo remover: $e')),
      );
    } finally {
      if (mounted) setState(() => _menuBusy = false);
    }
  }

  Future<void> _deleteBook() async {
    if (_menuBusy) return;
    setState(() => _menuBusy = true);
    try {
      final userId = await GoogleAuthService().getBackendUserId();
      if (userId == null) throw Exception('Usuario no autenticado');
      await ApiService.deleteBook(userId: userId, bookId: widget.book.intId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Libro eliminado')));
      widget.onRemoved?.call();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _menuBusy = false);
    }
  }

  Future<void> _editBook() async {
    if (_editing) return;
    final userId = await GoogleAuthService().getBackendUserId();
    if (userId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No autenticado')));
      return;
    }
    _titleCtrl.text = widget.book.titulo;
    _descCtrl.text = widget.book.descripcion ?? '';
    setState(() => _editing = true);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Editar libro', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Título'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descripción'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        try {
                          await ApiService.updateBook(
                            userId: userId,
                            bookId: widget.book.intId,
                            titulo: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
                            descripcion: _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
                          );
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Actualizado')));
                            widget.onRemoved?.call(); // refresh list to get updated data
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                        } finally {
                          if (mounted) setState(() => _editing = false);
                          Navigator.pop(ctx);
                        }
                      },
                      child: const Text('Guardar'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    ).whenComplete(() {
      if (mounted) setState(() => _editing = false);
    });
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  AspectRatio(
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
                  // Barra de progreso si existe progreso > 0
                  if (book.progreso != null && book.progreso! > 0)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: (book.progreso! / 100).clamp(0.0, 1.0),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              boxShadow: [
                                BoxShadow(
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.5),
                                  blurRadius: 4,
                                )
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  // Badge de porcentaje en esquina superior derecha si hay progreso
                  if (book.progreso != null && book.progreso! > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.7),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${book.progreso!.toInt()}%',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
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
                      const Spacer(),
                      IconButton(
                        tooltip: 'Abrir',
                        icon: const Icon(Icons.open_in_full),
                        onPressed: _openFullPlayer,
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'no_leer') {
                            _removeFromLibrary();
                          } else if (value == 'editar') {
                            _editBook();
                          } else if (value == 'eliminar') {
                            _deleteBook();
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem<String>(
                            value: 'no_leer',
                            child: Row(
                              children: const [
                                Icon(Icons.do_not_disturb, size: 18),
                                SizedBox(width: 8),
                                Text('No leer'),
                              ],
                            ),
                          ),
                          if (widget.book.uploaderId != null && widget.currentUserId != null && widget.book.uploaderId == widget.currentUserId)
                            PopupMenuItem<String>(
                              value: 'editar',
                              child: Row(
                                children: const [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text('Editar'),
                                ],
                              ),
                            ),
                          if (widget.book.uploaderId != null && widget.currentUserId != null && widget.book.uploaderId == widget.currentUserId)
                            PopupMenuItem<String>(
                              value: 'eliminar',
                              child: Row(
                                children: const [
                                  Icon(Icons.delete_forever, size: 18),
                                  SizedBox(width: 8),
                                  Text('Eliminar'),
                                ],
                              ),
                            ),
                        ],
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
