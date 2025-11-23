import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

// ============================================================================
// 1. CORE & CONFIGURACIÓN
// ============================================================================

const String kApiBaseUrl = "https://api.crocdb.net";
const double kBorderRadius = 24.0;
const Duration kAnimationDuration = Duration(milliseconds: 400);

class AppColors {
  // Modo Oscuro (Cyberpunk/Neon)
  static const Color darkBg = Color(0xFF0A0A0F);
  static const Color darkSurface = Color(0xFF161622);
  static const Color neonCyan = Color(0xFF00FFFF);
  static const Color neonMagenta = Color(0xFFFF00FF);
  static const Color neonPurple = Color(0xFFBC13FE);
  
  // Modo Claro (Clean/Soft)
  static const Color lightBg = Color(0xFFF5F5FA);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightAccent = Color(0xFF6366F1);
}

// ============================================================================
// 2. MODELOS DE DATOS (DOMAIN LAYER)
// ============================================================================

class ConsolePlatform {
  final String id;
  final String name;
  final String brand;

  ConsolePlatform({required this.id, required this.name, required this.brand});
}

class Rom {
  final String title;
  final String platform;
  final List<String> regions;
  final String romId;
  final String slug;
  final String? coverUrl; 
  final List<DownloadLink> links;

  Rom({
    required this.title,
    required this.platform,
    required this.regions,
    required this.romId,
    required this.slug,
    this.coverUrl,
    required this.links,
  });

  factory Rom.fromJson(Map<String, dynamic> json) {
    return Rom(
      title: json['title'] ?? 'Unknown Title',
      platform: json['platform'] ?? 'unknown',
      regions: (json['regions'] as List?)?.map((e) => e.toString()).toList() ?? [],
      romId: json['rom_id']?.toString() ?? '',
      slug: json['slug'] ?? '',
      links: (json['links'] as List?)
              ?.map((e) => DownloadLink.fromJson(e))
              .toList() ??
          [],
    );
  }
}

class DownloadLink {
  final String name;
  final String format;
  final String sizeStr;
  final String url;
  final String host;

  DownloadLink({
    required this.name,
    required this.format,
    required this.sizeStr,
    required this.url,
    required this.host,
  });

  factory DownloadLink.fromJson(Map<String, dynamic> json) {
    return DownloadLink(
      name: json['name'] ?? 'file',
      format: json['format'] ?? '',
      sizeStr: json['size_str'] ?? '',
      url: json['url'] ?? '',
      host: json['host'] ?? '',
    );
  }
}

class DownloadTask {
  final String id;
  final String fileName;
  final double progress; // 0.0 a 1.0
  final bool isDownloading;
  final bool isCompleted;
  final bool isError;
  final String statusMessage;

  DownloadTask({
    required this.id,
    required this.fileName,
    this.progress = 0.0,
    this.isDownloading = false,
    this.isCompleted = false,
    this.isError = false,
    this.statusMessage = 'Pendiente',
  });

  DownloadTask copyWith({
    double? progress,
    bool? isDownloading,
    bool? isCompleted,
    bool? isError,
    String? statusMessage,
  }) {
    return DownloadTask(
      id: id,
      fileName: fileName,
      progress: progress ?? this.progress,
      isDownloading: isDownloading ?? this.isDownloading,
      isCompleted: isCompleted ?? this.isCompleted,
      isError: isError ?? this.isError,
      statusMessage: statusMessage ?? this.statusMessage,
    );
  }
}

// ============================================================================
// 3. REPOSITORIOS Y SERVICIOS (DATA LAYER)
// ============================================================================

