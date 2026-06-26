import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class LegalScreen extends StatefulWidget {
  final String title;
  final String assetPath;

  const LegalScreen({super.key, required this.title, required this.assetPath});

  @override
  State<LegalScreen> createState() => _LegalScreenState();
}

class _LegalScreenState extends State<LegalScreen> {
  late Future<String> _future;

  @override
  void initState() {
    super.initState();
    _future = rootBundle.loadString(widget.assetPath);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrim,
          ),
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrim),
      ),
      body: FutureBuilder<String>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.textPrim,
              ),
            );
          }
          if (snap.hasError || !snap.hasData) {
            return const Center(
              child: Text(
                'Could not load document.',
                style: TextStyle(color: AppColors.textSec),
              ),
            );
          }
          return _MarkdownBody(text: snap.data!);
        },
      ),
    );
  }
}

class _MarkdownBody extends StatelessWidget {
  final String text;
  const _MarkdownBody({required this.text});

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      itemCount: lines.length,
      itemBuilder: (_, i) => _renderLine(lines[i]),
    );
  }

  Widget _renderLine(String line) {
    if (line.startsWith('# ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 8),
        child: Text(
          line.substring(2),
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrim,
          ),
        ),
      );
    }
    if (line.startsWith('## ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Text(
          line.substring(3),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrim,
          ),
        ),
      );
    }
    if (line.startsWith('### ')) {
      return Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 4),
        child: Text(
          line.substring(4),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.textPrim,
          ),
        ),
      );
    }
    if (line.startsWith('---')) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Divider(color: AppColors.border, thickness: 0.5),
      );
    }
    if (line.startsWith('> ')) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: _richText(line.substring(2), 12, AppColors.textSec),
      );
    }
    if (line.startsWith('- ')) {
      return Padding(
        padding: const EdgeInsets.only(left: 8, top: 3, bottom: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('• ', style: TextStyle(fontSize: 13, color: AppColors.textSec)),
            Expanded(child: _richText(line.substring(2), 13, AppColors.textSec)),
          ],
        ),
      );
    }
    if (line.startsWith('_') && line.endsWith('_')) {
      return Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Text(
          line.substring(1, line.length - 1),
          style: const TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: AppColors.textDim,
          ),
        ),
      );
    }
    if (line.trim().isEmpty) {
      return const SizedBox(height: 6);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: _richText(line, 13, AppColors.textSec),
    );
  }

  Widget _richText(String raw, double size, Color defaultColor) {
    // Strip simple markdown bold markers (**text**) for inline bold
    final spans = <TextSpan>[];
    final boldPattern = RegExp(r'\*\*(.+?)\*\*');
    int last = 0;
    for (final m in boldPattern.allMatches(raw)) {
      if (m.start > last) {
        spans.add(TextSpan(text: _stripInline(raw.substring(last, m.start))));
      }
      spans.add(TextSpan(
        text: m.group(1),
        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textPrim),
      ));
      last = m.end;
    }
    if (last < raw.length) {
      spans.add(TextSpan(text: _stripInline(raw.substring(last))));
    }
    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: size, color: defaultColor, height: 1.55),
        children: spans,
      ),
    );
  }

  String _stripInline(String s) =>
      s.replaceAll(RegExp(r'`([^`]+)`'), r'\1').replaceAll(RegExp(r'_([^_]+)_'), r'\1');
}
