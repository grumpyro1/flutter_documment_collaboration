import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdfrx/pdfrx.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:url_launcher/url_launcher.dart';
void main() {
  usePathUrlStrategy();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  static final _router = GoRouter(
    routerNeglect: true,
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const MainPage(),
      ),
      GoRoute(
        path: '/share/:token',
        builder: (context, state) {
          final token = state.pathParameters['token']!;
          return ExternalViewerPage(token: token);
        },
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Pdfrx example',
      routerConfig: _router,
    );
  }
}

// --- Marker model ---
// Now includes an id from the database
class Marker {
  final String commentId; // from database
  final Color color;
  final PdfPageTextRange range;
  String comment;
  final String selectedText;
  final double rectLeft;
  final double rectTop;
  final double rectRight;
  final double rectBottom;

  Marker({
    required this.commentId,
    required this.color,
    required this.range,
    required this.comment,
    required this.selectedText,
    required this.rectLeft,
    required this.rectTop,
    required this.rectRight,
    required this.rectBottom,
  });
}

// --- API Service ---
// All calls to FastAPI live here
class CommentApiService {
  static const String baseUrl = 'http://localhost:8000';

  // CREATE
  static Future<Map<String, dynamic>?> createComment({
    required String documentId,
    required String selectedText,
    required String comment,
    required int pageNumber,
    required double rectLeft,
    required double rectTop,
    required double rectRight,
    required double rectBottom,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/comments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'document_id': documentId,
        'selected_text': selectedText,
        'comment': comment,
        'page_number': pageNumber,
        'rect_left': rectLeft,
        'rect_top': rectTop,
        'rect_right': rectRight,
        'rect_bottom': rectBottom,
      }),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return null;
  }

  // CREATE REPLY
  static Future<Map<String, dynamic>?> createReply({
    required String parentCommentId,
    required String documentId,
    required String comment,
    required int pageNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/comments/$parentCommentId/replies'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'document_id': documentId,
        'selected_text': '',
        'comment': comment,
        'page_number': pageNumber,
        'rect_left': 0,
        'rect_top': 0,
        'rect_right': 0,
        'rect_bottom': 0,
      }),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    return null;
  }

  // GET REPLIES
  static Future<List<dynamic>> getReplies(String commentId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/comments/$commentId/replies'),
    );
    if (response.statusCode == 200) return jsonDecode(response.body);
    return [];
  }

  // READ
  static Future<List<dynamic>> getComments(String documentId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/comments/$documentId'),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    }
    return [];
  }

  // UPDATE
  static Future<bool> updateComment(String commentId, String newComment) async {
    final response = await http.put(
      Uri.parse('$baseUrl/comments/$commentId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'comment': newComment}),
    );
    return response.statusCode == 200;
  }

  // DELETE
  static Future<bool> deleteComment(String commentId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/comments/$commentId'),
    );
    return response.statusCode == 200;
  }

  // GENERATE SHARE LINK
static Future<Map<String, dynamic>?> createShareLink(String documentId) async {
  final response = await http.post(
    Uri.parse('$baseUrl/documents/share'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'document_id': documentId}),
  );
  if (response.statusCode == 200) return jsonDecode(response.body);
  return null;
}

