import 'package:flutter/material.dart';

/// Widget para mostrar un buscador en la parte superior.
class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 0),
      child: Center(
        child: SizedBox(
          width: MediaQuery.of(context).size.width * 0.93,
          height: 38,
          child: TextField(
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Buscar por título, autor o categoría...',
              hintStyle: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: const Icon(Icons.search, color: Colors.black54),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 0,
                horizontal: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
