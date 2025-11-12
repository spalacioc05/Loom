import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../models/book.dart';
import '../auth/google_auth_service.dart';
import 'dart:io';

class UploadBookScreen extends StatefulWidget {
  const UploadBookScreen({super.key});

  @override
  State<UploadBookScreen> createState() => _UploadBookScreenState();
}

class _UploadBookScreenState extends State<UploadBookScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tituloController = TextEditingController();
  final _descripcionController = TextEditingController();
  
  File? _selectedFile;
  String? _fileName;
  File? _selectedCover;
  String? _coverFileName;
  bool _isUploading = false;
  
  // Categorías seleccionadas (múltiples) y lista de categorías disponibles
  final Set<String> _selectedCategoriasIds = {};
  List<Category> _categorias = [];
  bool _loadingCategorias = true;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final categorias = await ApiService.fetchCategories();
      setState(() {
        _categorias = categorias;
        _loadingCategorias = false;
      });
    } catch (e) {
      setState(() {
        _categorias = [Category(id: '1', nombre: 'General')];
        _loadingCategorias = false;
      });
    }
  }

  Future<void> _pickPDF() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
          _fileName = result.files.single.name;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar archivo: $e')),
      );
    }
  }

  Future<void> _pickCover() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.image,
      );

      if (result != null) {
        setState(() {
          _selectedCover = File(result.files.single.path!);
          _coverFileName = result.files.single.name;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al seleccionar portada: $e')),
      );
    }
  }

  Future<void> _uploadBook() async {
    if (!_formKey.currentState!.validate()) return;
    
    if (_selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona un archivo PDF')),
      );
      return;
    }

    if (_selectedCategoriasIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona al menos una categoría')),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      // Obtener userId del backend para asociar libro a su biblioteca
      String? userId;
      try {
        userId = await GoogleAuthService().getBackendUserId();
      } catch (_) {}

      await ApiService.uploadBook(
        titulo: _tituloController.text,
        descripcion: _descripcionController.text,
        categoriasIds: _selectedCategoriasIds.toList(),
        pdfFile: _selectedFile!,
        coverFile: _selectedCover, // Puede ser null
        userId: userId,
      );

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Libro subido exitosamente'),
          backgroundColor: Colors.green,
        ),
      );

      // Retornar true para indicar que se subió exitosamente
      Navigator.pop(context, true);
      
    } catch (e) {
      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al subir libro: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _tituloController.dispose();
    _descripcionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subir Libro'),
        backgroundColor: Theme.of(context).colorScheme.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Campo de título
              TextFormField(
                controller: _tituloController,
                decoration: InputDecoration(
                  labelText: 'Título del libro *',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.book),
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'El título es requerido';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Campo de descripción
              TextFormField(
                controller: _descripcionController,
                decoration: InputDecoration(
                  labelText: 'Descripción (opcional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.description),
                  alignLabelWithHint: true,
                ),
                maxLines: 4,
              ),
              const SizedBox(height: 24),

              // Selector múltiple de categorías (chips en carousel horizontal)
              _loadingCategorias
                  ? const Center(child: CircularProgressIndicator())
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Categorías *', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            if (_selectedCategoriasIds.isNotEmpty)
                              Text('${_selectedCategoriasIds.length} seleccionadas', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 50,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _categorias.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 8),
                            itemBuilder: (context, index) {
                              final cat = _categorias[index];
                              final selected = _selectedCategoriasIds.contains(cat.id);
                              return FilterChip(
                                label: Text(cat.nombre),
                                selected: selected,
                                onSelected: (value) {
                                  setState(() {
                                    if (value) {
                                      _selectedCategoriasIds.add(cat.id);
                                    } else {
                                      _selectedCategoriasIds.remove(cat.id);
                                    }
                                  });
                                },
                                selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                                checkmarkColor: Theme.of(context).colorScheme.primary,
                              );
                            },
                          ),
                        ),
                        if (_selectedCategoriasIds.isEmpty)
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text('Selecciona al menos una categoría', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                          ),
                      ],
                    ),
              const SizedBox(height: 24),

              // Selector de PDF
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedFile != null 
                        ? Theme.of(context).colorScheme.primary 
                        : Colors.grey,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedFile != null ? Icons.check_circle : Icons.upload_file,
                      size: 64,
                      color: _selectedFile != null 
                          ? Theme.of(context).colorScheme.primary 
                          : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedFile != null 
                          ? 'Archivo seleccionado:' 
                          : 'Ningún archivo seleccionado',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                    if (_fileName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _fileName!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _pickPDF,
                      icon: const Icon(Icons.folder_open),
                      label: Text(_selectedFile != null ? 'Cambiar archivo' : 'Seleccionar PDF'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Selector de Portada (Opcional)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _selectedCover != null 
                        ? Theme.of(context).colorScheme.secondary 
                        : Colors.grey,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      _selectedCover != null ? Icons.image : Icons.add_photo_alternate,
                      size: 64,
                      color: _selectedCover != null 
                          ? Theme.of(context).colorScheme.secondary 
                          : Colors.grey,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _selectedCover != null 
                          ? 'Portada seleccionada:' 
                          : 'Portada (opcional)',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 14,
                      ),
                    ),
                    if (_coverFileName != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _coverFileName!,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _pickCover,
                      icon: const Icon(Icons.image_search),
                      label: Text(_selectedCover != null ? 'Cambiar portada' : 'Seleccionar imagen'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Botón de subir
              ElevatedButton(
                onPressed: _isUploading ? null : _uploadBook,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isUploading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                        ),
                      )
                    : const Text(
                        'Subir Libro',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
