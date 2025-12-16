import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';
import '../models/chat_message.dart';
import '../data/profile_repository.dart';
import '../widgets/overlay_notice.dart';
import '../data/report_repository.dart';
import '../models/report.dart';

class ChatThreadView extends StatelessWidget {
  const ChatThreadView({
    super.key,
    required this.messages,
    this.onSend,
    this.onSendMessage,
    this.otherAvatarAsset,
    this.avatarsByName,
    this.currentUserHandle,
    this.additionalHandles = const [],
    this.participants = const [],
    this.projectId,
    this.threadId,
  });

  final List<ChatMessage> messages;
  final ValueChanged<String>? onSend;
  // New richer callback (preferred) providing full ChatMessage including attachments / metadata.
  final ValueChanged<ChatMessage>? onSendMessage;
  final String? otherAvatarAsset;
  // Optional map of sender display name -> avatar asset path. Used primarily for team chats to show per-sender avatars.
  final Map<String, String?>? avatarsByName;
  final String? currentUserHandle; // e.g. '@omar' or 'omar'
  final List<String> additionalHandles; // any extra aliases/handles
  final List<String> participants; // conversation members' display names
  final String? projectId; // Project ID for reporting
  final String? threadId; // Thread ID for reporting

  @override
  Widget build(BuildContext context) {
    return _ChatThreadBody(
      messages: messages,
      onSend: onSend,
      onSendMessage: onSendMessage,
      otherAvatarAsset: otherAvatarAsset,
      avatarsByName: avatarsByName,
      currentUserHandle: currentUserHandle,
      additionalHandles: additionalHandles,
      participants: participants,
      projectId: projectId,
      threadId: threadId,
    );
  }
}

class _ChatThreadBody extends StatefulWidget {
  const _ChatThreadBody({
    required this.messages,
    this.onSend,
    this.onSendMessage,
    this.otherAvatarAsset,
    this.avatarsByName,
    this.currentUserHandle,
    this.additionalHandles = const [],
    this.participants = const [],
    this.projectId,
    this.threadId,
  });
  final List<ChatMessage> messages;
  final ValueChanged<String>? onSend;
  final ValueChanged<ChatMessage>? onSendMessage;
  final String? otherAvatarAsset;
  final Map<String, String?>? avatarsByName;
  final String? currentUserHandle;
  final List<String> additionalHandles;
  final List<String> participants;
  final String? projectId;
  final String? threadId;

  @override
  State<_ChatThreadBody> createState() => _ChatThreadBodyState();
}

class _ChatThreadBodyState extends State<_ChatThreadBody> {
  // Swappable controller (cannot be final because we replace it to achieve instant-bottom state).
  late ScrollController _scroll;
  static const bool _reversedMode =
      true; // Use reversed list so offset 0 == newest at visual bottom.
  final TextEditingController _input = TextEditingController();
  final TextEditingController _search = TextEditingController();
  bool _hasText = false;
  String _activeFilter = 'all'; // all | mentions | media
  bool _showSearch = false;
  String? _mentionFragment; // current fragment after '@'
  List<_MentionCandidate> _mentionMatches = [];
  bool get _showMentionPanel =>
      _mentionFragment != null && _mentionMatches.isNotEmpty;
  late final List<String> _myMentionTokens; // built in initState
  final GlobalKey _inputBarKey = GlobalKey();
  double _inputBarHeight = 0; // measured height of input bar for bottom padding
  bool _showJumpToBottom =
      false; // shows chevron when user scrolls away from latest
  bool _jumpingToBottom = false; // prevent overlapping jump animations
  bool _forceHideJump =
      false; // suppress chevron immediately after filter/search switch until user scrolls
  // Pending attachment (selected but not yet sent)
  String? _pendingAttachmentType;
  String? _pendingAttachmentLabel;

