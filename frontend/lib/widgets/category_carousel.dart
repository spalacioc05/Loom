import 'package:flutter/material.dart';

/// Widget para mostrar un carrusel horizontal de tags/categorías minimalista con selección.
class CategoryCarousel extends StatefulWidget {
  final List<String> categories;
  final void Function(int)? onCategorySelected;
  final int? selectedIndex;
  const CategoryCarousel({
    super.key,
    required this.categories,
    this.onCategorySelected,
    this.selectedIndex,
  });

  @override
  State<CategoryCarousel> createState() => _CategoryCarouselState();
}

class _CategoryCarouselState extends State<CategoryCarousel> {
  int? _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.selectedIndex ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    // final Color tagColor = Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.background;
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 0),
      child: SizedBox(
        height: 44,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: MediaQuery.of(context).size.width * 0.035,
          ),
          itemCount: widget.categories.length,
          separatorBuilder: (_, __) => const SizedBox(width: 18),
          itemBuilder: (context, index) {
            final bool selected = _selectedIndex == index;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedIndex = index);
                if (widget.onCategorySelected != null) {
                  widget.onCategorySelected!(index);
                }
              },
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0),
                    child: Text(
                      widget.categories[index],
                      style: TextStyle(
                        fontWeight: FontWeight.w500,
                        fontSize: 17,
                        color: selected ? Colors.white : Colors.white70,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(top: 6),
                    height: 3,
                    width: selected ? 32 : 0,
                    decoration: BoxDecoration(
                      color: selected ? Colors.white : Colors.transparent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
