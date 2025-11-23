import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui';
import 'package:dio/dio.dart';
import 'package:external_path/external_path.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
// ============================================================================
// 1. CONFIGURACIÓN E INICIALIZACIÓN
// ============================================================================

const String kApiBaseUrl = "https://api.crocdb.net";
const double kBorderRadius = 28.0; 

@pragma('vm:entry-point')
void downloadCallback(String id, int status, int progress) {
  final SendPort? send = IsolateNameServer.lookupPortByName('downloader_send_port');
  send?.send([id, status, progress]);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  ));

  if (Platform.isAndroid || Platform.isIOS) {
    await FlutterDownloader.initialize(debug: true, ignoreSsl: true);
  }

  runApp(const ProviderScope(child: CrocDbApp()));
}

class AppColors {
  // Modern Android Dark Palette
  static const Color darkBg = Color(0xFF121212); 
  static const Color darkSurface = Color(0xFF1E1E2C);
  static const Color primaryNeon = Color(0xFFBB86FC); 
  static const Color secondaryNeon = Color(0xFF03DAC6); 
  
  // Modern Android Light Palette
  static const Color lightBg = Color(0xFFFDFDF5);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightPrimary = Color(0xFF6750A4); 
  static const Color lightSecondary = Color(0xFF625B71);
}

// ============================================================================
// 2. MODELOS DE DATOS
// ============================================================================

class ConsolePlatform {
  final String id;
  final String name;
  final String brand;
  final Color color; 
  ConsolePlatform({required this.id, required this.name, required this.brand, required this.color});
}

class Rom {
  final String title;
  final String platform;
  final List<String> regions;
  final String romId;
  final String slug;
  final String? coverUrl; 
  final List<DownloadLink> links;

  Rom({required this.title, required this.platform, required this.regions, required this.romId, required this.slug, this.coverUrl, required this.links});

  factory Rom.fromJson(Map<String, dynamic> json) {
    return Rom(
      title: json['title'] ?? 'Unknown Title',
      platform: json['platform'] ?? 'unknown',
      regions: (json['regions'] as List?)?.map((e) => e.toString()).toList() ?? [],
      romId: json['rom_id']?.toString() ?? '',
      slug: json['slug'] ?? '',
      links: (json['links'] as List?)?.map((e) => DownloadLink.fromJson(e)).toList() ?? [],
    );
  }
}

class DownloadLink {
  final String name;
  final String format;
  final String sizeStr;
  final String url;
  final String host;
  DownloadLink({required this.name, required this.format, required this.sizeStr, required this.url, required this.host});
  factory DownloadLink.fromJson(Map<String, dynamic> json) {
    return DownloadLink(
      name: json['name'] ?? 'file', format: json['format'] ?? '', sizeStr: json['size_str'] ?? '', url: json['url'] ?? '', host: json['host'] ?? '',
    );
  }
}

class DownloadTaskModel {
  final String id;
  final String fileName;
  final double progress;
  final bool isDownloading;
  final bool isCompleted;
  final bool isError;
  final String statusMessage;
  final String? finalPath;

  DownloadTaskModel({required this.id, required this.fileName, this.progress = 0.0, this.isDownloading = false, this.isCompleted = false, this.isError = false, this.statusMessage = 'Pendiente', this.finalPath});

  DownloadTaskModel copyWith({double? progress, bool? isDownloading, bool? isCompleted, bool? isError, String? statusMessage, String? finalPath}) {
    return DownloadTaskModel(
      id: id, fileName: fileName, progress: progress ?? this.progress, isDownloading: isDownloading ?? this.isDownloading, isCompleted: isCompleted ?? this.isCompleted, isError: isError ?? this.isError, statusMessage: statusMessage ?? this.statusMessage, finalPath: finalPath ?? this.finalPath,
    );
  }
}

// ============================================================================
// 3. REPOSITORIOS
// ============================================================================

class ApiService {
  final Dio _dio = Dio(BaseOptions(baseUrl: kApiBaseUrl));

  Future<List<Rom>> searchRoms({required String query, List<String>? platforms}) async {
    try {
      final payload = {
        "search_key": query, "max_results": 50, "page": 1,
        if (platforms != null && platforms.isNotEmpty) "platforms": platforms,
      };
      final response = await _dio.post('/search', data: payload);
      if (response.data != null && response.data['data'] != null) {
        return (response.data['data']['results'] as List).map((e) => Rom.fromJson(e)).toList();
      }
      return [];
    } catch (e) { return []; }
  }

