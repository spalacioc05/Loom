import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Banner superior reutilizable con el texto "Loom" y notificación.
class LoomBanner extends StatelessWidget {
  const LoomBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 18, left: 22, right: 22, bottom: 10),
      color:
          Theme.of(context).appBarTheme.backgroundColor ??
          Theme.of(context).colorScheme.background,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Loom',
            style: GoogleFonts.lora(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
            ),
          ),
          const Icon(
            Icons.notifications_none_rounded,
            color: Colors.white,
            size: 28,
          ),
        ],
      ),
    );
  }
}