class ApiService {
  final Dio _dio = Dio(BaseOptions(
    baseUrl: kApiBaseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  Future<List<Rom>> searchRoms({
    required String query,
    List<String>? platforms,
    int page = 1,
  }) async {
    try {
      final payload = {
        "search_key": query,
        "max_results": 50,
        "page": page,
        if (platforms != null && platforms.isNotEmpty) "platforms": platforms,
      };

      final response = await _dio.post('/search', data: payload);
      
      if (response.data != null && response.data['data'] != null) {
        final List results = response.data['data']['results'] ?? [];
        return results.map((e) => Rom.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Error searching ROMs: $e');
    }
  }

  List<ConsolePlatform> getInitialConsoles() {
    return [
      ConsolePlatform(id: 'n64', name: 'Nintendo 64', brand: 'Nintendo'),
      ConsolePlatform(id: 'nes', name: 'NES', brand: 'Nintendo'),
      ConsolePlatform(id: 'snes', name: 'Super Nintendo', brand: 'Nintendo'),
      ConsolePlatform(id: 'gba', name: 'Game Boy Advance', brand: 'Nintendo'),
      ConsolePlatform(id: 'ps1', name: 'PlayStation', brand: 'Sony'),
      ConsolePlatform(id: 'genesis', name: 'Sega Genesis', brand: 'Sega'),
      ConsolePlatform(id: 'dreamcast', name: 'Dreamcast', brand: 'Sega'),
      ConsolePlatform(id: 'nds', name: 'Nintendo DS', brand: 'Nintendo'),
      ConsolePlatform(id: 'psp', name: 'PSP', brand: 'Sony'),
    ];
  }
}

class DownloadService {
  final Dio _dio = Dio();

  Future<void> downloadFile({
    required String url,
    required String fileName,
    required Function(double) onProgress,
    required Function(String path) onSuccess,
    required Function(String error) onError,
  }) async {
    try {
      Directory? dir;
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        dir = await getDownloadsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }

      final savePath = '${dir?.path ?? ""}/$fileName';

      await _dio.download(
        url,
        savePath,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            onProgress(received / total);
          }
        },
      );
      onSuccess(savePath);
    } catch (e) {
      onError(e.toString());
    }
  }
}

// ============================================================================
// 4. ESTADO (RIVERPOD NOTIFIERS)
// ============================================================================

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);
final apiServiceProvider = Provider((ref) => ApiService());

// Navegación principal (0 = Home/Consolas, 1 = Búsqueda)
final navIndexProvider = StateProvider<int>((ref) => 0);

class SearchState {
  final bool isLoading;
  final List<Rom> results;
  final String? error;
  final String activePlatformFilter; 

  SearchState({this.isLoading = false, this.results = const [], this.error, this.activePlatformFilter = ''});

