import 'package:flutter/material.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'panel_scaffold.dart';
import 'package:flutter/services.dart';
import 'dart:ui' show ImageFilter;
import '../data/sample_data.dart';
import '../data/chat_repository.dart';
import '../data/mappers.dart';
import '../data/initial_data.dart' show isDemoProjectId;
import '../data/team_repository.dart';
import '../data/profile_repository.dart';
import '../theme/colors.dart';
import '../theme/app_icons.dart';
import 'package:intl/intl.dart';
import '../models/chat_thread.dart';
import '../models/team_member.dart';
import '../models/chat_message.dart';
import 'chat_thread_view.dart';
import '../data/project_images.dart';

class ChatPanel extends StatefulWidget {
  const ChatPanel({
    super.key,
    required this.onClose,
    required this.projectId,
    this.projectName,
    this.onComposeActiveChanged,
  });
  final VoidCallback onClose;
  final String projectId;
  final String? projectName;
  // Mirrors TeamPanel.onProfileActiveChanged
  final ValueChanged<bool>? onComposeActiveChanged;

  @override
  State<ChatPanel> createState() => _ChatPanelState();
}

class _ChatPanelState extends State<ChatPanel> {
  // Per-project in-memory chats/messages for non-demo projects
  // Legacy static maps replaced by ChatRepository; keep local transient state only if needed.

