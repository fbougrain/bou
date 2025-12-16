import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/media_item.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';
import '../widgets/plain_dropdown.dart';
import '../data/mappers.dart';
import '../models/project.dart';
import '../data/media_repository.dart';

const TextStyle _ddTextStyle = TextStyle(color: Colors.white, fontSize: 14.5);

class MediaPage extends StatefulWidget {
  const MediaPage({super.key, required this.project});
  final Project project;

  @override
  State<MediaPage> createState() => _MediaPageState();
}

class _MediaPageState extends State<MediaPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchCtrl = TextEditingController();
  MediaType? _filterType; // null = All
  String _sort = 'recent'; // 'recent' | 'oldest'

  late final AnimationController _fadeCtrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOutCubic);
    WidgetsBinding.instance.addPostFrameCallback((_) => _fadeCtrl.forward());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  Widget _buildMediaScaffold(List<MediaItem> items) {
    final filtered = _applyFilters(items);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            const Text(
              'Media',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            _SearchBar(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              onCancel: () => setState(() {}),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _TypeDropdown(
                    value: _filterType,
                    onChanged: (val) => setState(() => _filterType = val),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _SortDropdown(
                    value: _sort,
                    onChanged: (val) => setState(() => _sort = val),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: filtered.isEmpty
                  ? const _EmptyState()
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, i) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final m = filtered[i];
                        return Container(
                          decoration: BoxDecoration(
                            color: surfaceDark,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: borderDark, width: 1.1),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF2A313B),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: borderDark),
                                ),
                                alignment: Alignment.center,
                                clipBehavior: Clip.antiAlias,
                                child: _thumbnail(m),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      m.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _meta(m),
                                      style: const TextStyle(
                                        color: Colors.white60,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('projects')
            .doc(widget.project.id)
            .collection('media')
            .orderBy('date', descending: true)
            .snapshots(includeMetadataChanges: true),
        builder: (context, snapshot) {
          if (snapshot.hasData) {
            final items = snapshot.data!.docs
                .map((d) => MediaItemFirestore.fromMap(d.id, d.data()))
                .toList();
            return _buildMediaScaffold(items);
          }
          // Fallback to repository for demo/offline
          final repoItems = MediaRepository.instance.itemsFor(widget.project.id);
          if (repoItems.isNotEmpty) {
            return _buildMediaScaffold(repoItems);
          }
          // Show loading indicator if no data yet
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const _MediaLoadingIndicator();
          }
          return _buildMediaScaffold([]);
        },
      ),
    );
  }

  List<MediaItem> _applyFilters(List<MediaItem> items) {
    String q = _searchCtrl.text.trim().toLowerCase();
    Iterable<MediaItem> x = items;
    if (_filterType != null) {
      x = x.where((e) => e.type == _filterType);
    }
    if (q.isNotEmpty) {
      x = x.where((e) => e.name.toLowerCase().contains(q));
    }
    final list = x.toList();
    list.sort(
      (a, b) => _sort == 'recent'
          ? b.date.compareTo(a.date)
          : a.date.compareTo(b.date),
    );
    return list;
  }

  IconData _iconFor(MediaType t) {
    switch (t) {
      case MediaType.photo:
        return AppIcons.folderOpen; // fallback icon (adjust when specific icon available)
      case MediaType.video:
        return AppIcons.folderOpen; // fallback
      case MediaType.document:
        return AppIcons.file;
    }
  }

  String _meta(MediaItem m) =>
      '${m.uploader} • ${m.date.year}-${m.date.month.toString().padLeft(2, '0')}-${m.date.day.toString().padLeft(2, '0')}';

  Widget _thumbnail(MediaItem m) {
    if (m.thumbnailUrl == null || m.thumbnailUrl!.isEmpty) {
      return Icon(_iconFor(m.type), color: Colors.white70, size: 20);
    }
    return Image.network(
      m.thumbnailUrl!,
      width: 44,
      height: 44,
      fit: BoxFit.cover,
      // Gracefully handle invalid image data or network failures.
      errorBuilder: (context, error, stack) => Icon(
        _iconFor(m.type),
        color: Colors.white70,
        size: 20,
      ),
      // Avoid flashing on desktop slow connections.
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) return child;
        return Icon(_iconFor(m.type), color: Colors.white70, size: 20);
      },
    );
  }
}

class _SearchBar extends StatefulWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    this.onCancel,
  });
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback? onCancel;

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surfaceDark,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderDark, width: 1.1),
      ),
      padding: const EdgeInsets.only(left: 12, right: 8),
      height: 44,
      child: Row(
        children: [
          const Icon(AppIcons.search, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              onSubmitted: widget.onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14.5),
              decoration: const InputDecoration(
                hintText: 'Search',
                hintStyle: TextStyle(color: Colors.white54),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TypeDropdown extends StatelessWidget {
  const _TypeDropdown({required this.value, required this.onChanged});
  final MediaType? value;
  final ValueChanged<MediaType?> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: PlainDropdown<MediaType?>(
        value: value,
        items: const [
          DropdownMenuItem(
            value: null,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Text('All', style: _ddTextStyle),
            ),
          ),
          DropdownMenuItem(
            value: MediaType.photo,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Text('Photos & Videos', style: _ddTextStyle),
            ),
          ),
          DropdownMenuItem(
            value: MediaType.document,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Text('Documents', style: _ddTextStyle),
            ),
          ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  const _SortDropdown({required this.value, required this.onChanged});
  final String value; // 'recent' | 'oldest'
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: PlainDropdown<String>(
        value: value,
        items: const [
          DropdownMenuItem(
            value: 'recent',
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Text('Recent', style: _ddTextStyle),
            ),
          ),
          DropdownMenuItem(
            value: 'oldest',
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Text('Oldest', style: _ddTextStyle),
            ),
          ),
        ],
        onChanged: (v) {
          if (v != null) onChanged(v);
        },
      ),
    );
  }
}

// moved plain dropdown to widgets/plain_dropdown.dart

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          SizedBox(height: 20),
          Icon(AppIcons.folderOpen, size: 56, color: Colors.white60),
          SizedBox(height: 10),
          Text(
            'No media',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: 6),
          Text(
            'You currently have no media yet.',
            style: TextStyle(color: Colors.white60, fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _MediaLoadingIndicator extends StatelessWidget {
  const _MediaLoadingIndicator();
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 2.8),
        ),
      ),
    );
  }
}