  SearchState copyWith({bool? isLoading, List<Rom>? results, String? error, String? activePlatformFilter}) {
    return SearchState(
      isLoading: isLoading ?? this.isLoading,
      results: results ?? this.results,
      error: error,
      activePlatformFilter: activePlatformFilter ?? this.activePlatformFilter,
    );
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final ApiService _api;
  SearchNotifier(this._api) : super(SearchState());

  Future<void> search(String query) async {
    // Permitir búsqueda vacía si hay un filtro de plataforma para mostrar "populares" o similar (si la API lo soportara)
    // Para esta API, necesitamos query o plataforma.
    if (query.isEmpty && state.activePlatformFilter.isEmpty) return;

    state = state.copyWith(isLoading: true, error: null);
    try {
      List<String>? platforms;
      if (state.activePlatformFilter.isNotEmpty) {
        platforms = [state.activePlatformFilter];
      }
      
      // Si la query está vacía pero hay plataforma, enviamos un término genérico o manejamos según API
      // Aquí asumimos que el usuario escribe algo. 
      final results = await _api.searchRoms(query: query.isEmpty ? "mario" : query, platforms: platforms);
      state = state.copyWith(isLoading: false, results: results);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void setPlatformFilter(String platformId) {
    state = state.copyWith(activePlatformFilter: platformId, results: []); // Limpiar resultados al cambiar filtro
  }

  void clearFilter() {
    state = state.copyWith(activePlatformFilter: '', results: []);
  }
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) {
  return SearchNotifier(ref.read(apiServiceProvider));
});

// Download Manager
class DownloadNotifier extends StateNotifier<List<DownloadTask>> {
  final DownloadService _service = DownloadService();
  DownloadNotifier() : super([]);

  void startDownload(DownloadLink link) {
    final task = DownloadTask(
      id: DateTime.now().toString(),
      fileName: link.name.isNotEmpty ? link.name : 'download.zip',
      isDownloading: true,
      statusMessage: 'Iniciando...',
    );

    state = [...state, task];

    _service.downloadFile(
      url: link.url,
      fileName: task.fileName,
      onProgress: (progress) {
        state = [
          for (final t in state)
            if (t.id == task.id) t.copyWith(progress: progress, statusMessage: 'Descargando ${(progress * 100).toInt()}%') else t
        ];
      },
      onSuccess: (path) {
        state = [
          for (final t in state)
            if (t.id == task.id) 
              t.copyWith(progress: 1.0, isDownloading: false, isCompleted: true, statusMessage: 'Completado: $path') 
            else t
        ];
      },
      onError: (err) {
        state = [
          for (final t in state)
            if (t.id == task.id) 
              t.copyWith(isDownloading: false, isError: true, statusMessage: 'Error: $err') 
            else t
        ];
      },
    );
  }
}

final downloadsProvider = StateNotifierProvider<DownloadNotifier, List<DownloadTask>>((ref) => DownloadNotifier());

// Computed Provider para saber si hay descargas activas
final activeDownloadsCountProvider = Provider<int>((ref) {
  final tasks = ref.watch(downloadsProvider);
  return tasks.where((t) => t.isDownloading).length;
});

// ============================================================================
// 5. WIDGETS UI PERSONALIZADOS
// ============================================================================

class RetroBackground extends StatelessWidget {
  final Widget child;
  const RetroBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Stack(
      children: [
        Container(color: Theme.of(context).scaffoldBackgroundColor),
        if (isDark)
          Positioned.fill(
            child: Opacity(
              opacity: 0.05,
              child: CustomPaint(painter: GridPainter(color: AppColors.neonCyan)),
            ),
          ),
        Positioned(
          top: -100, right: -100,
          child: _buildBlurBlob(isDark ? AppColors.neonPurple : AppColors.lightAccent),
        ),
        Positioned(
          bottom: -100, left: -100,
          child: _buildBlurBlob(isDark ? AppColors.neonCyan : Colors.blueAccent),
        ),
        child,
        if (isDark)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter, end: Alignment.bottomCenter,
                    colors: [Colors.transparent, Colors.black.withOpacity(0.02)],
                    stops: const [0.5, 0.5], tileMode: TileMode.repeated,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBlurBlob(Color color) {
    return Container(
      width: 400, height: 400,
      decoration: BoxDecoration(shape: BoxShape.circle, color: color.withOpacity(0.2)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 80, sigmaY: 80),
        child: Container(color: Colors.transparent),
      ),
    );
  }
}

class GridPainter extends CustomPainter {
  final Color color;
  GridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color..strokeWidth = 1;
    const double spacing = 40;
    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += spacing) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }
  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final double opacity;
  final EdgeInsets? padding;
  final VoidCallback? onTap;

  const GlassCard({super.key, required this.child, this.opacity = 0.05, this.padding, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget content = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withOpacity(opacity),
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: (isDark ? Colors.white : Colors.black).withOpacity(0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 16, spreadRadius: -4, offset: const Offset(0, 10))],
      ),
      child: child,
    );
    if (onTap != null) {
      content = InkWell(onTap: onTap, borderRadius: BorderRadius.circular(kBorderRadius), child: content);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(kBorderRadius),
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: content),
    );
  }
}

class Console3DCard extends StatefulWidget {
  final ConsolePlatform console;
  final VoidCallback onTap;

  const Console3DCard({super.key, required this.console, required this.onTap});

  @override
  State<Console3DCard> createState() => _Console3DCardState();
}

