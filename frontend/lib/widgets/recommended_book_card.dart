import 'package:flutter/material.dart';
import '../models/book.dart';

/// Card de libro para el carrusel de recomendados, con efecto "staggered".
class RecommendedBookCard extends StatelessWidget {
  final Book book;
  final double offset;
  const RecommendedBookCard({
    super.key,
    required this.book,
    required this.offset,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.translate(
      offset: Offset(0, offset),
      child: Card(
        elevation: 4,
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          width: 220,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(book.titulo, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                book.descripcion ?? 'Sin descripción',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