  bool get _isDemo => isDemoProjectId(widget.projectId);
  // Conversations persist for the session by mutating the shared sampleChats list directly.
  // Two-page flow: 0 = chats list, 1 = new conversation. Threads open as a slide-in route.
  late final PageController _pageController;
  bool _composeActive = false;
  // Match TeamPanel timings for consistency.
  static const Duration _forward = Duration(milliseconds: 520);
  static const Duration _back = Duration(milliseconds: 480);
  Offset? _lastTapPosition;
  // Track a lifted chat row (brought forward above the blur) while the menu is open.
  String? _liftedChatId;
  final Map<String, GlobalKey> _rowKeys = {};
  // Overlay notice for quick ephemeral messages (avoids SnackBar/Hero interactions)
  OverlayEntry? _noticeOverlay;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
  }

  @override
  void dispose() {
    _removeNoticeOverlay();
    _pageController.dispose();
    super.dispose();
  }

  void _removeNoticeOverlay() {
    try {
      _noticeTimer?.cancel();
    } catch (_) {}
    _noticeTimer = null;
    try {
      _noticeOverlay?.remove();
    } catch (_) {}
    _noticeOverlay = null;
  }

  void _showOverlayNotice(String message, {Duration duration = const Duration(milliseconds: 900)}) {
    // Clear any existing notice first
    _removeNoticeOverlay();
  final overlay = Overlay.of(context);
  _noticeOverlay = OverlayEntry(builder: (ctx) {
  final mq = MediaQuery.of(ctx);
  // Original chat panel placement: small margin above system inset (do not
  // lift above the bottom navigation bar so the notice sits closer to the
  // panel's content area).
  final bottom = mq.viewPadding.bottom + mq.viewInsets.bottom + 12.0;
      return Positioned(
        right: 16,
        left: 16,
        bottom: bottom,
        child: Material(
          color: Colors.transparent,
          child: Center(
            child: AnimatedOpacity(
              opacity: 1.0,
              duration: const Duration(milliseconds: 160),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: ShapeDecoration(
                  color: surfaceDark,
                  shape: const StadiumBorder(),
                  shadows: [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0,4))],
                ),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),
        ),
      );
    });
    overlay.insert(_noticeOverlay!);
    _noticeTimer = Timer(duration, _removeNoticeOverlay);
  }

  List<TeamMember> _filterOutCurrentUser(List<TeamMember> members) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final currentEmail = ProfileRepository.instance.profile.email;
    if (currentUid == null && currentEmail.isEmpty) return members;
    
    return members.where((m) {
      // Match by email to filter out current user
      if (currentEmail.isNotEmpty && m.email != null && m.email == currentEmail) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> _openComposer() async {
    setState(() => _composeActive = true);
    widget.onComposeActiveChanged?.call(true);
    final result = await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: _forward,
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          // Only demos have sample team members; non-demo projects read from TeamRepository
          final allMembers = _isDemo
              ? sampleTeamMembers
              : TeamRepository.instance.membersFor(widget.projectId);
          final members = _filterOutCurrentUser(allMembers);
            return _ComposerPage(members: members);
        },
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
    if (!mounted) return;
    if (result is _NewConversationResult) {
      final participants = result.members.map((m) => m.name).join(', ');
      final now = DateTime.now();
      final thread = ChatThread(
        id: 'new_${DateTime.now().millisecondsSinceEpoch}',
        username: result.title.isEmpty ? participants : result.title,
        lastMessage: 'Conversation created',
        lastTime: now,
        unreadCount: 0,
        avatarAsset: 'assets/profile_placeholder.jpg',
        isTeam: false,
      );
      setState(() {
        ChatRepository.instance.createThread(widget.projectId, thread);
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        ChatRepository.instance.addMessage(widget.projectId, thread.id, ChatMessage(
          text: 'Conversation created',
          isMe: true,
          senderName: 'System',
          senderUid: currentUid,
          time: now,
        ));
        // Participants tracking for demo mention support
        sampleChatParticipants[thread.id] = List<TeamMember>.from(result.members);
      });
      // StreamBuilder will automatically update when new thread is added
    }
    setState(() => _composeActive = false);
    widget.onComposeActiveChanged?.call(false);
  }

  void _backFromComposer() {
    // Always clear focus so typing stops and the keyboard dismisses
    FocusScope.of(context).unfocus();
    if (!_composeActive) {
      widget.onClose();
      return;
    }
    _pageController
        .animateToPage(0, duration: _back, curve: Curves.easeOutCubic)
        .whenComplete(() {
          if (mounted) {
            setState(() => _composeActive = false);
            widget.onComposeActiveChanged?.call(false);
          }
        });
  }

  Future<void> _openThread(ChatThread thread) async {
    // Clear unread and update lastTime so it moves up appropriately.
    ChatThread toOpen = thread;
    setState(() {
      ChatRepository.instance.markThreadRead(widget.projectId, thread.id);
      final threads = ChatRepository.instance.threadsFor(widget.projectId);
      final idx = threads.indexWhere((t) => t.id == thread.id);
      if (idx != -1) toOpen = threads[idx];
      _composeActive = false;
    });
    // Ensure the underlying PageView is back on the list page.
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        0,
        duration: _back,
        curve: Curves.easeOutCubic,
      );
    }
    // Mark thread as open before pushing route
    ChatRepository.instance.setThreadOpen(widget.projectId, toOpen.id);
    
    // Push a panel-like slide route for the thread view.
    await Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        transitionDuration: _forward,
        // Remove reverse transition so the route doesn't keep intercepting taps
        // after the thread content slid off-screen via our custom animation.
        reverseTransitionDuration: Duration.zero,
        pageBuilder: (context, animation, secondaryAnimation) {
          return _ThreadPage(
            thread: toOpen,
            projectId: widget.projectId,
            isDemo: _isDemo,
          );
        },
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(1, 0),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        },
      ),
    );
    
    // Mark thread as closed after route is popped and mark as read
    ChatRepository.instance.clearThreadOpen(widget.projectId, toOpen.id);
    
    if (!mounted) return;
    // Rebuild chats list to reflect the latest preview/time from messages.
    setState(() {});
  }

  Future<void> _showConversationMenu(
    ChatThread chat, {
    Rect? liftedRect,
    String? previewText,
    bool isUnread = false,
  }) async {
    final overlayBox =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final size = overlayBox.size;
    final tap = _lastTapPosition ?? size.center(Offset.zero);
    final selected = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'context menu',
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (context, anim, secondary) {
        // Menu target placement (approximate above the finger), constrained within the panel page.
        const menuWidth = 280.0;
        const menuHeightEst = 168.0; // estimated height of 3-option menu
        const menuGap = 12.0; // visual separation between menu and lifted row
        final safeTop =
            MediaQuery.of(context).padding.top + kToolbarHeight + 8.0;
        final safeBottom = size.height - 12.0;
        final left = (tap.dx - menuWidth / 2).clamp(
          12.0,
          size.width - 12.0 - menuWidth,
        );
        double top;
        if (liftedRect != null) {
          // Try to place above the lifted row with a gap; if not enough space, place below.
          final aboveTop = liftedRect.top - menuGap - menuHeightEst;
          if (aboveTop >= safeTop) {
            top = aboveTop.clamp(safeTop, safeBottom - menuHeightEst);
          } else {
            top = (liftedRect.bottom + menuGap).clamp(
              safeTop,
              safeBottom - menuHeightEst,
            );
          }
        } else {
          // Fallback to positioning relative to the tap point.
          final desiredTop = tap.dy - menuHeightEst;
          top = desiredTop.clamp(safeTop, safeBottom - menuHeightEst);
        }
        return Stack(
          children: [
            // Blurred backdrop only (no tint/dim), preserves underlying shapes
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).pop(),
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            if (liftedRect != null)
              Positioned.fromRect(
                rect: liftedRect,
                child: IgnorePointer(
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.98, end: 1.0).animate(
                      CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: surfaceDarker,
                        border: Border.all(color: borderDark),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 20,
                            spreadRadius: 1,
                            offset: Offset(0, 8),
                          ),
                        ],
                      ),
                      child: _buildRowContent(
                        chat,
                        previewText ?? chat.lastMessage,
                        isUnread,
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: left,
              top: top,
              child: _FloatingContextMenu(
                width: menuWidth,
                onSelected: (value) => Navigator.of(context).pop(value),
                showDelete: !(chat.isTeam),
              ),
            ),
          ],
        );
      },
      transitionBuilder: (context, anim, secondary, child) {
        final curved = CurvedAnimation(
          parent: anim,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(opacity: curved, child: child);
      },
    );
    if (!mounted) return;
    switch (selected) {
      case 'pin':
        _showOverlayNotice('Pin action (coming soon)');
        break;
      case 'mute':
        _showOverlayNotice('Mute action (coming soon)');
        break;
      case 'delete':
        // Show a demo overlay notice instead of actually deleting data in this demo app.
        _showOverlayNotice('Delete action (coming soon)');
        break;
      default:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // timeFmt now handled inside _buildRowContent where needed.
    // Sorting moved into StreamBuilder to update instantly with stream changes.
    return PopScope(
      canPop: !_composeActive,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _composeActive) {
          _backFromComposer();
        }
      },
      child: AnimatedBuilder(
        animation: _pageController,
        builder: (context, _) {
          // progress: 0 = list, 1 = composer
          double progress = 0;
          if (_pageController.hasClients &&
              _pageController.position.hasPixels) {
            final page =
                _pageController.page ?? _pageController.initialPage.toDouble();
            progress = page.clamp(0, 1);
          }
          // Clamp progress for list fade between page 0 and 1
          final listFade = (1 - progress).clamp(
            0.0,
            1.0,
          ); // fade out chats list + FAB

          // Keep team participants map in sync for demos only.
          if (_isDemo) sampleChatParticipants['team'] = sampleTeamMembers;
          return PanelScaffold(
            title: _composeActive ? 'New Conversation' : 'Chats',
            onClose: _composeActive ? _backFromComposer : widget.onClose,
            fab: IgnorePointer(
              ignoring: _composeActive || progress > 0.001,
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 260),
                opacity: listFade.clamp(0, 1),
                child: Transform.translate(
                  offset: const Offset(
                    0,
                    10,
                  ), // push a little closer to the bottom edge
                  child: IconButton(
                    onPressed: _openComposer,
                    icon: const Icon(AppIcons.addChat, color: Colors.white),
                    iconSize: 35,
                    splashRadius: 24,
                  ),
                ),
              ),
            ),
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // Chats list
                AnimatedBuilder(
                  animation: ProjectImages.instance,
                  builder: (context, _) {
                    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('projects')
                          .doc(widget.projectId)
                          .collection('chats')
                          .snapshots(includeMetadataChanges: true),
                      builder: (context, snap) {
                        List<ChatThread> baseThreads;
                        if (snap.hasData) {
                          // Stream has data - use it (even if empty, that's the real state)
                          baseThreads = snap.data!.docs
                              .map((d) {
                                try {
                                  return ChatThreadFirestore.fromMap(d.id, d.data());
                                } catch (e) {
                                  // Skip invalid documents
                                  return null;
                                }
                              })
                              .whereType<ChatThread>()
                              .toList();
                        } else if (snap.hasError) {
                          // On error, try repository fallback
                          baseThreads = ChatRepository.instance.threadsFor(widget.projectId);
                        } else {
                          // Waiting or no data yet, use repository as fallback
                          baseThreads = ChatRepository.instance.threadsFor(widget.projectId);
                        }
                        
                        // Recompute ordering on every stream update so threads move instantly.
                        final effectiveProjectName = widget.projectName;
                        final data = baseThreads
                            .map(
                              (c) => c.isTeam && effectiveProjectName != null
                                  ? ChatThread(
                                      id: c.id,
                                      username: 'Team – $effectiveProjectName',
                                      lastMessage: c.lastMessage,
                                      lastTime: c.lastTime,
                                      unreadCount: c.unreadCount,
                                      avatarAsset: c.avatarAsset,
                                      isTeam: c.isTeam,
                                    )
                                  : c,
                            )
                            .toList(growable: false);
                        final visibleChats = [...data]
                          ..sort((a, b) {
                            if (a.isTeam != b.isTeam) return a.isTeam ? -1 : 1;
                            return b.lastTime.compareTo(a.lastTime);
                          });
                    return Opacity(
                      opacity: listFade.clamp(0, 1),
                      child: Transform.translate(
                        offset: Offset(40 * progress, 0),
                        child: visibleChats.isEmpty
                            ? Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 24),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: const [
                                      Icon(
                                        AppIcons.multiplechats,
                                        size: 56,
                                        color: Color(0x66FFFFFF),
                                      ),
                                      SizedBox(height: 14),
                                      Text(
                                        'No chat',
                                        style: TextStyle(
                                          color: neutralText,
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.1,
                                        ),
                                      ),
                                      SizedBox(height: 6),
                                      Text(
                                        'you currently have no conversations yet',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white60,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                itemCount: visibleChats.length,
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 2),
                                itemBuilder: (context, index) {
                                  final chat = visibleChats[index];
                                  final currentUid = FirebaseAuth.instance.currentUser?.uid;
                                  
                                  // Stream all messages to calculate per-user unread count
                                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                                    stream: FirebaseFirestore.instance
                                        .collection('projects')
                                        .doc(widget.projectId)
                                        .collection('chats')
                                        .doc(chat.id)
                                        .collection('messages')
                                        .orderBy('time')
                                        .snapshots(includeMetadataChanges: true),
                                    builder: (context, allMsgSnap) {
                                      // Stream readBy to get lastReadTime for current user
                                      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                                        stream: currentUid != null
                                            ? FirebaseFirestore.instance
                                                .collection('projects')
                                                .doc(widget.projectId)
                                                .collection('chats')
                                                .doc(chat.id)
                                                .collection('readBy')
                                                .doc(currentUid)
                                                .snapshots(includeMetadataChanges: true)
                                            : null,
                                        builder: (context, readBySnap) {
                                          // Calculate per-user unread count based on lastReadTime
                                          int unreadCount = 0;
                                          DateTime? lastReadTime;
                                          
                                          if (readBySnap.hasData && readBySnap.data!.exists) {
                                            final lastReadTimeStr = readBySnap.data!.data()?['lastReadTime'] as String?;
                                            if (lastReadTimeStr != null) {
                                              try {
                                                lastReadTime = DateTime.parse(lastReadTimeStr);
                                              } catch (_) {}
                                            }
                                          }
                                          
                                          // If thread is currently open, don't count any messages as unread
                                          final isCurrentlyOpen = ChatRepository.instance.isThreadOpen(widget.projectId, chat.id);
                                          
                                          if (!isCurrentlyOpen && allMsgSnap.hasData && currentUid != null) {
                                            final messages = allMsgSnap.data!.docs
                                                .map((d) {
                                                  try {
                                                    return ChatMessageFirestore.fromMap(d.data(), currentUserUid: currentUid, id: d.id);
                                                  } catch (_) {
                                                    return null;
                                                  }
                                                })
                                                .whereType<ChatMessage>()
                                                .toList();
                                            
                                            // Count messages after lastReadTime that are not from current user and not system messages
                                            unreadCount = messages.where((m) {
                                              if (m.time == null) return false;
                                              if (m.senderUid == currentUid) return false; // Don't count own messages
                                              if (m.senderUid == null) return false; // Don't count system messages
                                              if (lastReadTime == null) return true; // If no lastReadTime, all messages are unread
                                              return m.time!.isAfter(lastReadTime);
                                            }).length;
                                          }
                                          
                                          // Get last message for preview
                                          ChatMessage? lastMessage;
                                          if (allMsgSnap.hasData && allMsgSnap.data!.docs.isNotEmpty) {
                                            try {
                                              // Get all messages, then get the last one
                                              final allMessages = allMsgSnap.data!.docs
                                                  .map((d) {
                                                    try {
                                                      return ChatMessageFirestore.fromMap(
                                                        d.data(),
                                                currentUserUid: currentUid,
                                                id: d.id,
                                              );
                                                    } catch (_) {
                                                      return null;
                                                    }
                                                  })
                                                  .whereType<ChatMessage>()
                                                  .toList();
                                              
                                              if (allMessages.isNotEmpty) {
                                                lastMessage = allMessages.last;
                                              }
                                            } catch (_) {
                                              // Fallback to repository
                                              final repoMessages = ChatRepository.instance.messagesFor(widget.projectId, chat.id);
                                              if (repoMessages.isNotEmpty) {
                                                lastMessage = repoMessages.last;
                                              }
                                            }
                                          } else {
                                            // Fallback to repository
                                            final repoMessages = ChatRepository.instance.messagesFor(widget.projectId, chat.id);
                                            if (repoMessages.isNotEmpty) {
                                              lastMessage = repoMessages.last;
                                            }
                                          }
                                          
                                          // Determine preview text
                                          String previewText;
                                          if (lastMessage != null) {
                                            if (lastMessage.text.isNotEmpty) {
                                              previewText = lastMessage.text;
                                            } else if (lastMessage.attachmentType != null) {
                                              previewText = lastMessage.attachmentLabel ?? 
                                                  '${lastMessage.attachmentType![0].toUpperCase()}${lastMessage.attachmentType!.substring(1)} attachment';
                                            } else {
                                              previewText = '…';
                                            }
                                          } else {
                                            // Use thread's lastMessage as fallback
                                            previewText = chat.lastMessage.isNotEmpty ? chat.lastMessage : '…';
                                          }
                                          
                                          // Unread = last message is NOT from current user AND unreadCount > 0
                                          final isFromCurrentUser = lastMessage != null && 
                                              lastMessage.senderUid != null && 
                                              currentUid != null && 
                                              lastMessage.senderUid == currentUid;
                                          final isUnread = unreadCount > 0 && 
                                              (lastMessage != null ? !isFromCurrentUser : false);
                                      
                                      final key = _rowKeys.putIfAbsent(
                                        chat.id,
                                        () => GlobalKey(),
                                      );
                                      
                                      return Opacity(
                                        opacity: _liftedChatId == chat.id ? 0.0 : 1.0,
                                        child: Container(
                                          key: key,
                                          child: InkWell(
                                            onTapDown: (details) {
                                              _lastTapPosition = details.globalPosition;
                                            },
                                            onLongPress: () async {
                                              HapticFeedback.lightImpact();
                                              // Measure row rect in Overlay coordinates and lift it.
                                              final overlayBox =
                                                  Overlay.of(
                                                        context,
                                                      ).context.findRenderObject()
                                                      as RenderBox;
                                              final rowBox =
                                                  key.currentContext?.findRenderObject()
                                                      as RenderBox?;
                                              Rect? rect;
                                              if (rowBox != null) {
                                                final topLeft = rowBox.localToGlobal(
                                                  Offset.zero,
                                                  ancestor: overlayBox,
                                                );
                                                rect = topLeft & rowBox.size;
                                                setState(() {
                                                  _liftedChatId = chat.id;
                                                });
                                              }
                                              await _showConversationMenu(
                                                chat,
                                                liftedRect: rect,
                                                previewText: previewText,
                                                isUnread: isUnread,
                                              );
                                              if (mounted) {
                                                setState(() {
                                                  _liftedChatId = null;
                                                });
                                              }
                                            },
                                            onTap: () => _openThread(chat),
                                            // Soft visual indication on press/hold
                                            splashFactory: NoSplash.splashFactory,
                                            overlayColor: WidgetStateProperty.resolveWith(
                                              (states) {
                                                if (states.contains(
                                                      WidgetState.pressed,
                                                    ) ||
                                                    states.contains(
                                                      WidgetState.focused,
                                                    ) ||
                                                    states.contains(
                                                      WidgetState.hovered,
                                                    )) {
                                                  return Colors.white.withValues(
                                                    alpha: 0.06,
                                                  );
                                                }
                                                return Colors.transparent;
                                              },
                                            ),
                                            highlightColor: Colors.transparent,
                                            splashColor: Colors.transparent,
                                            hoverColor: Colors.transparent,
                                            focusColor: Colors.transparent,
                                            enableFeedback: false,
                                            child: _buildRowContent(
                                              chat,
                                              previewText,
                                              isUnread,
                                            ),
                                          ),
                                        ),
                                      );
                                        },
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          );
                        },
                      );
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Reusable chat row content for both the list and the lifted overlay.
  Widget _buildRowContent(ChatThread chat, String previewText, bool isUnread) {
    final timeFmt = DateFormat.Hm();
    MemoryImage? teamProjectImage;
    if (chat.isTeam && widget.projectName != null) {
      final bytes = ProjectImages.instance.get(widget.projectName!);
      if (bytes != null) teamProjectImage = MemoryImage(bytes);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFF1F2937),
            backgroundImage: teamProjectImage ??
                (chat.avatarAsset != null
                    ? AssetImage(chat.avatarAsset!)
                    : const AssetImage('assets/profile_placeholder.jpg')),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        chat.username,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: const Color(0xFFFFFFFF),
                          fontWeight: isUnread
                              ? FontWeight.w800
                              : FontWeight.w600,
                          fontSize: 16,
                          letterSpacing: -0.1,
                          decoration: TextDecoration.none,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeFmt.format(chat.lastTime),
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 12,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        if (isUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: accentTech,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  previewText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isUnread ? const Color(0xFFFFFFFF) : Colors.white60,
                    fontSize: 13,
                    fontWeight: isUnread ? FontWeight.w700 : FontWeight.w400,
                    decoration: TextDecoration.none,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Slide-in thread page that mirrors the panel style and reuses PanelScaffold.
class _ThreadPage extends StatefulWidget {
  const _ThreadPage({required this.thread, required this.projectId, required this.isDemo});
  final ChatThread thread;
  final String projectId;
  final bool isDemo;

  @override
  State<_ThreadPage> createState() => _ThreadPageState();
}

class _ThreadPageState extends State<_ThreadPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _dragX = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 240),
        )..addListener(() {
          setState(() {});
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target, double width, {bool thenPop = false}) {
    final start = _dragX;
    final distance = (target - start).abs();
    final duration = Duration(
      milliseconds: (240 * (distance / width)).clamp(120, 240).toInt(),
    );
    _controller.duration = duration;
    _controller.reset();
    final tween = Tween<double>(
      begin: start,
      end: target,
    ).chain(CurveTween(curve: Curves.easeOutCubic));
    final anim = tween.animate(_controller);
    _controller.addListener(() {
      setState(() => _dragX = anim.value);
    });
    _controller.forward().whenComplete(() async {
      if (thenPop && mounted) {
        // Pop immediately (no reverse transition) once content is off-screen,
        // so underlying UI becomes interactive without any invisible overlay window.
        Navigator.of(context).pop();
      }
    });
  }

  Widget _buildThreadContent(List<ChatMessage> messages, List<TeamMember> teamMembers) {
    final thread = widget.thread;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            // System back: animate out, then pop immediately (no reverse route anim).
            _controller.stop();
            _animateTo(width, width, thenPop: true);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) {
              // Begin drag from anywhere to mimic panel behavior.
              _dragging = true;
              _controller.stop();
            },
            onHorizontalDragUpdate: (details) {
              if (!_dragging) return;
              setState(() {
                _dragX = (_dragX + details.delta.dx).clamp(0.0, width);
              });
            },
            onHorizontalDragEnd: (details) {
              if (!_dragging) return;
              _dragging = false;
              final vx = details.primaryVelocity ?? 0;
              final progress = _dragX / width;
              final shouldPop = progress > 0.33 || vx > 800;
              if (shouldPop) {
                _animateTo(width, width, thenPop: true);
              } else {
                _animateTo(0, width);
              }
            },
            child: Stack(
              children: [
                // Scrim over underlying content that fades in as you drag right
                IgnorePointer(
                  child: Opacity(
                    opacity: (_dragX / width).clamp(0.0, 1.0) * 0.25,
                    child: const ColoredBox(color: Colors.black),
                  ),
                ),
                Transform.translate(
                  offset: Offset(_dragX, 0),
                  child: PanelScaffold(
                    title: thread.username,
                    onClose: () {
                      // Close button: animate out, then pop immediately so underlying is clickable right away.
                      _controller.stop();
                      _animateTo(width, width, thenPop: true);
                    },
                    child: ChatThreadView(
                      messages: messages,
                      otherAvatarAsset: thread.avatarAsset,
                      // Team conversation: use streamed team members for reactive updates
                      participants: thread.isTeam
                          ? teamMembers.map((m) => m.name).toList(growable: false)
                          : (sampleChatParticipants[thread.id]
                                  ?.map((m) => m.name)
                                  .toList(growable: false) ??
                              const []),
                      projectId: widget.projectId,
                      threadId: thread.id,
                      avatarsByName: thread.isTeam
                          ? {
                              for (final m in teamMembers)
                                m.name: m.photoAsset ?? 'assets/profile_placeholder.jpg',
                            }
                          : null,
                      onSendMessage: (msg) {
                        // Add via repository only (it updates the in-memory list and thread preview + writes for demo).
                        ChatRepository.instance.addMessage(widget.projectId, thread.id, msg);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    // Stream messages for this thread
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('projects')
          .doc(widget.projectId)
          .collection('chats')
          .doc(thread.id)
          .collection('messages')
          .orderBy('time')
          .snapshots(includeMetadataChanges: true),
      builder: (context, msgSnap) {
        List<ChatMessage> messages;
        if (msgSnap.hasData) {
          final currentUid = FirebaseAuth.instance.currentUser?.uid;
          messages = msgSnap.data!.docs
              .map((d) {
                try {
                  return ChatMessageFirestore.fromMap(d.data(), currentUserUid: currentUid, id: d.id);
                } catch (_) {
                  return null;
                }
              })
              .whereType<ChatMessage>()
              .toList();
        } else {
          // Fallback to repository
          messages = ChatRepository.instance.messagesFor(widget.projectId, thread.id);
        }
        
        // Stream team members if this is a team thread
        if (thread.isTeam) {
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('projects')
                .doc(widget.projectId)
                .collection('team')
                .orderBy('name')
                .snapshots(includeMetadataChanges: true),
            builder: (context, teamSnap) {
              List<TeamMember> teamMembers;
              Map<String, TeamMember> teamMembersByUid = {};
              if (teamSnap.hasData) {
                teamMembers = teamSnap.data!.docs
                    .map((d) {
                      try {
                        final member = TeamMemberFirestore.fromMap(d.data());
                        // Store mapping: document ID (UID) -> TeamMember
                        teamMembersByUid[d.id] = member;
                        return member;
                      } catch (_) {
                        return null;
                      }
                    })
                    .whereType<TeamMember>()
                    .toList();
              } else {
                // Fallback to repository
                teamMembers = TeamRepository.instance.membersFor(widget.projectId);
                if (teamMembers.isEmpty && widget.isDemo) {
                  teamMembers = sampleTeamMembers;
                }
              }
              
              // Resolve sender names from team members using senderUid
              final resolvedMessages = messages.map((msg) {
                if (msg.senderUid != null && !msg.isMe && teamMembersByUid.containsKey(msg.senderUid)) {
                  final teamMember = teamMembersByUid[msg.senderUid]!;
                  // Update sender name to match team member name for proper avatar resolution
                  if (teamMember.name != msg.senderName) {
                    return msg.copyWith(senderName: teamMember.name);
                  }
                }
                return msg;
              }).toList();
              
              return _buildThreadContent(resolvedMessages, teamMembers);
            },
          );
        } else {
          // Not a team thread, use empty list for team members
          return _buildThreadContent(messages, const []);
        }
      },
    );
  }
}

// Slide-in composer page that mirrors the thread page interaction and speed.
class _ComposerPage extends StatefulWidget {
  const _ComposerPage({required this.members});
  final List<TeamMember> members;

  @override
  State<_ComposerPage> createState() => _ComposerPageState();
}

class _FloatingContextMenu extends StatelessWidget {
  const _FloatingContextMenu({
    required this.onSelected,
    this.width = 320,
    this.showDelete = true,
  });
  final ValueChanged<String> onSelected;
  final double width;
  final bool showDelete;

  Widget _item({
    required String label,
    required Widget trailing,
    Color? color,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      overlayColor: WidgetStateProperty.all(
        Colors.white.withValues(alpha: 0.04),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color ?? neutralText,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  letterSpacing: -0.1,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFF252A31),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderDark),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 18, spreadRadius: 1),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item(
              label: 'Pin',
              trailing: const Icon(
                AppIcons.pin,
                color: Colors.white70,
                size: 18,
              ),
              onTap: () => onSelected('pin'),
            ),
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
            _item(
              label: 'Mute',
              trailing: const Icon(
                AppIcons.mute,
                color: Colors.white70,
                size: 18,
              ),
              onTap: () => onSelected('mute'),
            ),
            if (showDelete) ...[
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.10)),
              _item(
                label: 'Delete',
                trailing: const Icon(
                  AppIcons.deleteFilled,
                  color: Colors.redAccent,
                  size: 18,
                ),
                color: Colors.redAccent,
                onTap: () => onSelected('delete'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ComposerPageState extends State<_ComposerPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _dragX = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 240),
        )..addListener(() {
          setState(() {});
        });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateTo(double target, double width, {bool thenPop = false}) {
    final start = _dragX;
    final distance = (target - start).abs();
    final duration = Duration(
      milliseconds: (240 * (distance / width)).clamp(120, 240).toInt(),
    );
    _controller.duration = duration;
    _controller.reset();
    final tween = Tween<double>(
      begin: start,
      end: target,
    ).chain(CurveTween(curve: Curves.easeOutCubic));
    final anim = tween.animate(_controller);
    _controller.addListener(() {
      setState(() => _dragX = anim.value);
    });
    _controller.forward().whenComplete(() async {
      if (thenPop && mounted) {
        Navigator.of(context).pop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) async {
            if (didPop) return;
            _controller.stop();
            _animateTo(width, width, thenPop: true);
          },
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) {
              _dragging = true;
              _controller.stop();
            },
            onHorizontalDragUpdate: (details) {
              if (!_dragging) return;
              setState(() {
                _dragX = (_dragX + details.delta.dx).clamp(0.0, width);
              });
            },
            onHorizontalDragEnd: (details) {
              if (!_dragging) return;
              _dragging = false;
              final vx = details.primaryVelocity ?? 0;
              final progress = _dragX / width;
              final shouldPop = progress > 0.33 || vx > 800;
              if (shouldPop) {
                _animateTo(width, width, thenPop: true);
              } else {
                _animateTo(0, width);
              }
            },
            child: Transform.translate(
              offset: Offset(_dragX, 0),
              child: PanelScaffold(
                title: 'New Conversation',
                onClose: () {
                  _controller.stop();
                  _animateTo(width, width, thenPop: true);
                },
                child: _NewConversationPage(
                  members: widget.members,
                  onCancel: () {
                    _controller.stop();
                    _animateTo(width, width, thenPop: true);
                  },
                  onCreate: (result) {
                    Navigator.of(context).pop(result);
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _NewConversationResult {
  final String title;
  final List<TeamMember> members;
  _NewConversationResult(this.title, this.members);
}

// Full-page composer mirroring the dialog content
class _NewConversationPage extends StatefulWidget {
  const _NewConversationPage({
    required this.members,
    required this.onCancel,
    required this.onCreate,
  });
  final List<TeamMember> members;
  final VoidCallback onCancel;
  final ValueChanged<_NewConversationResult> onCreate;
  @override
  State<_NewConversationPage> createState() => _NewConversationPageState();
}

class _NewConversationPageState extends State<_NewConversationPage> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<int> _selectedIds = {};
  String _filter = '';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _submit() {
    if (_selectedIds.isEmpty) return;
    final chosen = widget.members
        .where((m) => _selectedIds.contains(m.id))
        .toList(growable: false);
    widget.onCreate(_NewConversationResult(_titleCtrl.text.trim(), chosen));
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final filtered = _filter.isEmpty
        ? members
        : members
              .where(
                (m) =>
                    m.name.toLowerCase().contains(_filter) ||
                    m.role.toLowerCase().contains(_filter),
              )
              .toList(growable: false);
  // const accent = newaccent;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'New Conversation',
              style: TextStyle(
                color: neutralText,
                fontSize: 19,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              onChanged: (v) =>
                  setState(() => _filter = v.trim().toLowerCase()),
              style: const TextStyle(color: neutralText, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search team members',
                hintStyle: const TextStyle(color: Colors.white38),
                prefixIcon: const Icon(
                  AppIcons.search,
                  size: 20,
                  color: Colors.white54,
                ),
                filled: true,
                fillColor: surfaceDarker,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: borderDark),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: Color(0xFF3797EF),
                    width: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text(
                  'Participants',
                  style: TextStyle(
                    color: neutralText,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _selectedIds.isEmpty
                        ? surfaceDarker
                        : accentTech.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _selectedIds.isEmpty
                          ? borderDark
                          : accentTech.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Text(
                    '${_selectedIds.length} selected',
                    style: TextStyle(
                      color: _selectedIds.isEmpty
                          ? const Color(0x89FFFFFF)
                          : const Color(0xFF3B82F6),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Title field moves under the Participants heading and appears only after selecting members
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              reverseDuration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final fade = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                );
                final size = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                );
                return FadeTransition(
                  opacity: fade,
                  child: SizeTransition(
                    sizeFactor: size,
                    axis: Axis.vertical,
                    axisAlignment: -1.0,
                    child: child,
                  ),
                );
              },
              child: _selectedIds.isNotEmpty
                  ? Column(
                      key: const ValueKey('titleField'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _titleCtrl,
                          style: const TextStyle(
                            color: neutralText,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Conversation title (optional)',
                            hintStyle: const TextStyle(color: Colors.white38),
                            filled: true,
                            fillColor: surfaceDarker,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: borderDark),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(
                                color: Color(0xFF3797EF),
                                width: 1.4,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    )
                  : const SizedBox.shrink(key: ValueKey('titleFieldHidden')),
            ),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  decoration: BoxDecoration(
                    color: surfaceDarker,
                    border: Border.all(color: borderDark),
                  ),
                  child: members.isEmpty
                      ? const Center(
                          child: Text(
                            'No team members yet',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        )
                      : Scrollbar(
                          child: ListView.separated(
                            itemCount: filtered.length,
                            separatorBuilder: (_, idx) => const Divider(
                              height: 1,
                              color: borderDark,
                              indent: 56,
                            ),
                            itemBuilder: (context, index) {
                              final m = filtered[index];
                              final selected = _selectedIds.contains(m.id);
                              return GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _toggle(m.id),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                    horizontal: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? accentTech.withValues(alpha: 0.12)
                                        : Colors.transparent,
                                  ),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 18,
                                        backgroundColor: const Color(0xFF374151),
                                        backgroundImage: m.photoAsset != null
                                            ? AssetImage(m.photoAsset!)
                                            : const AssetImage(
                                                'assets/profile_placeholder.jpg',
                                              ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              m.name,
                                              style: const TextStyle(
                                                color: neutralText,
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Text(
                                              m.role,
                                              style: const TextStyle(
                                                color: Colors.white54,
                                                fontSize: 12,
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
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: _selectedIds.isEmpty
                        ? surfaceDarker
                        : accentTech.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _selectedIds.isEmpty
                          ? borderDark
                          : accentTech.withValues(alpha: 0.6),
                    ),
                  ),
                  child: TextButton(
                    onPressed: _selectedIds.isEmpty ? null : _submit,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 13,
                      ),
                      foregroundColor: _selectedIds.isEmpty
                          ? const Color(0x89FFFFFF)
                          : const Color(0xFF3B82F6),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                      backgroundColor: Colors.transparent,
                      disabledForegroundColor: const Color(0x89FFFFFF),
                    ),
                    child: const Text('Create Conversation'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NewConversationDialog extends StatefulWidget {
  const _NewConversationDialog({required this.members});
  final List<TeamMember> members;
  @override
  State<_NewConversationDialog> createState() => _NewConversationDialogState();
}

class _NewConversationDialogState extends State<_NewConversationDialog> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<int> _selectedIds = {};
  String _filter = '';

  @override
  void dispose() {
    _titleCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _toggle(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _submit() {
    if (_selectedIds.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final chosen = widget.members
        .where((m) => _selectedIds.contains(m.id))
        .toList(growable: false);
    Navigator.of(
      context,
    ).pop(_NewConversationResult(_titleCtrl.text.trim(), chosen));
  }

  @override
  Widget build(BuildContext context) {
    final members = widget.members;
    final filtered = _filter.isEmpty
        ? members
        : members
              .where(
                (m) =>
                    m.name.toLowerCase().contains(_filter) ||
                    m.role.toLowerCase().contains(_filter),
              )
              .toList(growable: false);
    // Use construction (orange) accent instead of tech (blue) within this dialog.
  const accent = newaccent;
    return Dialog(
      backgroundColor: surfaceDark,
      // Slightly reduce side inset so a wider dialog uses more screen width.
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: borderDark, width: 1),
      ),
      child: ConstrainedBox(
        // Make the entire popup wider; allow it to grow but cap for very large screens.
        constraints: const BoxConstraints(
          maxHeight: 600,
          minWidth: 720,
          maxWidth: 920,
        ),
        child: Padding(
          // Slightly tighter side padding so content uses more width.
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New Conversation',
                style: TextStyle(
                  color: neutralText,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _titleCtrl,
                style: const TextStyle(color: neutralText, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Conversation title (optional)',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: surfaceDarker,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: borderDark),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: accent, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _searchCtrl,
                onChanged: (v) =>
                    setState(() => _filter = v.trim().toLowerCase()),
                style: const TextStyle(color: neutralText, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Search team members',
                  hintStyle: const TextStyle(color: Colors.white38),
                  prefixIcon: const Icon(
                    AppIcons.search,
                    size: 20,
                    color: Colors.white54,
                  ),
                  filled: true,
                  fillColor: surfaceDarker,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: borderDark),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: accent, width: 1.4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(
                    'Participants',
                    style: const TextStyle(
                      color: neutralText,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _selectedIds.isEmpty
                          ? surfaceDarker
                          : accentTech.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _selectedIds.isEmpty
                            ? borderDark
                            : accentTech.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      '${_selectedIds.length} selected',
                      style: TextStyle(
                        color: _selectedIds.isEmpty
                            ? Colors.white54
                            : accentTech,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    decoration: BoxDecoration(
                      color: surfaceDarker,
                      border: Border.all(color: borderDark),
                    ),
                    child: Scrollbar(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, idx) => const Divider(
                          height: 1,
                          color: borderDark,
                          // Adjusted indent now that the leading selection circle is removed
                          indent: 56,
                        ),
                        itemBuilder: (context, index) {
                          final m = filtered[index];
                          final selected = _selectedIds.contains(m.id);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _toggle(m.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 14,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? accentTech.withValues(alpha: 0.12)
                                    : Colors.transparent,
                              ),
                              child: Row(
                                children: [
                                  // Avatar now first element (selection indicated by row highlight only)
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: const Color(0xFF374151),
                                    backgroundImage: m.photoAsset != null
                                        ? AssetImage(m.photoAsset!)
                                        : const AssetImage(
                                            'assets/profile_placeholder.jpg',
                                          ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          m.name,
                                          style: const TextStyle(
                                            color: neutralText,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          m.role,
                                          style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12,
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
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  ElevatedButton(
                    onPressed: _selectedIds.isEmpty ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      disabledBackgroundColor: accent.withValues(alpha: 0.25),
                      foregroundColor: Colors.white,
                      disabledForegroundColor: Colors.white54,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 13,
                      ),
                      textStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('Create Conversation'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