class _Console3DCardState extends State<Console3DCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          transform: Matrix4.identity()..scale(_isHovered ? 1.05 : 1.0)..translate(0.0, _isHovered ? -5.0 : 0.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              colors: [
                isDark ? const Color(0xFF1E1E2C) : Colors.white,
                isDark ? const Color(0xFF161622) : Colors.grey.shade100
              ],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _isHovered ? (isDark ? AppColors.neonCyan.withOpacity(0.3) : Colors.blue.withOpacity(0.2)) : Colors.black.withOpacity(0.1),
                blurRadius: _isHovered ? 20 : 10, offset: Offset(0, _isHovered ? 10 : 5),
              ),
            ],
            border: Border.all(color: _isHovered ? (isDark ? AppColors.neonCyan : Colors.blue) : Colors.transparent, width: 1.5),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -20, bottom: -20,
                child: Opacity(
                  opacity: 0.1,
                  child: Icon(FontAwesomeIcons.gamepad, size: 80, color: isDark ? Colors.white : Colors.black),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      widget.console.id.toUpperCase(),
                      style: GoogleFonts.orbitron(fontSize: 22, fontWeight: FontWeight.bold, color: isDark ? AppColors.neonCyan : AppColors.lightAccent),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.console.name,
                      style: GoogleFonts.rajdhani(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? Colors.grey : Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Botón de Descarga Flotante Global
class GlobalDownloadButton extends ConsumerWidget {
  const GlobalDownloadButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeCount = ref.watch(activeDownloadsCountProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return FloatingActionButton(
      onPressed: () {
        showModalBottomSheet(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (ctx) => const DownloadsSheet(),
        );
      },
      backgroundColor: isDark ? AppColors.neonPurple : AppColors.lightAccent,
      child: Stack(
        alignment: Alignment.center,
        children: [
          const Icon(Icons.download_rounded, color: Colors.white),
          if (activeCount > 0)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                child: Text(
                  activeCount.toString(),
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ).animate().scale(duration: 300.ms, curve: Curves.elasticOut),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// 6. PANTALLAS (UI PRESENTATION)
// ============================================================================

void main() {
  runApp(const ProviderScope(child: CrocDbApp()));
}

class CrocDbApp extends ConsumerWidget {
  const CrocDbApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Retired64 - CROCDB',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.lightBg,
        primaryColor: AppColors.lightAccent,
        textTheme: GoogleFonts.rajdhaniTextTheme(ThemeData.light().textTheme),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkBg,
        primaryColor: AppColors.neonCyan,
        textTheme: GoogleFonts.rajdhaniTextTheme(ThemeData.dark().textTheme).apply(
          bodyColor: Colors.white,
          displayColor: Colors.white,
        ),
        useMaterial3: true,
      ),
      home: const MainLayoutScreen(),
    );
  }
}

// Nueva Pantalla Principal con Navegación por Pestañas
class MainLayoutScreen extends ConsumerWidget {
  const MainLayoutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(navIndexProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      extendBody: true, // Para que el fondo retro cubra todo
      extendBodyBehindAppBar: true,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(70),
        child: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: AppBar(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor.withOpacity(0.5),
              elevation: 0,
              title: Row(
                children: [
                  Icon(FontAwesomeIcons.dragon, color: isDark ? AppColors.neonMagenta : AppColors.lightAccent),
                  const SizedBox(width: 10),
                  Text(
                    "RETIRED64 - CROCDB",
                    style: GoogleFonts.orbitron(fontWeight: FontWeight.w900, letterSpacing: 2),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
                  onPressed: () => ref.read(themeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark,
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ),
      body: RetroBackground(
        child: IndexedStack(
          index: currentIndex,
          children: const [
            HomeConsolesTab(),
            SearchRomTab(),
          ],
        ),
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: NavigationBar(
            height: 70,
            backgroundColor: (isDark ? AppColors.darkSurface : Colors.white).withOpacity(0.8),
            selectedIndex: currentIndex,
            onDestinationSelected: (index) {
              // Si volvemos a Home, limpiamos filtros
              if (index == 0) {
                 ref.read(searchProvider.notifier).clearFilter();
              }
              ref.read(navIndexProvider.notifier).state = index;
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.gamepad_outlined),
                selectedIcon: Icon(Icons.gamepad),
                label: 'Plataformas',
              ),
              NavigationDestination(
                icon: Icon(Icons.search_outlined),
                selectedIcon: Icon(Icons.search),
                label: 'Búsqueda',
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: const GlobalDownloadButton(), // Botón siempre disponible
    );
  }
}

// TAB 1: Consolas
class HomeConsolesTab extends ConsumerWidget {
  const HomeConsolesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final consoles = ref.read(apiServiceProvider).getInitialConsoles();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            Text(
              "EXPLORA PLATAFORMAS",
              style: GoogleFonts.orbitron(
                fontSize: 24,
                color: isDark ? Colors.white : Colors.black87,
                letterSpacing: 1.5,
              ),
            ).animate().fadeIn().slideX(),
            const SizedBox(height: 8),
            Text(
              "Selecciona una consola para buscar tus juegos favoritos.",
              style: TextStyle(color: isDark ? Colors.grey : Colors.grey.shade700),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.only(bottom: 100),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 200,
                  childAspectRatio: 1.0,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: consoles.length,
                itemBuilder: (context, index) {
                  final console = consoles[index];
                  return Console3DCard(
                    console: console,
                    onTap: () {
                      // 1. Establecer filtro
                      ref.read(searchProvider.notifier).setPlatformFilter(console.id);
                      // 2. Realizar búsqueda inicial (opcional, para "todos los juegos" de esa consola)
                      ref.read(searchProvider.notifier).search("mario"); // Búsqueda por defecto o dejar vacío
                      // 3. Cambiar a Tab de Búsqueda
                      ref.read(navIndexProvider.notifier).state = 1;
                    },
                  ).animate().fadeIn(delay: Duration(milliseconds: 50 * index)).slideY(begin: 0.1);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// TAB 2: Búsqueda
class SearchRomTab extends ConsumerStatefulWidget {
  const SearchRomTab({super.key});

  @override
  ConsumerState<SearchRomTab> createState() => _SearchRomTabState();
}

class _SearchRomTabState extends ConsumerState<SearchRomTab> {
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final searchState = ref.watch(searchProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 20),
            // Barra de Búsqueda
            Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 600),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: isDark ? AppColors.neonCyan.withOpacity(0.2) : Colors.black12,
                      blurRadius: 20,
                      spreadRadius: 2,
                    )
                  ],
                ),
                child: TextField(
                  controller: _searchCtrl,
                  onSubmitted: (value) => ref.read(searchProvider.notifier).search(value),
                  style: const TextStyle(fontSize: 18),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: isDark ? AppColors.darkSurface : Colors.white,
                    hintText: 'Busca tu juego (ej. Zelda)...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.arrow_forward),
                      onPressed: () => ref.read(searchProvider.notifier).search(_searchCtrl.text),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(30),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Chips de Filtro Activo
            if (searchState.activePlatformFilter.isNotEmpty)
              Row(
                children: [
                  Text("Filtrando por:", style: TextStyle(color: isDark ? Colors.grey : Colors.grey.shade700)),
                  const SizedBox(width: 10),
                  Chip(
                    label: Text(searchState.activePlatformFilter.toUpperCase()),
                    backgroundColor: isDark ? AppColors.neonPurple.withOpacity(0.2) : AppColors.lightAccent.withOpacity(0.1),
                    deleteIcon: const Icon(Icons.close, size: 18),
                    onDeleted: () {
                      ref.read(searchProvider.notifier).clearFilter();
                    },
                  ).animate().scale(),
                ],
              ),

            const SizedBox(height: 10),

            // Lista de Resultados
            if (searchState.isLoading)
              const Expanded(child: Center(child: CircularProgressIndicator())),
            
            if (!searchState.isLoading && searchState.results.isEmpty && searchState.error == null)
               Expanded(
                 child: Center(
                   child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(Icons.search_off, size: 60, color: Colors.grey.withOpacity(0.5)),
                       const SizedBox(height: 10),
                       const Text("Realiza una búsqueda para ver resultados"),
                     ],
                   ),
                 ),
               ),

            if (searchState.results.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 100),
                  physics: const BouncingScrollPhysics(),
                  itemCount: searchState.results.length,
                  itemBuilder: (context, index) {
                    final rom = searchState.results[index];
                    return RomListCard(rom: rom)
                        .animate()
                        .fadeIn(delay: Duration(milliseconds: 50 * index))
                        .slideX(begin: 0.1);
                  },
                ),
              ),
              
             if (searchState.error != null)
               Expanded(child: Center(child: Text("Error: ${searchState.error}", style: const TextStyle(color: Colors.red)))),
          ],
        ),
      ),
    );
  }
}

