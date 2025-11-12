import 'package:flutter/material.dart';

/// Widget para mostrar un buscador en la parte superior.
class SearchBarWidget extends StatelessWidget {
  final ValueChanged<String>? onChanged;
  final VoidCallback? onClear;
  final TextEditingController? controller;
  const SearchBarWidget({super.key, this.onChanged, this.onClear, this.controller});

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
            controller: controller,
            onChanged: onChanged,
            decoration: InputDecoration(
              hintText: 'Buscar por título, autor o categoría...',
              hintStyle: const TextStyle(
                color: Colors.black54,
                fontWeight: FontWeight.w400,
              ),
              prefixIcon: const Icon(Icons.search, color: Colors.black54),
              suffixIcon: onClear != null ? IconButton(
                icon: const Icon(Icons.close, color: Colors.black54),
                onPressed: onClear,
                tooltip: 'Limpiar',
              ) : null,
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