// VALIDATE SHARE LINK
static Future<Map<String, dynamic>?> validateShareLink(String token) async {
  final response = await http.get(
    Uri.parse('$baseUrl/share/$token'),
  );
  if (response.statusCode == 200) return jsonDecode(response.body);
  return null;
}
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
  bool _isLoading = false;
  List<Map<String, dynamic>> _loadedComments = [];
  Map<String, List<Map<String, dynamic>>> _replies = {};
  List<dynamic> _rawComments = []; // Raw comments from API (before PDF is ready to map positions)
  // The document ID — in real app this comes from your document list
  // For now we hardcode it to match the S3 URL
  static const String documentId = 'eab54cd0-6cff-44f4-bd8e-a970abbdcf59';

  @override
  void initState() {
    super.initState();
    // Load comments from database when page opens
    _loadComments();
  }

  // --- READ: Load comments from FastAPI on startup ---
  Future<void> _loadComments() async {
    setState(() => _isLoading = true);

    final data = await CommentApiService.getComments(documentId);

    setState(() {
      _rawComments = data;
      _loadedComments = data.map((e) => Map<String, dynamic>.from(e)).toList();
      _isLoading = false;
    });

    await _loadReplies(data); // ADD THIS LINE
  }

  Future<void> _loadReplies(List<dynamic> comments) async {
    for (final comment in comments) {
      final commentId = comment['comment_id'] as String;
      final replies = await CommentApiService.getReplies(commentId);
      if (replies.isNotEmpty) {
        setState(() {
          _replies[commentId] = replies
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        });
      }
    }
  }

  Future<void> _onAddReply(Map<String, dynamic> parentComment) async {
    final comment = await _showCommentDialog(initialComment: '');
    if (comment == null || comment.isEmpty) return;

    final saved = await CommentApiService.createReply(
      parentCommentId: parentComment['comment_id'] as String,
      documentId: documentId,
      comment: comment,
      pageNumber: parentComment['page_number'] as int,
    );

    if (saved != null) {
      await _loadComments(); // refresh everything including replies
    }
  }

  // --- CREATE: Add highlight + comment ---
  Future<void> _onAddHighlight() async {
    if (_textSelections == null || _textSelections!.isEmpty) return;

    final selectedText = await controller.textSelectionDelegate.getSelectedText();
    final comment = await _showCommentDialog(initialComment: '');
    if (comment == null) return;

    for (final selectedRange in _textSelections!) {
      final bounds = selectedRange.bounds;

      // Save to FastAPI
      final saved = await CommentApiService.createComment(
        documentId: documentId,
        selectedText: selectedText,
        comment: comment,
        pageNumber: selectedRange.pageNumber,
        rectLeft: bounds.left,
        rectTop: bounds.top,
        rectRight: bounds.right,
        rectBottom: bounds.bottom,
      );

      if (saved != null) {
        _markers.putIfAbsent(selectedRange.pageNumber, () => []).add(
          Marker(
            commentId: saved['comment_id'],
            color: Colors.yellow,
            range: selectedRange,
            comment: comment,
            selectedText: selectedText,
            rectLeft: bounds.left,
            rectTop: bounds.top,
            rectRight: bounds.right,
            rectBottom: bounds.bottom,
          ),
        );
      }
    }

    await _loadComments(); // refresh sidebar
    if (!_isSidebarOpen) setState(() => _isSidebarOpen = true);
    
  }
  
  // --- Reusable comment dialog ---
  Future<String?> _showCommentDialog({required String initialComment}) {
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

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _onShareDocument() async {
    final result = await CommentApiService.createShareLink(documentId);
    if (result == null) {
      _showError('Failed to generate share link.');
      return;
    }

    final token = result['token'];
    final expiresAt = result['expires_at'];
    final shareUrl = '${Uri.base.origin}/share/$token';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.share, size: 20),
            SizedBox(width: 8),
            Text('Share Document'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Share this link with external viewers:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                shareUrl,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 14, color: Colors.orange),
                const SizedBox(width: 4),
                Text(
                  'Expires: $expiresAt',
                  style: const TextStyle(fontSize: 11, color: Colors.orange),
                ),
              ],
            ),
          ],
        ),
        actions: [
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: shareUrl));
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Link copied!')),
              );
            },
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Link'),
          ),
          // ADD THIS
          FilledButton.icon(
            onPressed: () async {
              Navigator.pop(context);
              final uri = Uri.parse(shareUrl);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open Link'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // --- Draw yellow highlights on PDF ---
  void _paintMarkers(Canvas canvas, Rect pageRect, PdfPage page) {
    final paint = Paint()
      ..color = Colors.yellow.withAlpha(120)
      ..style = PaintingStyle.fill;

    // Draw in-session highlights (from current session)
    final markers = _markers[page.pageNumber];
    if (markers != null) {
      for (final marker in markers) {
        canvas.drawRect(
          marker.range.bounds.toRectInDocument(page: page, pageRect: pageRect),
          paint,
        );
      }
    }

    // Draw loaded highlights (from database)
    for (final raw in _rawComments) {
      if (raw['page_number'] == page.pageNumber) {
        // Convert PDF coordinates to screen coordinates
        final scaleX = pageRect.width / page.width;
        final scaleY = pageRect.height / page.height;

        final rect = Rect.fromLTRB(
          pageRect.left + raw['rect_left'] * scaleX,
          pageRect.top + (page.height - raw['rect_top']) * scaleY,
          pageRect.left + raw['rect_right'] * scaleX,
          pageRect.top + (page.height - raw['rect_bottom']) * scaleY,
        );

        canvas.drawRect(rect, paint);
      }
    }
  }

  // --- Place comment icons + hover popover ---
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
    // Combine in-session markers + loaded comments from database
    final allMarkers = [
      // From current session
      ..._markers.entries.expand((e) => e.value).map((m) => {
        'comment_id': m.commentId,        // changed from 'id' to 'comment_id'
        'page_number': m.range.pageNumber,
        'selected_text': m.selectedText,
        'comment': m.comment,
        'parent_comment_id': null, // main comments have no parent
        'rect_left': m.rectLeft,   // add rect coords for navigation
        'rect_top': m.rectTop,
        'rect_right': m.rectRight,
        'rect_bottom': m.rectBottom,
        'marker': m,
      }),
      // From database (not in current session)
      ..._loadedComments.where((raw) =>
        !_markers.values.expand((e) => e).any((m) => m.commentId == raw['comment_id']),
      ),
    ]..sort((a, b) => (a['page_number'] as int).compareTo(b['page_number'] as int));

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
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

  // --- Individual comment card ---
  Widget _buildCommentCard(Map<String, dynamic> item) {
    final marker = item['marker'] as Marker?;

    return GestureDetector(
      onTap: () {
          final pageNumber = item['page_number'] as int;
          final rectLeft = (item['rect_left'] ?? 0.0) as double;
          final rectTop = (item['rect_top'] ?? 0.0) as double;
          final rectRight = (item['rect_right'] ?? 0.0) as double;
          final rectBottom = (item['rect_bottom'] ?? 0.0) as double;

          final rect = controller.calcRectForRectInsidePage(
            pageNumber: pageNumber,
            rect: PdfRect(rectLeft, rectTop, rectRight, rectBottom),
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
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.yellow.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Page ${item['page_number']}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.yellow.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(Icons.edit_outlined, size: 16, color: Colors.grey.shade500),
                  tooltip: 'Edit comment',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
                    final updatedComment = await _showCommentDialog(
                      initialComment: item['comment'] as String,
                    );
                    if (updatedComment == null) return;

                    final success = await CommentApiService.updateComment(
                      item['comment_id'] as String,
                      updatedComment,
                    );
                    if (success) {
                      setState(() {
                        item['comment'] = updatedComment;
                        if (marker != null) marker.comment = updatedComment;
                      });
                    }
                  },
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300),
                  tooltip: 'Delete comment',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () async {
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

                    final commentId = item['comment_id'] as String;
                    final success = await CommentApiService.deleteComment(commentId);
                    if (success) {
                      if (marker != null) {
                        setState(() => _markers[marker.range.pageNumber]?.remove(marker));
                      }
                      await _loadComments(); // refresh everything
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.yellow.shade50,
                borderRadius: BorderRadius.circular(4),
                border: Border(left: BorderSide(color: Colors.yellow.shade600, width: 3)),
              ),
              child: Text(
                '"${item['selected_text']}"',
                style: TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 12,
                  color: Colors.grey.shade700,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if ((item['comment'] as String).isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(item['comment'], style: const TextStyle(fontSize: 13)),
            ],

            // Show existing replies
            if (_replies[item['comment_id']] != null)
              ..._replies[item['comment_id']]!
                  .map((r) => _buildReplyCard(r))
                  .toList(),

            // Reply button
            if (item['parent_comment_id'] == null)
              TextButton.icon(
                onPressed: () => _onAddReply(item),
                icon: Icon(Icons.reply, size: 14, color: Colors.grey.shade500),
                label: Text(
                  'Reply',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReplyCard(Map<String, dynamic> reply) {
    return Container(
      margin: const EdgeInsets.only(left: 16, top: 6),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.grey.shade400),
              const SizedBox(width: 4),
              Text(
                'Reply',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // Edit reply
              IconButton(
                icon: Icon(Icons.edit_outlined, size: 14, color: Colors.grey.shade400),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () async {
                  final updated = await _showCommentDialog(
                    initialComment: reply['comment'] as String,
                  );
                  if (updated == null) return;
                  final success = await CommentApiService.updateComment(
                    reply['comment_id'] as String,
                    updated,
                  );
                  if (success) setState(() => reply['comment'] = updated);
                },
              ),
              const SizedBox(width: 6),
              // Delete reply
              IconButton(
                icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade200),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('Delete reply?'),
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
                  final success = await CommentApiService.deleteComment(
                    reply['comment_id'] as String,
                  );
                  if (success) {
                    setState(() {
                      final parentId = reply['parent_comment_id'] as String;
                      _replies[parentId]?.remove(reply);
                    });
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(reply['comment'] as String, style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Viewer'),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            // IconButton(
            //   icon: const Icon(Icons.open_in_new),
            //   tooltip: 'Test External Viewer',
            //   onPressed: () async {
            //     final uri = Uri.parse('/share/eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJkb2N1bWVudF9pZCI6ImVhYjU0Y2QwLTZjZmYtNDRmNC1iZDhlLWE5NzBhYmJkY2Y1OSIsImV4cCI6MTc3MTcwMTcxM30.jEmRFDgT-f7xd9meV36TwEz4KQ93U01ZwY8HqKUnAIk');
            //     await launchUrl(uri, mode: LaunchMode.externalApplication);
            //   },
            // ),
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
            IconButton(
              icon: const Icon(Icons.share),
              tooltip: 'Share Document',
              onPressed: _onShareDocument,
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


// --- External Viewer Page (read only for shared links) ---
class ExternalViewerPage extends StatefulWidget {
  final String token;
  const ExternalViewerPage({super.key, required this.token});

  @override
  State<ExternalViewerPage> createState() => _ExternalViewerPageState();
}

class _ExternalViewerPageState extends State<ExternalViewerPage> {
  bool _isLoading = true;
  bool _isExpired = false;
  String? _documentId;
  List<dynamic> _rawComments = [];
  Map<String, List<Map<String, dynamic>>> _replies = {};
  bool _isSidebarOpen = false;

  @override
  void initState() {
    super.initState();
    _validateLink();
  }

  Future<void> _validateLink() async {
    final result = await CommentApiService.validateShareLink(widget.token);
    if (result == null) {
      setState(() {
        _isLoading = false;
        _isExpired = true;
      });
      return;
    }

    final docId = result['document_id'] as String;
    final comments = await CommentApiService.getComments(docId);

    // Load replies for each comment
    final repliesMap = <String, List<Map<String, dynamic>>>{};
    for (final comment in comments) {
      final commentId = comment['comment_id'] as String;
      final replies = await CommentApiService.getReplies(commentId);
      if (replies.isNotEmpty) {
        repliesMap[commentId] = replies
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
      }
    }

    setState(() {
      _documentId = docId;
      _rawComments = comments;
      _replies = repliesMap;
      _isLoading = false;
    });
  }

  // Draw highlights on PDF (read only)
  void _paintMarkers(Canvas canvas, Rect pageRect, PdfPage page) {
    final paint = Paint()
      ..color = Colors.yellow.withAlpha(120)
      ..style = PaintingStyle.fill;

    for (final raw in _rawComments) {
      if (raw['page_number'] == page.pageNumber) {
        final scaleX = pageRect.width / page.width;
        final scaleY = pageRect.height / page.height;

        final rect = Rect.fromLTRB(
          pageRect.left + raw['rect_left'] * scaleX,
          pageRect.top + (page.height - raw['rect_top']) * scaleY,
          pageRect.left + raw['rect_right'] * scaleX,
          pageRect.top + (page.height - raw['rect_bottom']) * scaleY,
        );

        canvas.drawRect(rect, paint);
      }
    }
  }

  // Read only sidebar
  Widget _buildSidebar() {
    final allComments = _rawComments
        .map((e) => Map<String, dynamic>.from(e))
        .toList()
      ..sort((a, b) => (a['page_number'] as int).compareTo(b['page_number'] as int));

    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(left: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        children: [
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
                  'Comments (${allComments.length})',
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
          Expanded(
            child: allComments.isEmpty
                ? Center(
                    child: Text(
                      'No comments yet.',
                      style: TextStyle(color: Colors.grey.shade400),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: allComments.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final item = allComments[index];
                      return _buildReadOnlyCard(item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // Read only comment card — no edit/delete/reply buttons
  Widget _buildReadOnlyCard(Map<String, dynamic> item) {
    final commentId = item['comment_id'] as String;
    final itemReplies = _replies[commentId] ?? [];

    return Container(
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.yellow.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'Page ${item['page_number']}',
              style: TextStyle(
                fontSize: 11,
                color: Colors.yellow.shade800,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.yellow.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border(left: BorderSide(color: Colors.yellow.shade600, width: 3)),
            ),
            child: Text(
              '"${item['selected_text']}"',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if ((item['comment'] as String).isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(item['comment'], style: const TextStyle(fontSize: 13)),
          ],
          // Show replies read only
          ...itemReplies.map((reply) => Container(
            margin: const EdgeInsets.only(left: 16, top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.subdirectory_arrow_right, size: 14, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    reply['comment'] as String,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_isExpired || _documentId == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              const Text(
                'This link has expired',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Please request a new link from the document owner.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Document Viewer'),
        actions: [
          // View Only badge
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                Icon(Icons.visibility, size: 14, color: Colors.orange.shade800),
                const SizedBox(width: 4),
                Text(
                  'View Only',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade800,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Toggle comments sidebar
          IconButton(
            icon: Icon(_isSidebarOpen ? Icons.comment : Icons.comment_outlined),
            tooltip: 'Comments',
            onPressed: () => setState(() => _isSidebarOpen = !_isSidebarOpen),
          ),
        ],
      ),
      body: Row(
        children: [
          Expanded(
            child: PdfViewer.uri(
              Uri.parse(
                'https://wybr-edms.s3.ap-southeast-1.amazonaws.com/$_documentId.pdf',
              ),
              params: PdfViewerParams(
                loadingBannerBuilder: (context, bytesDownloaded, totalBytes) {
                  return Center(
                    child: CircularProgressIndicator(
                      value: totalBytes != null ? bytesDownloaded / totalBytes : null,
                    ),
                  );
                },
                pagePaintCallbacks: [_paintMarkers],
              ),
            ),
          ),
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