class RomListCard extends StatelessWidget {
  final Rom rom;
  const RomListCard({super.key, required this.rom});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlassCard(
        opacity: isDark ? 0.05 : 0.6,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => RomDetailScreen(rom: rom)),
          );
        },
        child: Row(
          children: [
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: isDark ? AppColors.neonPurple.withOpacity(0.2) : Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Icon(FontAwesomeIcons.gamepad, color: isDark ? AppColors.neonCyan : AppColors.lightAccent),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    rom.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _buildBadge(context, rom.platform.toUpperCase(), Colors.purple),
                      const SizedBox(width: 8),
                      if (rom.regions.isNotEmpty)
                        _buildBadge(context, rom.regions.first.toUpperCase(), Colors.teal),
                    ],
                  )
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: isDark ? Colors.white54 : Colors.black54),
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(BuildContext context, String text, MaterialColor color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.5), width: 0.5),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: isDark ? Colors.white : Colors.black, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class RomDetailScreen extends ConsumerWidget {
  final Rom rom;
  const RomDetailScreen({super.key, required this.rom});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      floatingActionButton: const GlobalDownloadButton(), // Botón de descarga también aquí
      body: RetroBackground(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverAppBar(
              expandedHeight: 200,
              pinned: true,
              backgroundColor: Colors.transparent,
              leading: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black26, shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                title: Text(
                  rom.title,
                  style: GoogleFonts.rajdhani(
                    fontWeight: FontWeight.bold,
                    shadows: [const Shadow(blurRadius: 10, color: Colors.black)],
                  ),
                ),
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            isDark ? AppColors.neonPurple : Colors.blue,
                            isDark ? AppColors.neonCyan : Colors.purple,
                          ],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                      ),
                    ),
                    BackdropFilter(filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0), child: Container(color: Colors.black.withOpacity(0.3))),
                    Center(child: Icon(FontAwesomeIcons.compactDisc, size: 100, color: Colors.white.withOpacity(0.2))),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("INFORMACIÓN", style: GoogleFonts.orbitron(fontSize: 18, color: isDark ? AppColors.neonCyan : AppColors.lightAccent)),
                    const SizedBox(height: 10),
                    GlassCard(
                      child: Column(
                        children: [
                          _buildInfoRow("Plataforma", rom.platform.toUpperCase()),
                          _buildInfoRow("Regiones", rom.regions.join(", ")),
                          _buildInfoRow("ID", rom.romId),
                          _buildInfoRow("Slug", rom.slug),
                        ],
                      ),
                    ).animate().slideY(begin: 0.2, duration: 400.ms),

                    const SizedBox(height: 30),
                    Text("DESCARGAS", style: GoogleFonts.orbitron(fontSize: 18, color: isDark ? AppColors.neonMagenta : Colors.pink)),
                    const SizedBox(height: 10),
                    
                    if (rom.links.isEmpty)
                      const Text("No hay enlaces disponibles.")
                    else
                      ...rom.links.map((link) => _buildDownloadItem(context, ref, link)),
                      
                    const SizedBox(height: 80), // Espacio para el FAB
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Flexible(child: Text(value, style: const TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }

  Widget _buildDownloadItem(BuildContext context, WidgetRef ref, DownloadLink link) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GlassCard(
        opacity: isDark ? 0.1 : 0.8,
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.black12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.file_download_outlined),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(link.name.isNotEmpty ? link.name : "Archivo ROM", style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text("${link.format} • ${link.sizeStr} • ${link.host}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            IconButton(
              icon: Icon(Icons.download_rounded, color: isDark ? AppColors.neonCyan : Colors.blue),
              onPressed: () {
                ref.read(downloadsProvider.notifier).startDownload(link);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text("Descarga iniciada"),
                    backgroundColor: isDark ? AppColors.neonPurple : Colors.blue,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// BottomSheet de Descargas
class DownloadsSheet extends ConsumerWidget {
  const DownloadsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.all(20),
      height: MediaQuery.of(context).size.height * 0.6, // Altura fija
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "GESTOR DE DESCARGAS",
                style: GoogleFonts.orbitron(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            ],
          ),
          const Divider(),
          Expanded(
            child: downloads.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(FontAwesomeIcons.boxOpen, size: 50, color: Colors.grey),
                        const SizedBox(height: 10),
                        const Text("No hay descargas activas"),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: downloads.length,
                    itemBuilder: (context, index) {
                      final task = downloads[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black26 : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.withOpacity(0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(child: Text(task.fileName, maxLines: 1, overflow: TextOverflow.ellipsis)),
                                  if (task.isCompleted)
                                    const Icon(Icons.check_circle, color: Colors.green, size: 20)
                                  else if (task.isError)
                                    const Icon(Icons.error, color: Colors.red, size: 20),
                                ],
                              ),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                value: task.progress,
                                backgroundColor: Colors.grey.withOpacity(0.2),
                                color: task.isError ? Colors.red : (task.isCompleted ? Colors.green : AppColors.neonCyan),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                task.statusMessage,
                                style: const TextStyle(fontSize: 10, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}