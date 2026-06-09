import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_colors.dart';
import '../../models/audio_project.dart';
import '../../providers/app_provider.dart';
import '../../widgets/common/glass_card.dart';
import '../denoiser/denoiser_screen.dart';

class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final library = context.watch<LibraryProvider>();

    return Scaffold(
      backgroundColor: AppColors.bgPrimary,
      appBar: AppBar(
        title: Text('Library',
            style: GoogleFonts.rajdhani(
                fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: 1)),
        actions: [
          IconButton(
            icon: Icon(
              library.isGridView ? Icons.view_list : Icons.grid_view,
              color: AppColors.textSecondary,
            ),
            onPressed: library.toggleView,
          ),
        ],
      ),
      body: library.projects.isEmpty
          ? _buildEmptyState()
          : library.isGridView
              ? _buildGrid(context, library)
              : _buildList(context, library),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music,
              size: 72, color: AppColors.textMuted.withOpacity(0.4)),
          const SizedBox(height: 16),
          const Text('No projects yet',
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 18,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 6),
          const Text('Record or import audio to get started',
              style: TextStyle(color: AppColors.textMuted, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildGrid(BuildContext context, LibraryProvider library) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.85,
      ),
      itemCount: library.projects.length,
      itemBuilder: (_, i) => _ProjectGridCard(
        project: library.projects[i],
        isPlaying: library.currentlyPlayingId == library.projects[i].id,
        onPlay: () => library.togglePlay(library.projects[i]),
        onDelete: () => _confirmDelete(context, library, library.projects[i]),
        onOpen: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DenoiserScreen(project: library.projects[i]),
          ),
        ).then((_) => library.loadProjects()),
        delay: (i * 50).ms,
      ),
    );
  }

  Widget _buildList(BuildContext context, LibraryProvider library) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: library.projects.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _ProjectListTile(
        project: library.projects[i],
        isPlaying: library.currentlyPlayingId == library.projects[i].id,
        onPlay: () => library.togglePlay(library.projects[i]),
        onDelete: () => _confirmDelete(context, library, library.projects[i]),
        onOpen: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => DenoiserScreen(project: library.projects[i]),
          ),
        ).then((_) => library.loadProjects()),
        delay: (i * 40).ms,
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, LibraryProvider library, AudioProject project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.bgCard,
        title: const Text('Delete Project',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'Delete "${project.displayName}"? This cannot be undone.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete',
                style: TextStyle(color: AppColors.recording)),
          ),
        ],
      ),
    );
    if (confirm == true) await library.deleteProject(project.id);
  }
}

class _ProjectGridCard extends StatelessWidget {
  final AudioProject project;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onOpen;
  final Duration delay;

  const _ProjectGridCard({
    required this.project,
    required this.isPlaying,
    required this.onPlay,
    required this.onDelete,
    required this.onOpen,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onOpen,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: project.isProcessed
                        ? AppColors.greenGradient
                        : AppColors.primaryGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    project.isProcessed ? Icons.check : Icons.audio_file,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert,
                      color: AppColors.textMuted, size: 18),
                  color: AppColors.bgCard,
                  itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: AppColors.recording, size: 16),
                            SizedBox(width: 8),
                            Text('Delete', style: TextStyle(color: AppColors.recording, fontSize: 13)),
                          ],
                        )),
                  ],
                  onSelected: (v) {
                    if (v == 'delete') onDelete();
                  },
                ),
              ],
            ),
            const Spacer(),
            Text(
              project.displayName,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              project.duration,
              style: const TextStyle(
                  color: AppColors.textMuted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onPlay,
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        color: isPlaying
                            ? AppColors.primaryStart.withOpacity(0.2)
                            : AppColors.bgCardLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isPlaying
                              ? AppColors.primaryStart.withOpacity(0.5)
                              : AppColors.border,
                        ),
                      ),
                      child: Icon(
                        isPlaying ? Icons.stop : Icons.play_arrow,
                        color: isPlaying
                            ? AppColors.primaryStart
                            : AppColors.textSecondary,
                        size: 18,
                      ),
                    ),
                  ),
                ),
                if (project.isProcessed) ...[
                  const SizedBox(width: 6),
                  Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppColors.success.withOpacity(0.3)),
                    ),
                    child: const Center(
                      child: Text('Clean',
                          style: TextStyle(
                              color: AppColors.success,
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ).animate(delay: delay).fadeIn().scale(begin: const Offset(0.95, 0.95));
  }
}

class _ProjectListTile extends StatelessWidget {
  final AudioProject project;
  final bool isPlaying;
  final VoidCallback onPlay;
  final VoidCallback onDelete;
  final VoidCallback onOpen;
  final Duration delay;

  const _ProjectListTile({
    required this.project,
    required this.isPlaying,
    required this.onPlay,
    required this.onDelete,
    required this.onOpen,
    required this.delay,
  });

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('MMM d, HH:mm').format(project.createdAt);
    return GestureDetector(
      onTap: onOpen,
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            GestureDetector(
              onTap: onPlay,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: isPlaying
                      ? AppColors.primaryGradient
                      : null,
                  color: isPlaying ? null : AppColors.bgCardLight,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isPlaying
                        ? AppColors.primaryStart.withOpacity(0.5)
                        : AppColors.border,
                  ),
                ),
                child: Icon(
                  isPlaying ? Icons.stop : Icons.play_arrow,
                  color: isPlaying ? Colors.white : AppColors.textSecondary,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(project.displayName,
                      style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(project.duration,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                      const Text(' · ',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                      Text(date,
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (project.isProcessed)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: const Text('Clean',
                    style: TextStyle(
                        color: AppColors.success,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert,
                  color: AppColors.textMuted, size: 18),
              color: AppColors.bgCard,
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline, color: AppColors.recording, size: 16),
                        SizedBox(width: 8),
                        Text('Delete',
                            style: TextStyle(color: AppColors.recording, fontSize: 13)),
                      ],
                    )),
              ],
              onSelected: (v) { if (v == 'delete') onDelete(); },
            ),
          ],
        ),
      ),
    ).animate(delay: delay).fadeIn().slideX(begin: 0.05, end: 0);
  }
}