  List<ConsolePlatform> getInitialConsoles() {
    return [
      ConsolePlatform(id: 'n64', name: 'Nintendo 64', brand: 'Nintendo', color: Colors.redAccent),
      ConsolePlatform(id: 'nes', name: 'NES', brand: 'Nintendo', color: Colors.grey),
      ConsolePlatform(id: 'snes', name: 'Super Nintendo', brand: 'Nintendo', color: Colors.purpleAccent),
      ConsolePlatform(id: 'gba', name: 'Game Boy Advance', brand: 'Nintendo', color: Colors.indigoAccent),
      ConsolePlatform(id: 'ps1', name: 'PlayStation', brand: 'Sony', color: Colors.blueGrey),
      ConsolePlatform(id: 'genesis', name: 'Sega Genesis', brand: 'Sega', color: Colors.blueAccent),
      ConsolePlatform(id: 'dreamcast', name: 'Dreamcast', brand: 'Sega', color: Colors.orangeAccent),
      ConsolePlatform(id: 'nds', name: 'Nintendo DS', brand: 'Nintendo', color: Colors.pinkAccent),
      ConsolePlatform(id: 'psp', name: 'PSP', brand: 'Sony', color: Colors.black),
    ];
  }
}

// ============================================================================
// 4. GESTIÓN DE ESTADO (RIVERPOD)
// ============================================================================

final themeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);
final apiServiceProvider = Provider((ref) => ApiService());
final navIndexProvider = StateProvider<int>((ref) => 0);

class SearchState {
  final bool isLoading;
  final List<Rom> results;
  final String activePlatformFilter; 
  SearchState({this.isLoading = false, this.results = const [], this.activePlatformFilter = ''});
  SearchState copyWith({bool? isLoading, List<Rom>? results, String? activePlatformFilter}) {
    return SearchState(isLoading: isLoading ?? this.isLoading, results: results ?? this.results, activePlatformFilter: activePlatformFilter ?? this.activePlatformFilter);
  }
}

class SearchNotifier extends StateNotifier<SearchState> {
  final ApiService _api;
  SearchNotifier(this._api) : super(SearchState());

  Future<void> search(String query) async {
    if (query.isEmpty && state.activePlatformFilter.isEmpty) return;
    state = state.copyWith(isLoading: true);
    try {
      List<String>? platforms;
      if (state.activePlatformFilter.isNotEmpty) platforms = [state.activePlatformFilter];
      final results = await _api.searchRoms(query: query.isEmpty ? "mario" : query, platforms: platforms);
      state = state.copyWith(isLoading: false, results: results);
    } catch (e) { state = state.copyWith(isLoading: false); }
  }

  void setPlatformFilter(String platformId) => state = state.copyWith(activePlatformFilter: platformId, results: []); 
  void clearFilter() => state = state.copyWith(activePlatformFilter: '', results: []);
}

final searchProvider = StateNotifierProvider<SearchNotifier, SearchState>((ref) => SearchNotifier(ref.read(apiServiceProvider)));

class DownloadNotifier extends StateNotifier<List<DownloadTaskModel>> {
  DownloadNotifier() : super([]);

  /// NUEVO: Inicializa el gestor y limpia tareas estancadas
  Future<void> initializeDownloader() async {
    final tasks = await FlutterDownloader.loadTasks();
    if (tasks != null) {
      final List<DownloadTaskModel> activeTasks = [];
      for (var task in tasks) {
        if (task.status == DownloadTaskStatus.failed ||
            task.status == DownloadTaskStatus.canceled ||
            task.status == DownloadTaskStatus.undefined) {
          // Eliminamos la tarea del registro nativo
          await FlutterDownloader.remove(taskId: task.taskId);
        } else {
          // Mapeamos las tareas activas o completadas
          activeTasks.add(DownloadTaskModel(
            id: task.taskId,
            fileName: task.filename ?? 'unknown_file',
            progress: task.progress / 100.0,
            isDownloading: task.status == DownloadTaskStatus.running || task.status == DownloadTaskStatus.enqueued,
            isCompleted: task.status == DownloadTaskStatus.complete,
            isError: task.status == DownloadTaskStatus.failed,
            statusMessage: _getStatusMessage(task.status, task.progress),
          ));
        }
      }
      state = activeTasks;
    }
  }

  void updateFromBackground(String id, int status, int progress) {
    final taskStatus = DownloadTaskStatus.fromInt(status);
    
    // Si terminó la descarga en la carpeta privada, iniciamos el movimiento a la pública
    if (taskStatus == DownloadTaskStatus.complete) {
       _finalizeAndroidDownload(id);
    }

    state = [
      for (final t in state)
        if (t.id == id)
          t.copyWith(
            progress: progress / 100.0,
            isDownloading: taskStatus == DownloadTaskStatus.running || taskStatus == DownloadTaskStatus.enqueued,
            isCompleted: taskStatus == DownloadTaskStatus.complete,
            isError: taskStatus == DownloadTaskStatus.failed,
            statusMessage: _getStatusMessage(taskStatus, progress),
          )
        else t
    ];
  }

