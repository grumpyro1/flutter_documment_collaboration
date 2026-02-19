import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Pdfrx example',
      home: MainPage(),
    );
  }
}

// --- Marker model ---
class Marker {
  final Color color;
  final PdfPageTextRange range;
  String comment; // mutable so we can edit it
  final String selectedText;

  Marker({
    required this.color,
    required this.range,
    required this.comment,
    required this.selectedText,
  });
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  final controller = PdfViewerController();
  final Map<int, List<Marker>> _markers = {};
  List<PdfPageTextRange>? _textSelections;
  bool _isSidebarOpen = false;
  Marker? _hoveredMarker;

  // --- CREATE: Add highlight + comment ---
  Future<void> _onAddHighlight() async {
    if (_textSelections == null || _textSelections!.isEmpty) return;

    final selectedText = await controller.textSelectionDelegate.getSelectedText();

    final comment = await _showCommentDialog(initialComment: '');
    if (comment == null) return;

    for (final selectedRange in _textSelections!) {
      _markers
          .putIfAbsent(selectedRange.pageNumber, () => [])
          .add(Marker(
            color: Colors.yellow,
            range: selectedRange,
            comment: comment,
            selectedText: selectedText,
          ));
    }

    setState(() {});

    if (!_isSidebarOpen) {
      setState(() => _isSidebarOpen = true);
    }
  }

  // --- UPDATE: Edit an existing comment ---
  Future<void> _onEditComment(Marker marker) async {
    final updatedComment = await _showCommentDialog(initialComment: marker.comment);
    if (updatedComment == null) return;

    setState(() {
      marker.comment = updatedComment;
    });
  }