  @override
  void initState() {
    super.initState();
    _scroll = ScrollController();
    _scroll.addListener(_scrollListener);
    _forceHideJump = true; // start with chevron hidden until user scrolls up
    // Build mention tokens from provided handles (we intentionally DO NOT include a generic 'me' alias)
    // Rationale: Users should @ the actual handle (e.g. @omar) or any explicit additional alias supplied.
    final tokens = <String>{};
    void addHandle(String? h) {
      if (h == null) return;
      final trimmed = h.trim();
      if (trimmed.isEmpty) return;
      final core = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
      if (core.isNotEmpty) tokens.add(core.toLowerCase());
    }

    addHandle(widget.currentUserHandle);
    for (final extra in widget.additionalHandles) {
      addHandle(extra);
    }
    _myMentionTokens = tokens.toList(growable: false);
    _input.addListener(() {
      final next = _input.text.trim().isNotEmpty;
      if (next != _hasText) {
        setState(() => _hasText = next);
      }
      _updateMentionState();
    });

    // After first frame, ensure we start scrolled to the bottom (latest messages visible)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scroll.hasClients) {
        if (_reversedMode) {
          if (_scroll.position.pixels != 0) {
            _scroll.jumpTo(0);
          }
        } else {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      }
      _measureInputBar();
      // Extra stabilization to ensure we are truly at the bottom even if late layout shifts content.
      if (_reversedMode) {
        int attempts = 0;
        void stabilizeRev(Duration _) {
          if (!mounted || !_scroll.hasClients) return;
          if (_scroll.position.pixels != 0) {
            _scroll.jumpTo(0);
          }
          attempts++;
          if (attempts < 2) {
            WidgetsBinding.instance.addPostFrameCallback(stabilizeRev);
          }
        }

        WidgetsBinding.instance.addPostFrameCallback(stabilizeRev);
      } else {
        int attempts = 0;
        void stabilize(Duration _) {
          if (!mounted || !_scroll.hasClients) return;
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
          attempts++;
          if (attempts < 2) {
            WidgetsBinding.instance.addPostFrameCallback(stabilize);
          }
        }

        WidgetsBinding.instance.addPostFrameCallback(stabilize);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    _search.dispose();
    super.dispose();
  }

  void _scrollListener() {
    // Called after first frame/any scroll; toggles chevron visibility.
    if (!_scroll.hasClients) return;
    final atBottom = _isAtBottom();
    if (_forceHideJump) {
      if (!atBottom) {
        // User scrolled up; allow showing button from now on.
        setState(() {
          _forceHideJump = false;
          _showJumpToBottom = true;
        });
      } else {
        if (_showJumpToBottom) {
          setState(() {
            _showJumpToBottom = false;
          });
        }
      }
      return;
    }
    final show = !atBottom;
    if (show != _showJumpToBottom) {
      setState(() => _showJumpToBottom = show);
    }
  }

  // Controller swap helper no longer required in reversed mode (newest pinned at visual bottom).

  void _updateMentionState() {
    final text = _input.text;
    final sel = _input.selection.baseOffset;
    if (sel <= 0 || sel > text.length) {
      if (_mentionFragment != null) setState(() => _mentionFragment = null);
      return;
    }
    // Look back from cursor to find an '@' that starts a mention (start or preceded by space)
    final prefix = text.substring(0, sel);
    final match = RegExp(r'(?:^|\s)@(\w{0,32})$').firstMatch(prefix);
    if (match == null) {
      if (_mentionFragment != null) setState(() => _mentionFragment = null);
      return;
    }
    final frag = match.group(1)!; // may be empty
    // Helper: build a token from a display name (first word, alnum/_ only)
    String tokenFrom(String n) {
      final first = n.split(RegExp(r'\s+')).first;
      return first.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    }

    // Build canonical map token -> display, preferring participant display names over ad-hoc sender names.
    final Map<String, String> byToken = {};
    for (final p in widget.participants) {
      final n = p.trim();
      if (n.isEmpty || n == 'Me' || n == 'System') continue;
      final t = tokenFrom(n);
      if (t.isEmpty) continue;
      byToken.putIfAbsent(t.toLowerCase(), () => n);
    }
    for (final m in widget.messages) {
      final n = (m.senderName ?? '').trim();
      if (n.isEmpty || n == 'Me' || n == 'System') continue;
      final t = tokenFrom(n);
      if (t.isEmpty) continue;
      byToken.putIfAbsent(t.toLowerCase(), () => n);
    }
    final fragLower = frag.toLowerCase();
    final entries =
        byToken.entries.where((e) => e.key.startsWith(fragLower)).toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    final filtered = entries
        .map((e) => _MentionCandidate(display: e.value, token: e.key))
        .toList();
    setState(() {
      _mentionFragment = frag;
      _mentionMatches = filtered.take(8).toList();
      if (_mentionMatches.isEmpty) _mentionFragment = null;
    });
  }

  bool _isAtBottom([double threshold = 96]) {
    if (!_scroll.hasClients) return true;
    if (_reversedMode) {
      // In reversed mode, offset 0 is visual bottom.
      return _scroll.position.pixels <= 2; // small tolerance
    }
    final pos = _scroll.position;
    final dynThreshold = _inputBarHeight > 0 ? _inputBarHeight + 8 : threshold;
    return pos.pixels >= (pos.maxScrollExtent - dynThreshold);
  }

  void _measureInputBar() {
    final ctx = _inputBarKey.currentContext;
    if (ctx == null) return;
    final h = ctx.size?.height ?? 0;
    if (h > 0 && (h - _inputBarHeight).abs() > 1) {
      setState(() => _inputBarHeight = h);
    }
  }

  void _resetScrollControllerToBottom() {
    // Dispose existing controller and create a fresh one anchored at bottom (offset 0 in reversed mode).
    _scroll.removeListener(_scrollListener);
    try {
      _scroll.dispose();
    } catch (_) {}
    _scroll = ScrollController();
    _scroll.addListener(_scrollListener);
    _showJumpToBottom =
        false; // internal state (will be reflected on next build when we call setState)
    // Ensure on the very next frame we are at the newest position deterministically.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (_reversedMode) {
        if (_scroll.position.pixels != 0) {
          _scroll.jumpTo(0);
        }
      } else {
        final max = _scroll.position.maxScrollExtent;
        if ((_scroll.position.pixels - max).abs() > 1) {
          _scroll.jumpTo(max);
        }
      }
    });
  }
  // Removed legacy schedule/stabilize helpers. Instant anchoring handled by controller swap.

  void _setFilter(String value) {
    if (value == _activeFilter) return;
    _resetScrollControllerToBottom();
    setState(() {
      _activeFilter = value;
      _forceHideJump = true;
      _showJumpToBottom = false;
    });
  }

  void _toggleSearch(bool show) {
    _resetScrollControllerToBottom();
    setState(() {
      _showSearch = show;
      if (!show) _search.clear();
      _forceHideJump = true;
      _showJumpToBottom = false;
    });
  }

  bool _isMentioningMe(String text) {
    // Extract @tokens and compare to our mention tokens (case-insensitive)
    final regex = RegExp(r'@([A-Za-z0-9_]+)');
    for (final m in regex.allMatches(text)) {
      final token = m.group(1)!.toLowerCase();
      if (_myMentionTokens.contains(token)) return true;
    }
    return false;
  }

  void _insertMention(_MentionCandidate c) {
    final text = _input.text;
    final sel = _input.selection.baseOffset;
    if (sel < 0) return;
    final prefix = text.substring(0, sel);
    final match = RegExp(r'(?:^|\s)@(\w{0,32})$').firstMatch(prefix);
    if (match == null) return;
    final atIndex = prefix.lastIndexOf('@');
    if (atIndex < 0) return;
    final newText =
        '${text.substring(0, atIndex)}@${c.token} ${text.substring(sel)}';
    final caret = atIndex + 1 + c.token.length + 1; // int caret position
    setState(() {
      _input.text = newText;
      _input.selection = TextSelection.collapsed(offset: caret);
      _mentionFragment = null;
      _mentionMatches = [];
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty && _pendingAttachmentType == null) return;

    // Build ChatMessage if richer callback provided.
    if (widget.onSendMessage != null) {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      // Use actual sender name from profile, not "Me" (display logic will show "Me" when isMe: true)
      final profile = ProfileRepository.instance.profile;
      final senderName = profile.name.isNotEmpty ? profile.name : (currentUid?.substring(0, 6) ?? 'User');
      final msg = ChatMessage(
        text: text,
        isMe: true,
        senderName: senderName,
        senderUid: currentUid,
        time: DateTime.now(),
        attachmentType: _pendingAttachmentType,
        attachmentLabel: _pendingAttachmentLabel,
      );
      widget.onSendMessage!(msg);
    } else {
      // Legacy fallback: encode attachment in text sentinel if attachment chosen.
      if (widget.onSend != null) {
        final payload = _pendingAttachmentType != null
            ? '[attachment:${_pendingAttachmentType!}:${_pendingAttachmentLabel ?? _pendingAttachmentType!}] ${text.isNotEmpty ? text : ''}'
                  .trim()
            : text;
        widget.onSend!(payload);
      }
    }
    _input.clear();
    setState(() {
      _pendingAttachmentType = null;
      _pendingAttachmentLabel = null;
    });
    if (_reversedMode) {
      // In reversed mode bottom == offset 0. If user was browsing older messages, snap back.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scroll.hasClients) return;
        if (!_isAtBottom()) {
          // Animate to provide context that we returned to latest.
          _scroll
              .animateTo(
                0,
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
              )
              .catchError((_) {});
        }
      });
    } else {
      _scrollToBottomAfterSend();
    }
  }


  // Ensures we actually land on the very last message even if new layout frames extend
  // maxScrollExtent after the initial scroll (common when the list rebuild + keyboard insets shift).
  void _scrollToBottomAfterSend() {
    // We do a short sequence: animate -> wait a frame -> if new content pushed maxScrollExtent further, animate again.
    // Final guarantee: jump if still a few pixels off (e.g., due to late layout of images or attachment chips).
    if (_reversedMode) return; // not needed; newest already visible
    if (!mounted || !_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    _scroll
        .animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        )
        .catchError((_) {});
  }

  // Robust jump-to-bottom invoked by the floating chevron button. Tries multiple frames
  // to compensate for late layout (e.g., images, attachment chips) so a single tap
  // reliably lands exactly at the latest message.
  void _jumpToBottom() {
    if (!_scroll.hasClients || _jumpingToBottom) return;
    if (_reversedMode) {
      // In reversed mode bottom == offset 0.
      _scroll.animateTo(
        0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _jumpingToBottom = true;
    try {
      if (!mounted || !_scroll.hasClients) return;
      _scroll
          .animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted) {
              setState(() {
                _jumpingToBottom = false;
                _showJumpToBottom = !_isAtBottom();
              });
            }
          });
    } catch (_) {
      if (mounted) {
        setState(() {
          _jumpingToBottom = false;
          _showJumpToBottom = !_isAtBottom();
        });
      }
    }
  }

  String _fmtTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  String _fmtDate(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final date = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(date).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    // Short date dd MMM
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month - 1]}';
  }

  String? _resolveAvatarFor(String? senderName) {
    if (senderName == null ||
        senderName.isEmpty ||
        senderName == 'Me' ||
        senderName == 'System') {
      return widget.otherAvatarAsset;
    }
    final map = widget.avatarsByName;
    if (map != null) {
      final found = map[senderName];
      if (found != null && found.isNotEmpty) return found;
    }
    return widget.otherAvatarAsset;
  }

  Future<void> _showReportDialog(BuildContext context, ChatMessage message) async {
    if (widget.projectId == null) return;
    
    final reasonController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'report dialog',
      barrierColor: Colors.black.withValues(alpha: 0.5),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim, secondary) {
        return Dialog(
          backgroundColor: surfaceDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: borderDark),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        AppIcons.report,
                        color: Colors.red,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Text(
                        'Report Message',
                        style: TextStyle(
                          color: Colors.red,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: reasonController,
                    maxLines: 4,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Why are you reporting this message?',
                      hintStyle: const TextStyle(color: Colors.white38),
                      filled: true,
                      fillColor: surfaceDarker,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderDark),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: borderDark),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: accentTech),
                      ),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please provide a reason';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: newaccentbackground,
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: newaccent.withValues(alpha: 0.95),
                          width: 1.6,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      onPressed: () async {
                        if (formKey.currentState!.validate()) {
                          Navigator.pop(context);
                          await _submitReport(message, reasonController.text.trim());
                        }
                      },
                      child: const Text(
                        'Submit Report',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _submitReport(ChatMessage message, String reason) async {
    if (widget.projectId == null) return;
    
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) return;
      
      final profile = ProfileRepository.instance.profile;
      final reporterName = profile.name.isNotEmpty ? profile.name : currentUser.uid.substring(0, 6);
      
      // Use the actual Firestore document ID if available, otherwise generate one
      final messageId = message.id ?? (message.time != null 
          ? '${message.time!.millisecondsSinceEpoch}_${message.text.hashCode}'
          : null);
      
      final report = Report(
        id: '', // Will be set by repository
        projectId: widget.projectId!,
        reporterUid: currentUser.uid,
        reporterName: reporterName,
        reportedUserUid: message.senderUid,
        reportedUserName: message.senderName,
        messageId: messageId,
        messageText: message.text,
        reason: reason,
        createdAt: DateTime.now(),
        threadId: widget.threadId,
      );
      
      await ReportRepository.instance.submitReport(report);
      
      if (mounted) {
        showOverlayNotice(context, 'Report submitted successfully');
      }
    } catch (e) {
      if (mounted) {
        showOverlayNotice(context, 'Failed to submit report');
      }
    }
  }

  Widget _highlighted(
    String text,
    String query,
    TextStyle base, {
    bool isOnSentBubble = false,
  }) {
    if (query.isEmpty) return Text(text, style: base);
    final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
    final matches = pattern.allMatches(text);
    if (matches.isEmpty) return Text(text, style: base);
    int last = 0;
    final spans = <InlineSpan>[];
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final matched = text.substring(m.start, m.end);
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
            decoration: BoxDecoration(
              color: isOnSentBubble
                  ? Colors.white.withValues(
                      alpha: 0.28,
                    ) // light overlay for blue bubble
                  : accentTech.withValues(
                      alpha: 0.30,
                    ), // existing accent overlay for received
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(matched, style: base.copyWith(color: Colors.white)),
          ),
        ),
      );
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }
    return RichText(
      text: TextSpan(style: base, children: spans),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxBubbleWidth = MediaQuery.of(context).size.width * 0.75;
    final raw = widget.messages;
    final query = _search.text.trim().toLowerCase();
    List<ChatMessage> messages = raw;

    // Apply filter type
    if (_activeFilter == 'mentions') {
      messages = messages
          .where((m) => !m.isMe && _isMentioningMe(m.text))
          .toList();
    } else if (_activeFilter == 'media') {
      messages = messages.where((m) => m.hasAttachment).toList();
    }
    // Apply search
    if (query.isNotEmpty) {
      messages = messages
          .where(
            (m) =>
                m.text.toLowerCase().contains(query) ||
                (m.attachmentLabel?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    }
    final mentionPanel = _showMentionPanel
        ? Positioned(
            left: 12,
            right: 12,
            // Adjust to sit just above the input bar dynamically.
            bottom: (_inputBarHeight > 0 ? _inputBarHeight + 16 : 70),
            child: _MentionOverlay(
              fragment: _mentionFragment!,
              matches: _mentionMatches,
              onSelected: _insertMention,
            ),
          )
        : const SizedBox.shrink();

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        if (_showMentionPanel) {
          setState(() {
            _mentionFragment = null;
            _mentionMatches = [];
          });
          // Don't unfocus; user likely wants to keep typing.
          return;
        }
        FocusScope.of(context).unfocus();
      },
      child: Stack(
        children: [
          Column(
            children: [
              // Fixed header background to prevent tone change on scroll
              Container(
                color: backgroundDark,
                child: AnimatedCrossFade(
                  duration: const Duration(milliseconds: 220),
                  crossFadeState: _showSearch
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _search,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                            decoration: InputDecoration(
                              prefixIcon: const Icon(
                                AppIcons.search,
                                color: Colors.white54,
                                size: 18,
                              ),
                              hintText: 'Search in chat...',
                              hintStyle: const TextStyle(color: Colors.white38),
                              filled: true,
                              fillColor: surfaceDarker,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(color: borderDark),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(18),
                                borderSide: const BorderSide(color: accentTech),
                              ),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: () => _toggleSearch(false),
                          icon: const Icon(
                            AppIcons.close,
                            size: 20,
                            color: Colors.white54,
                          ),
                        ),
                      ],
                    ),
                  ),
                  secondChild: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'All',
                          active: _activeFilter == 'all',
                          onTap: () => _setFilter('all'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: '@ Mentions',
                          active: _activeFilter == 'mentions',
                          onTap: () => _setFilter('mentions'),
                        ),
                        const SizedBox(width: 6),
                        _FilterChip(
                          label: 'Media',
                          active: _activeFilter == 'media',
                          onTap: () => _setFilter('media'),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'Search',
                          onPressed: () => _toggleSearch(true),
                          icon: const Icon(
                            AppIcons.search,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  key: ValueKey(
                    'chatList-$_activeFilter-${_showSearch ? 's' : 'n'}',
                  ),
                  controller: _scroll,
                  reverse: _reversedMode,
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  physics: const ClampingScrollPhysics(),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    // Map visual index to logical chronological index.
                    final logicalIndex = _reversedMode
                        ? (messages.length - 1 - index)
                        : index;
                    final m = messages[logicalIndex];
                    final prev = logicalIndex > 0
                        ? messages[logicalIndex - 1]
                        : null; // earlier chronologically
                    final next = logicalIndex < messages.length - 1
                        ? messages[logicalIndex + 1]
                        : null; // later chronologically
                    final isMe = m.isMe;
                    final isSystem = (m.senderName == 'System');
                    final dt = m.time;
                    final dayChanged = () {
                      if (dt == null) {
                        return false;
                      }
                      if (prev?.time == null) {
                        return true; // first chronological message or different day
                      }
                      final a = DateTime(dt.year, dt.month, dt.day);
                      final b = DateTime(
                        prev!.time!.year,
                        prev.time!.month,
                        prev.time!.day,
                      );
                      return a != b;
                    }();
                    final showAvatar =
                        !isMe &&
                        (prev == null ||
                            prev.isMe ||
                            prev.senderName != m.senderName ||
                            dayChanged);
                    final continuedFromPrev =
                        prev != null &&
                        prev.isMe == isMe &&
                        !dayChanged &&
                        (prev.senderName == m.senderName);
                    final continuesToNext =
                        next != null &&
                        next.isMe == isMe &&
                        (next.senderName == m.senderName) &&
                        (next.time != null &&
                            m.time != null &&
                            DateTime(
                                  next.time!.year,
                                  next.time!.month,
                                  next.time!.day,
                                ) ==
                                DateTime(
                                  m.time!.year,
                                  m.time!.month,
                                  m.time!.day,
                                ));
                    // We no longer need a dedicated isLast margin; spacing applied at group ends below.

                    List<Widget> columnChildren = [];
                    if (dayChanged && dt != null) {
                      columnChildren.add(
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              const Expanded(
                                child: Divider(color: borderDark, thickness: 1),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _fmtDate(dt),
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Divider(color: borderDark, thickness: 1),
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    if (isSystem) {
                      columnChildren.add(
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Center(
                            child: Text(
                              m.text,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12.5,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      );
                    } else {
                      final radius = BorderRadius.only(
                        topLeft: Radius.circular(
                          isMe ? 18 : (continuedFromPrev ? 6 : 18),
                        ),
                        topRight: Radius.circular(
                          isMe ? (continuedFromPrev ? 6 : 18) : 18,
                        ),
                        bottomLeft: Radius.circular(
                          isMe ? 18 : (continuesToNext ? 6 : 18),
                        ),
                        bottomRight: Radius.circular(
                          isMe ? (continuesToNext ? 6 : 18) : 18,
                        ),
                      );
                      columnChildren.add(
                        Padding(
                          // Apply bottom margin at the end of a grouped sequence so every group (including the last and second-to-last after a send) gets breathing room.
                          padding: EdgeInsets.only(
                            // Add extra vertical space when switching between my messages and others.
                            top: continuedFromPrev
                                ? 1
                                : (prev != null && prev.isMe != isMe ? 10 : 4),
                            bottom: 0,
                          ),
                          child: Row(
                            mainAxisAlignment: isMe
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (!isMe && showAvatar) ...[
                                CircleAvatar(
                                  radius: 14,
                                  backgroundColor: const Color(0xFF374151),
                                  backgroundImage: AssetImage(
                                    _resolveAvatarFor(m.senderName) ??
                                        'assets/profile_placeholder.jpg',
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ] else if (!isMe) ...[
                                const SizedBox(
                                  width: 36,
                                ), // space for absent avatar alignment
                              ],
                              Flexible(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: maxBubbleWidth,
                                  ),
                                  child: GestureDetector(
                                    onLongPress: !isMe && widget.projectId != null
                                        ? () => _showReportDialog(context, m)
                                        : null,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: isMe
                                            ? const Color(0xFF1375D1)
                                            : const Color(0xFF262B36),
                                        borderRadius: radius,
                                        border: Border.all(
                                          color: isMe
                                              ? const Color(0xFF2C6AA6)
                                              : const Color(0xFF2A2F3A),
                                        ),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          10,
                                          16,
                                          10,
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                          Builder(
                                            builder: (context) {
                                              final name = m.isMe
                                                  ? 'Me'
                                                  : (m.senderName ?? '');
                                              final time = m.time != null
                                                  ? _fmtTime(m.time!)
                                                  : '';
                                              if (continuedFromPrev &&
                                                  name.isNotEmpty) {
                                                // hide name on continued bubble
                                                return Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    if (time.isNotEmpty)
                                                      Text(
                                                        time,
                                                        style: TextStyle(
                                                          color: Colors.white
                                                              .withValues(
                                                                alpha: 0.55,
                                                              ),
                                                          fontSize: 10.5,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                  ],
                                                );
                                              }
                                              return Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (name.isNotEmpty)
                                                    Text(
                                                      name,
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withValues(
                                                              alpha: 0.90,
                                                            ),
                                                        fontSize: 11.5,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        letterSpacing: -0.1,
                                                      ),
                                                    ),
                                                  if (time.isNotEmpty) ...[
                                                    const SizedBox(width: 6),
                                                    Text(
                                                      time,
                                                      style: TextStyle(
                                                        color: Colors.white
                                                            .withValues(
                                                              alpha: 0.55,
                                                            ),
                                                        fontSize: 10.5,
                                                        fontWeight:
                                                            FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                              );
                                            },
                                          ),
                                          const SizedBox(height: 4),
                                          _highlighted(
                                            m.text,
                                            _search.text.trim(),
                                            const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15.0,
                                              height: 1.34,
                                            ),
                                            isOnSentBubble: isMe,
                                          ),
                                          if (m.hasAttachment) ...[
                                            const SizedBox(height: 8),
                                            _AttachmentChip(
                                              type: m.attachmentType!,
                                              label:
                                                  m.attachmentLabel ??
                                                  m.attachmentType!,
                                              highlightQuery: _search.text
                                                  .trim(),
                                              highlighter: (text, q, style) =>
                                                  _highlighted(
                                                    text,
                                                    q,
                                                    style,
                                                    isOnSentBubble: isMe,
                                                  ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            ],
                          ),
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: columnChildren,
                    );
                  },
                ),
              ),
              const Divider(height: 1, color: borderDark),
              SafeArea(
                top: false,
                child: Padding(
                  key: _inputBarKey,
                  padding: const EdgeInsets.fromLTRB(4, 7, 10, 0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_pendingAttachmentType != null) ...[
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _PendingAttachmentChip(
                              type: _pendingAttachmentType!,
                              label:
                                  _pendingAttachmentLabel ??
                                  _pendingAttachmentType!,
                              onRemove: () {
                                setState(() {
                                  _pendingAttachmentType = null;
                                  _pendingAttachmentLabel = null;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                      Row(
                        children: [
                          IconButton(
                            onPressed: _openAttachmentSheet,
                            icon: const Icon(
                              AppIcons.attachment,
                              color: Colors.white70,
                            ),
                          ),
                          Expanded(
                            child: TextField(
                              controller: _input,
                              minLines: 1,
                              maxLines: 4,
                              style: const TextStyle(
                                color: neutralText,
                                fontSize: 15,
                              ),
                              decoration: InputDecoration(
                                hintText: 'Message...',
                                hintStyle: const TextStyle(
                                  color: Colors.white38,
                                ),
                                filled: true,
                                fillColor: surfaceDarker,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 12,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: const BorderSide(
                                    color: borderDark,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF3797EF),
                                    width: 1.2,
                                  ),
                                ),
                              ),
                              onSubmitted: (_) => _send(),
                            ),
                          ),
                          const SizedBox(width: 2),
                          if (_hasText || _pendingAttachmentType != null)
                            IconButton(
                              onPressed: _send,
                              icon: Icon(AppIcons.send, color: Colors.white),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // Pending attachment chip (positioned just above input bar for clarity)
          mentionPanel,
          // Raised jump-to-bottom button (higher in conversation space)
          if (_showJumpToBottom)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              right: 12,
              // Lift it further into the message area. Previously inputBarHeight + 14.
              // Now: bar height + 90 (fallback 150) -> feels more "in-thread" like Instagram.
              bottom: (_inputBarHeight > 0 ? _inputBarHeight + 50 : 100),
              child: GestureDetector(
                onTap: _jumpToBottom,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A313B),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: const Color(0xFF323843)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: const Icon(
                    AppIcons.chevronDown,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _openAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: surfaceDarker,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 5, 20, 10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      AppIcons.attachment,
                      color: Colors.white70,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Add attachment',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(
                        AppIcons.close,
                        color: Colors.white54,
                        size: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Grid style (icon stacked over label) similar to HTML mock (3 columns)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _AttachmentGridButton(
                      icon: AppIcons.file,
                      label: 'Document',
                      onTap: () {
                        Navigator.pop(context);
                        showOverlayNotice(context, 'Document attachment (coming soon)');
                      },
                    ),
                    _AttachmentGridButton(
                      icon: AppIcons.mic,
                      label: 'Audio',
                      onTap: () {
                        Navigator.pop(context);
                        showOverlayNotice(context, 'Audio attachment (coming soon)');
                      },
                    ),
                    _AttachmentGridButton(
                      icon: AppIcons.locationFilled,
                      label: 'Location',
                      onTap: () {
                        Navigator.pop(context);
                        showOverlayNotice(context, 'Location attachment (coming soon)');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF2A313B) : surfaceDarker,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: active ? accentTech : borderDark),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

class _AttachmentChip extends StatelessWidget {
  const _AttachmentChip({
    required this.type,
    required this.label,
    this.highlightQuery = '',
    this.highlighter,
  });
  final String type;
  final String label;
  final String highlightQuery; // lower/any case substring to highlight
  final Widget Function(String text, String query, TextStyle base)? highlighter;

  IconData _icon() {
    switch (type) {
      case 'document':
        return AppIcons.file;
      case 'audio':
        return AppIcons.mic;
      case 'location':
        return AppIcons.locationFilled;
      default:
        return AppIcons.attachment;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFF2A2F3A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF323843)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon(), size: 14, color: Colors.white70),
              const SizedBox(width: 6),
              highlighter == null
                  ? Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  : highlighter!(
                      label,
                      highlightQuery,
                      const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
            ],
          ),
        ),
      ],
    );
  }
}

// (Removed unused _AttachmentActionTile; replaced by grid buttons.)

// New compact grid button used in the attachment sheet (icon above label)
class _AttachmentGridButton extends StatelessWidget {
  const _AttachmentGridButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: Colors.white.withValues(alpha: 0.08),
        highlightColor: Colors.white.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: const Color(0xFF2A313B),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderDark),
                ),
                child: Icon(icon, color: Colors.white70, size: 26),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Displays a chip for a pending (not yet sent) attachment with a remove (X) action.
class _PendingAttachmentChip extends StatelessWidget {
  const _PendingAttachmentChip({
    required this.type,
    required this.label,
    required this.onRemove,
  });
  final String type;
  final String label;
  final VoidCallback onRemove;

  IconData _icon() {
    switch (type) {
      case 'document':
        return AppIcons.file;
      case 'audio':
        return AppIcons.mic;
      case 'location':
        return AppIcons.locationFilled;
      default:
        return AppIcons.attachment;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF2A313B),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF323843)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon(), size: 16, color: Colors.white70),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(width: 10),
            InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(AppIcons.close, size: 16, color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Mention Support Structures ---
class _MentionCandidate {
  final String display;
  final String token; // token inserted after '@'
  const _MentionCandidate({required this.display, required this.token});
}

class _MentionOverlay extends StatelessWidget {
  const _MentionOverlay({
    required this.fragment,
    required this.matches,
    required this.onSelected,
  });
  final String fragment;
  final List<_MentionCandidate> matches;
  final ValueChanged<_MentionCandidate> onSelected;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {}, // absorb taps inside popup
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E2530),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderDark),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 260),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 6),
              shrinkWrap: true,
              itemCount: matches.length,
              itemBuilder: (context, i) {
                final c = matches[i];
                final matchPortion = fragment.isEmpty
                    ? c.token
                    : c.token.substring(0, fragment.length);
                final rest = fragment.isEmpty
                    ? ''
                    : c.token.substring(fragment.length);
                return InkWell(
                  onTap: () => onSelected(c),
                  splashColor: Colors.white.withValues(alpha: 0.05),
                  highlightColor: Colors.white.withValues(alpha: 0.03),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          AppIcons.person,
                          size: 16,
                          color: Colors.white54,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              RichText(
                                text: TextSpan(
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: [
                                    TextSpan(text: '@$matchPortion'),
                                    if (rest.isNotEmpty)
                                      TextSpan(
                                        text: rest,
                                        style: const TextStyle(
                                          color: Colors.white54,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Text(
                                c.display,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