  Future<void> _finalizeAndroidDownload(String taskId) async {
    final taskIndex = state.indexWhere((t) => t.id == taskId);
    if (taskIndex == -1) return;
    final task = state[taskIndex];

    try {
      final appDir = await getApplicationSupportDirectory();
      final sourceFile = File('${appDir.path}/${task.fileName}');
      if (!await sourceFile.exists()) return;

      final documentsPath = await ExternalPath.getExternalStoragePublicDirectory(ExternalPath.DIRECTORY_DOCUMENTS);
      final targetDir = Directory('$documentsPath/RomsDownloader');
      if (!await targetDir.exists()) await targetDir.create(recursive: true);

      final targetFile = File('${targetDir.path}/${task.fileName}');
      
      // Copiar a la carpeta pública y borrar la copia privada
      await sourceFile.copy(targetFile.path);
      await sourceFile.delete();

      state = [
        for (final t in state)
          if (t.id == taskId) t.copyWith(statusMessage: 'Guardado en Docs/RomsDownloader', finalPath: targetFile.path) else t
      ];
    } catch (e) {
      state = [
        for (final t in state)
          if (t.id == taskId) t.copyWith(statusMessage: 'Error moviendo archivo') else t
      ];
    }
  }

  String _getStatusMessage(DownloadTaskStatus status, int progress) {
    if (status == DownloadTaskStatus.enqueued) return "En cola...";
    if (status == DownloadTaskStatus.running) return "Descargando $progress%";
    if (status == DownloadTaskStatus.complete) return "Procesando...";
    if (status == DownloadTaskStatus.failed) return "Falló";
    return "Pendiente";
  }

  Future<void> startDownload(DownloadLink link) async {
    if (Platform.isAndroid) {
      // Pedimos los permisos necesarios
      if (await Permission.manageExternalStorage.request().isDenied) {
         await Permission.storage.request();
      }
      final appDir = await getApplicationSupportDirectory();
      final fileName = link.name.isNotEmpty ? link.name : 'download_${DateTime.now().millisecondsSinceEpoch}.zip';

      final taskId = await FlutterDownloader.enqueue(
        url: link.url, savedDir: appDir.path, fileName: fileName,
        showNotification: true, openFileFromNotification: false, saveInPublicStorage: false,
      );

      if (taskId != null) {
        state = [...state, DownloadTaskModel(id: taskId, fileName: fileName, isDownloading: true, statusMessage: 'Iniciando...')];
      }
      return;
    }
    // Desktop logic omitted
  }
}

final downloadsProvider = StateNotifierProvider<DownloadNotifier, List<DownloadTaskModel>>((ref) => DownloadNotifier());
final activeDownloadsCountProvider = Provider<int>((ref) => ref.watch(downloadsProvider).where((t) => t.isDownloading).length);

// ============================================================================
// 5. LISTENER DE PUERTO
// ============================================================================

class DownloadPortListener extends ConsumerStatefulWidget {
  final Widget child;
  const DownloadPortListener({super.key, required this.child});
  @override
  ConsumerState<DownloadPortListener> createState() => _DownloadPortListenerState();
}

class _DownloadPortListenerState extends ConsumerState<DownloadPortListener> {
  final ReceivePort _port = ReceivePort();
  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid || Platform.isIOS) {
      IsolateNameServer.registerPortWithName(_port.sendPort, 'downloader_send_port');
      _port.listen((dynamic data) => ref.read(downloadsProvider.notifier).updateFromBackground(data[0], data[1], data[2]));
      FlutterDownloader.registerCallback(downloadCallback);
      
      // Llamamos al inicializador en el primer frame para limpiar tareas estancadas
      WidgetsBinding.instance.addPostFrameCallback((_) {
         ref.read(downloadsProvider.notifier).initializeDownloader();
      });
    }
  }
  @override
  void dispose() {
    if (Platform.isAndroid || Platform.isIOS) IsolateNameServer.removePortNameMapping('downloader_send_port');
    super.dispose();
  }
  @override
  Widget build(BuildContext context) => widget.child;
}

// ============================================================================
// 6. UI MODERNA MATERIAL 3
// ============================================================================