  // --- DELETE: Remove a highlight + comment ---
  void _onDeleteComment(Marker marker) async {
    // Show a simple confirmation first
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete comment?'),
        content: const Text('This will remove the highlight and comment permanently.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _markers[marker.range.pageNumber]?.remove(marker);
      // Clean up empty page entries
      if (_markers[marker.range.pageNumber]?.isEmpty ?? false) {
        _markers.remove(marker.range.pageNumber);
      }
    });
  }

  // --- Reusable comment dialog (used for both Create and Update) ---
  Future<String?> _showCommentDialog({required String initialComment}) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        final textController = TextEditingController(text: initialComment);
        final isEditing = initialComment.isNotEmpty;

        return AlertDialog(
          title: Text(isEditing ? 'Edit comment' : 'Add a comment'),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Type your comment here...',
              border: OutlineInputBorder(),
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, textController.text),
              child: Text(isEditing ? 'Update' : 'Save'),
            ),
          ],
        );
      },
    );
  }

  // --- Draw yellow highlights on PDF ---
  void _paintMarkers(Canvas canvas, Rect pageRect, PdfPage page) {
    final markers = _markers[page.pageNumber];
    if (markers == null) return;

    for (final marker in markers) {
      final paint = Paint()
        ..color = marker.color.withAlpha(120)
        ..style = PaintingStyle.fill;

      canvas.drawRect(
        marker.range.bounds.toRectInDocument(page: page, pageRect: pageRect),
        paint,
      );
    }
  }

  // --- Place comment icons + hover popover on each page ---
  List<Widget> _buildPageOverlays(BuildContext context, Rect pageRect, PdfPage page) {
    final markers = _markers[page.pageNumber];
    if (markers == null) return [];

    return markers.map((marker) {
      final rect = marker.range.bounds.toRectInDocument(page: page, pageRect: pageRect);

      return Positioned(
        left: rect.right + 4,
        top: rect.top,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hoveredMarker = marker),
          onExit: (_) => setState(() => _hoveredMarker = null),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onTap: () => setState(() => _isSidebarOpen = true),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade700,
                    borderRadius: BorderRadius.circular(4),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 4,
                        offset: const Offset(1, 1),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.comment, size: 14, color: Colors.white),
                ),
              ),

              // Hover popover
              if (_hoveredMarker == marker)
                Positioned(
                  left: 24,
                  top: 0,
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 220,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.yellow.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '"${marker.selectedText}"',
                            style: TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (marker.comment.isNotEmpty) ...[
                            const Divider(height: 10),
                            Text(marker.comment, style: const TextStyle(fontSize: 13)),
                          ],
                          const SizedBox(height: 4),
                          Text(
                            'Page ${marker.range.pageNumber}',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // --- Build the right sidebar ---
  Widget _buildSidebar() {
    final allMarkers = _markers.entries
        .expand((entry) => entry.value)
        .toList()
      ..sort((a, b) => a.range.pageNumber.compareTo(b.range.pageNumber));

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
          // Sidebar header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                const Icon(Icons.comment_outlined, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Comments (${allMarkers.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _isSidebarOpen = false),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),

          // Comment cards
          Expanded(
            child: allMarkers.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.comment_outlined, size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                          'No comments yet.\nSelect text and tap 🖊 to add one.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: allMarkers.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => _buildCommentCard(allMarkers[index]),
                  ),
          ),
        ],
      ),
    );
  }

  // --- Individual comment card with Edit + Delete ---
  Widget _buildCommentCard(Marker marker) {
    return GestureDetector(
      onTap: () {
        // Scroll PDF to the highlight
        final rect = controller.calcRectForRectInsidePage(
          pageNumber: marker.range.pageNumber,
          rect: marker.range.bounds,
        );
        controller.ensureVisible(rect);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.yellow.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top row: page badge + edit + delete buttons
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Page ${marker.range.pageNumber}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.yellow.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),

                // Edit button
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade500),
                  tooltip: 'Edit comment',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _onEditComment(marker),
                ),
                const SizedBox(width: 8),

                // Delete button
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300),
                  tooltip: 'Delete comment',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () => _onDeleteComment(marker),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Highlighted text with left yellow border
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.yellow.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border(left: BorderSide(color: Colors.yellow.shade600, width: 3)),
              ),
              child: Text(
                '"${marker.selectedText}"',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),

            // Comment text
            if (marker.comment.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(marker.comment, style: const TextStyle(fontSize: 13)),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'No comment added.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade400, fontStyle: FontStyle.italic),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.border_color),
            tooltip: 'Highlight + Comment',
            onPressed: _onAddHighlight,
          ),
          IconButton(
            icon: Icon(_isSidebarOpen ? Icons.comment : Icons.comment_outlined),
            tooltip: _isSidebarOpen ? 'Hide Comments' : 'Show Comments',
            onPressed: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: PdfViewer.uri(
              
              Uri.parse(
                'https://wybr-edms.s3.ap-southeast-1.amazonaws.com/eab54cd0-6cff-44f4-bd8e-a970abbdcf59.pdf',
              ),
              controller: controller,
              params: PdfViewerParams(

                
                loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
                  return Center(
                    child: CircularProgressIndicator(
                      // totalBytes may not be available on certain case
                      value: totalBytes != null ? bytesDownloaded / totalBytes : null,
                      backgroundColor: Colors.grey,
                    ),
                  );
                },
                textSelectionParams: PdfTextSelectionParams(
                  onTextSelectionChange: (textSelection) async {
                    _textSelections = await textSelection.getSelectedTextRanges();
                  },
                ),
                pagePaintCallbacks: [_paintMarkers],
                pageOverlaysBuilder: (context, pageRect, page) {
                  return _buildPageOverlays(context, pageRect, page);
                },

                viewerOverlayBuilder: (context, size, handleLinkTap) => [
                  PdfViewerScrollThumb(
                    controller: controller,
                    orientation: ScrollbarOrientation.right,
                    thumbSize: const Size(40, 25),
                    thumbBuilder: (context, thumbSize, pageNumber, controller) => Container(
                      color: Colors.black,
                      child: Center(
                        child: Text(pageNumber?.toString() ?? '', style: const TextStyle(color: Colors.white)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Toggleable sidebar
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: _isSidebarOpen ? _buildSidebar() : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}