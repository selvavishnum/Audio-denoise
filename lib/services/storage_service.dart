import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/constants/app_constants.dart';
import '../models/audio_project.dart';

class StorageService {
  static StorageService? _instance;
  static StorageService get instance => _instance ??= StorageService._();
  StorageService._();

  late Box<AudioProject> _projectsBox;
  final _uuid = const Uuid();

  Future<void> init() async {
    await Hive.initFlutter();
    Hive.registerAdapter(AudioProjectAdapter());
    _projectsBox = await Hive.openBox<AudioProject>(AppConstants.boxProjects);
  }

  Future<String> getRecordingsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/${AppConstants.recordingsDirName}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> getProcessedDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/${AppConstants.processedDirName}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> getExportDir() async {
    final appDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/${AppConstants.exportDirName}');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir.path;
  }

  Future<String> newRecordingPath() async {
    final dir = await getRecordingsDir();
    final id = _uuid.v4().substring(0, 8);
    return '$dir/rec_$id.${AppConstants.recordingExtension}';
  }

  Future<String> newProcessedPath(String originalPath) async {
    final dir = await getProcessedDir();
    final baseName = File(originalPath).uri.pathSegments.last.replaceAll('.m4a', '').replaceAll('.mp3', '').replaceAll('.wav', '');
    return '$dir/${baseName}_clean.${AppConstants.outputExtension}';
  }

  List<AudioProject> getAllProjects() {
    final projects = _projectsBox.values.toList();
    projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return projects;
  }

  Future<AudioProject> saveProject(AudioProject project) async {
    await _projectsBox.put(project.id, project);
    return project;
  }

  Future<void> deleteProject(String id) async {
    final project = _projectsBox.get(id);
    if (project != null) {
      // Delete associated files
      final original = File(project.originalPath);
      if (await original.exists()) await original.delete();

      if (project.processedPath != null) {
        final processed = File(project.processedPath!);
        if (await processed.exists()) await processed.delete();
      }

      await _projectsBox.delete(id);
    }
  }

  Future<AudioProject> createProjectFromFile(String filePath, {String name = ''}) async {
    final file = File(filePath);
    final fileName = file.uri.pathSegments.last;
    final projectName = name.isEmpty
        ? fileName.replaceAll(RegExp(r'\.[^.]+$'), '')
        : name;

    final project = AudioProject(
      id: _uuid.v4(),
      name: projectName,
      originalPath: filePath,
      createdAt: DateTime.now(),
      denoiseMode: AppConstants.modeAiQuick,
    );

    return saveProject(project);
  }

  Future<int> getTotalProjectCount() async {
    return _projectsBox.length;
  }

  Future<double> getTotalStorageUsedMb() async {
    double totalBytes = 0;
    for (final project in _projectsBox.values) {
      final original = File(project.originalPath);
      if (await original.exists()) {
        totalBytes += await original.length();
      }
      if (project.processedPath != null) {
        final processed = File(project.processedPath!);
        if (await processed.exists()) {
          totalBytes += await processed.length();
        }
      }
    }
    return totalBytes / (1024 * 1024);
  }
}