class CrocDbApp extends ConsumerWidget {
  const CrocDbApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeProvider);
    
    return MaterialApp(
      title: 'CrocDB',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.lightPrimary,
          brightness: Brightness.light,
          surface: AppColors.lightBg,
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
        navigationBarTheme: const NavigationBarThemeData(
          labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        )
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkBg,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryNeon,
          brightness: Brightness.dark,
          surface: AppColors.darkBg,
        ),
        textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.darkSurface,
          indicatorColor: AppColors.primaryNeon.withOpacity(0.2),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        )
      ),
      home: const DownloadPortListener(child: MainLayoutScreen()),
    );
  }
}

class MainLayoutScreen extends ConsumerWidget {
  const MainLayoutScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idx = ref.watch(navIndexProvider);
    final activeDownloads = ref.watch(activeDownloadsCountProvider);

    return Scaffold(
      body: IndexedStack(
        index: idx,
        children: const [
          HomeConsolesTab(),
          SearchRomTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: idx,
        onDestinationSelected: (i) {
          if (i == 0) ref.read(searchProvider.notifier).clearFilter();
          ref.read(navIndexProvider.notifier).state = i;
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
            label: 'Explorar',
          ),
        ],
      ),
      floatingActionButton: activeDownloads > 0 || idx == 1 ? FloatingActionButton(
        onPressed: () => _showDownloads(context),
        child: Badge(
          isLabelVisible: activeDownloads > 0,
          label: Text(activeDownloads.toString()),
          child: const Icon(Icons.download),
        ),
      ) : null,
    );
  }

  void _showDownloads(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => const DownloadsSheet(),
    );
  }
}

// ----------------------------------------------------------------------------
// PESTAÑA 1: HOME (CONSOLAS)
// ----------------------------------------------------------------------------

class HomeConsolesTab extends ConsumerWidget {
  const HomeConsolesTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final consoles = ref.read(apiServiceProvider).getInitialConsoles();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CustomScrollView(
      slivers: [
        SliverAppBar.large(
          title: Text("Plataformas", style: GoogleFonts.orbitron(fontWeight: FontWeight.w900)),
          actions: [
             IconButton(
              icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
              onPressed: () => ref.read(themeProvider.notifier).state = isDark ? ThemeMode.light : ThemeMode.dark,
            ),
          ],
        ),
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 200, 
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 0.85,
            ),
            delegate: SliverChildBuilderDelegate(
              (ctx, i) => ConsoleCard(
                console: consoles[i], 
                onTap: () {
                  ref.read(searchProvider.notifier).setPlatformFilter(consoles[i].id);
                  ref.read(navIndexProvider.notifier).state = 1;
                }
              ).animate().fadeIn(delay: (50 * i).ms).scale(),
              childCount: consoles.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }
}

class ConsoleCard extends StatelessWidget {
  final ConsolePlatform console;
  final VoidCallback onTap;
  const ConsoleCard({super.key, required this.console, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kBorderRadius),
        side: BorderSide(color: theme.colorScheme.outline.withOpacity(0.1)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      console.color.withOpacity(0.1),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: -20,
              bottom: -20,
              child: Icon(
                FontAwesomeIcons.gamepad,
                size: 100,
                color: console.color.withOpacity(0.1),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(FontAwesomeIcons.gamepad, color: console.color, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    console.id.toUpperCase(),
                    style: GoogleFonts.orbitron(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    console.name,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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

// ----------------------------------------------------------------------------
// PESTAÑA 2: BÚSQUEDA Y RESULTADOS
// ----------------------------------------------------------------------------

class SearchRomTab extends ConsumerStatefulWidget {
  const SearchRomTab({super.key});
  @override
  ConsumerState<SearchRomTab> createState() => _SearchRomTabState();
}

class _SearchRomTabState extends ConsumerState<SearchRomTab> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(searchProvider);
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text("Explorar", style: GoogleFonts.orbitron(fontWeight: FontWeight.bold)),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(70),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    SearchBar(
                      controller: _ctrl,
                      hintText: "Busca juegos (ej. Zelda)",
                      leading: const Icon(Icons.search),
                      onSubmitted: (val) => ref.read(searchProvider.notifier).search(val),
                      trailing: [
                        IconButton(
                          icon: const Icon(Icons.arrow_forward),
                          onPressed: () => ref.read(searchProvider.notifier).search(_ctrl.text),
                        )
                      ],
                      elevation: const WidgetStatePropertyAll(0),
                      backgroundColor: WidgetStatePropertyAll(theme.colorScheme.surfaceContainerHigh),
                    ),
                    if (state.activePlatformFilter.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Row(
                          children: [
                            InputChip(
                              label: Text("Filtro: ${state.activePlatformFilter.toUpperCase()}"),
                              onDeleted: () => ref.read(searchProvider.notifier).clearFilter(),
                              selected: true,
                            ),
                          ],
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),
          
          if (state.isLoading)
             const SliverFillRemaining(child: Center(child: CircularProgressIndicator())),
          
          if (!state.isLoading && state.results.isEmpty)
             SliverFillRemaining(
               child: Center(
                 child: Column(
                   mainAxisAlignment: MainAxisAlignment.center,
                   children: [
                     Icon(Icons.search_off, size: 64, color: theme.colorScheme.outline),
                     const SizedBox(height: 16),
                     const Text("Sin resultados"),
                   ],
                 ),
               ),
             ),

          SliverList(
            delegate: SliverChildBuilderDelegate(
              (ctx, i) {
                final rom = state.results[i];
                return RomListItem(rom: rom).animate().fadeIn(delay: (30 * i).ms).slideX();
              },
              childCount: state.results.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 80)),
        ],
      ),
    );
  }
}

class RomListItem extends StatelessWidget {
  final Rom rom;
  const RomListItem({super.key, required this.rom});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (context) => RomDetailScreen(rom: rom)));
      },
      leading: Container(
        width: 50, height: 50,
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Center(
          child: Icon(FontAwesomeIcons.compactDisc, color: theme.colorScheme.onPrimaryContainer),
        ),
      ),
      title: Text(
        rom.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
        maxLines: 1, overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        "${rom.platform.toUpperCase()} • ${rom.regions.join(', ')}",
        style: TextStyle(color: theme.colorScheme.outline),
      ),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

// ----------------------------------------------------------------------------
// PANTALLA DETALLES
// ----------------------------------------------------------------------------

class RomDetailScreen extends ConsumerWidget {
  final Rom rom;
  const RomDetailScreen({super.key, required this.rom});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.large(
            title: Text(rom.title),
            actions: [
              IconButton(
                icon: const Icon(Icons.share),
                onPressed: () {},
              )
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badges
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(label: Text(rom.platform.toUpperCase()), avatar: const Icon(Icons.gamepad, size: 16)),
                      if (rom.regions.isNotEmpty)
                        Chip(label: Text(rom.regions.first), avatar: const Icon(Icons.public, size: 16)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  
                  Text("Información", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  _InfoRow(label: "ID", value: rom.romId),
                  _InfoRow(label: "Slug", value: rom.slug),
                  
                  const SizedBox(height: 32),
                  Text("Descargas Disponibles", style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  
                  if (rom.links.isEmpty)
                    const Text("No hay enlaces disponibles")
                  else
                    ...rom.links.map((link) => Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Card(
                        elevation: 0,
                        color: theme.colorScheme.surfaceContainer,
                        child: ListTile(
                          leading: const Icon(Icons.file_download),
                          title: Text(link.name.isEmpty ? "Archivo ROM" : link.name),
                          subtitle: Text("${link.format} • ${link.sizeStr}"),
                          trailing: FilledButton.tonalIcon(
                            icon: const Icon(Icons.download),
                            label: const Text("Bajar"),
                            onPressed: () {
                              ref.read(downloadsProvider.notifier).startDownload(link);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Añadido a descargas")));
                            },
                          ),
                        ),
                      ),
                    )),
                  
                   const SizedBox(height: 80),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// SHEET DE DESCARGAS (MODAL)
// ----------------------------------------------------------------------------

class DownloadsSheet extends ConsumerWidget {
  const DownloadsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloads = ref.watch(downloadsProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      expand: false,
      builder: (_, controller) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text("Gestor de Descargas", style: theme.textTheme.titleLarge),
            ),
            const Divider(height: 1),
            Expanded(
              child: downloads.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.download_done, size: 48, color: theme.colorScheme.outline),
                          const SizedBox(height: 16),
                          const Text("Lista vacía"),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: controller,
                      itemCount: downloads.length,
                      itemBuilder: (context, index) {
                        final task = downloads[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: task.isError 
                                ? theme.colorScheme.errorContainer 
                                : theme.colorScheme.primaryContainer,
                            child: Icon(
                              task.isCompleted ? Icons.check : (task.isError ? Icons.error : Icons.downloading),
                              color: task.isError ? theme.colorScheme.error : theme.colorScheme.primary,
                            ),
                          ),
                          title: Text(task.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              if (task.isDownloading)
                                LinearProgressIndicator(value: task.progress, borderRadius: BorderRadius.circular(4)),
                              Text(task.statusMessage, style: theme.textTheme.bodySmall),
                            ],
                          ),
                          trailing: task.isCompleted
                            ? Icon(Icons.check_circle, color: theme.colorScheme.primary)
                            : null,
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}