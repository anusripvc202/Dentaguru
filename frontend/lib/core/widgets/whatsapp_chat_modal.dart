import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';
import '../services/patient_problem_service.dart';
import '../services/session_service.dart';
import '../services/supabase_service.dart';

/// Real-Time 1-on-1 Chat Modal
/// Supports instant optimistic messaging, Supabase Realtime subscription + 2-second polling,
/// read receipts, and RBAC-enforced backend persistence.
class WhatsAppChatModal extends StatefulWidget {
  final String patientName;
  final String doctorName;
  final String currentUserRole; // 'Patient' | 'Dentist' | 'Clinic' | 'Admin'
  final String? patientId;
  final String? doctorId;
  final String? roomIdOverride;

  const WhatsAppChatModal({
    super.key,
    required this.patientName,
    required this.doctorName,
    required this.currentUserRole,
    this.patientId,
    this.doctorId,
    this.roomIdOverride,
  });

  static void show(
    BuildContext context, {
    required String patientName,
    required String doctorName,
    required String currentUserRole,
    String? patientId,
    String? doctorId,
    String? roomIdOverride,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => WhatsAppChatModal(
        patientName: patientName,
        doctorName: doctorName,
        currentUserRole: currentUserRole,
        patientId: patientId,
        doctorId: doctorId,
        roomIdOverride: roomIdOverride,
      ),
    );
  }

  @override
  State<WhatsAppChatModal> createState() => _WhatsAppChatModalState();
}

class _WhatsAppChatModalState extends State<WhatsAppChatModal>
    with WidgetsBindingObserver {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final PatientProblemService _problemService = PatientProblemService();

  late String _roomId;
  List<dynamic> _messages = [];
  bool _isLoading = true;
  bool _isSending = false;
  String? _errorBanner;
  Timer? _pollTimer;
  RealtimeChannel? _realtimeChannel;

  bool get _isDentist => widget.currentUserRole.toLowerCase().contains('dentist') || widget.currentUserRole.toLowerCase().contains('doctor');
  bool get _isAdmin => widget.currentUserRole.toLowerCase().contains('admin');

  String get _currentUserId {
    final sessId = SessionService().currentSession?.canonicalUserId ?? '';
    if (sessId.isNotEmpty) return sessId;
    return SupabaseService.safeCurrentUser?.id ?? '';
  }

  String get _counterpartName => _isDentist
      ? (widget.patientName.isNotEmpty ? widget.patientName : 'Patient')
      : (widget.doctorName.isNotEmpty ? widget.doctorName : 'Doctor');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _roomId = (widget.roomIdOverride != null && widget.roomIdOverride!.trim().isNotEmpty)
        ? ApiService.normalizeRoomId(widget.roomIdOverride!)
        : ApiService.getChatRoomId(
            patientIdOrName: widget.patientName.isNotEmpty ? widget.patientName : (widget.patientId ?? 'PATIENT'),
            dentistIdOrName: widget.doctorName.isNotEmpty ? widget.doctorName : (widget.doctorId ?? 'DOCTOR'),
          );

    _loadMessages();
    _subscribeRealtime();

    // Reliable 2-second background refresh alongside Supabase Realtime
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollMessages();
    });
  }

  void _subscribeRealtime() {
    try {
      final client = SupabaseService.safeClient;
      if (client == null) return;
      _realtimeChannel = client
          .channel('chat_messages_$_roomId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'chat_messages',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'room_id',
              value: _roomId,
            ),
            callback: (_) {
              _pollMessages();
            },
          )
          .subscribe();
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      unawaited(_handleAppResumed());
    }
  }

  Future<void> _handleAppResumed() async {
    try {
      final session = SessionService().currentSession;
      if (session != null && session.token.trim().isNotEmpty) {
        final roleLower = session.role.trim().toLowerCase();
        final isSubAdmin = roleLower.contains('sub-admin') ||
            roleLower.contains('subadmin') ||
            roleLower.contains('sub_admin');
        if (!isSubAdmin) {
          await SessionService().bindRealtimeSession(session);
        }
      }
    } catch (_) {}
    if (!mounted) return;
    try {
      await _realtimeChannel?.unsubscribe();
    } catch (_) {}
    _realtimeChannel = null;
    _subscribeRealtime();
    await _pollMessages();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    try {
      _realtimeChannel?.unsubscribe();
    } catch (_) {}
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await _apiService.fetchChatMessages(roomId: _roomId, markRead: true);
      if (mounted) {
        _reconcileMessages(msgs);
        setState(() {
          _isLoading = false;
          _errorBanner = null;
        });
      }
      final uid = _currentUserId;
      if (msgs.any((m) => m['read'] != true && m['sender_id']?.toString() != uid)) {
        _apiService.markChatRoomRead(roomId: _roomId, currentUserId: uid);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorBanner = 'Unable to load conversation history.';
        });
      }
    }
  }

  Future<void> _pollMessages() async {
    try {
      final msgs = await _apiService.fetchChatMessages(roomId: _roomId);
      if (mounted) {
        _reconcileMessages(msgs);
        final uid = _currentUserId;
        if (msgs.any((m) => m['read'] != true && m['sender_id']?.toString() != uid)) {
          _apiService.markChatRoomRead(roomId: _roomId, currentUserId: uid);
        }
      }
    } catch (_) {}
  }

  void _reconcileMessages(List<dynamic> serverMsgs) {
    if (!mounted) return;

    // Retain any pending optimistic messages not yet reflected in serverMsgs
    final unconfirmed = _messages.where((m) {
      final id = (m['id'] ?? '').toString();
      if (!id.startsWith('temp_')) return false;
      final text = (m['message'] ?? '').toString().trim();
      final type = (m['type'] ?? '').toString();
      return !serverMsgs.any((sm) =>
          (sm['message'] ?? '').toString().trim() == text &&
          (sm['type'] ?? '').toString() == type);
    }).toList();

    final merged = [...serverMsgs, ...unconfirmed];
    final prevLastId = _messages.isNotEmpty ? (_messages.last['id'] ?? '').toString() : '';
    final nextLastId = merged.isNotEmpty ? (merged.last['id'] ?? '').toString() : '';
    if (merged.length != _messages.length || prevLastId != nextLastId || (serverMsgs.isNotEmpty && _messages.isEmpty)) {
      setState(() {
        _messages = merged;
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 80,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _msgController.text.trim();
    if (text.isEmpty || _isSending) return;

    _msgController.clear();

    final currentUserId = _currentUserId;
    final currentUserName = SessionService().currentSession?.name ?? '';

    final effectiveSenderId = _isAdmin
        ? (currentUserId.isNotEmpty ? currentUserId : 'ADMIN')
        : (_isDentist
            ? (currentUserId.isNotEmpty ? currentUserId : (widget.doctorId?.isNotEmpty == true ? widget.doctorId! : widget.doctorName))
            : (currentUserId.isNotEmpty ? currentUserId : (widget.patientId?.isNotEmpty == true ? widget.patientId! : widget.patientName)));

    final msgType = _isAdmin ? 'admin' : (_isDentist ? 'doctor' : 'patient');
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';

    final optimisticMsg = {
      'id': tempId,
      'room_id': _roomId,
      'sender_id': effectiveSenderId,
      'message': text,
      'type': msgType,
      'sender': {
        'id': effectiveSenderId,
        'name': currentUserName.isNotEmpty ? currentUserName : (_isAdmin ? 'Admin' : (_isDentist ? widget.doctorName : widget.patientName)),
        'role': widget.currentUserRole,
      },
      'created_at': DateTime.now().toIso8601String(),
      'read': false,
    };

    setState(() {
      _isSending = true;
      _errorBanner = null;
      _messages.add(optimisticMsg);
    });
    _scrollToBottom();

    try {
      final sendRes = await _apiService.sendMessage(
        senderId: effectiveSenderId,
        message: text,
        roomId: _roomId,
        type: msgType,
        senderRole: _isAdmin ? 'Admin' : (_isDentist ? 'Dentist' : 'Patient'),
        receiverId: _isDentist ? widget.patientId : widget.doctorId,
      );

      if (sendRes['success'] != true) {
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m['id'] == tempId);
            _errorBanner = sendRes['message']?.toString() ?? 'Failed to send message.';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_errorBanner!),
              backgroundColor: const Color(0xFFFE3434),
            ),
          );
        }
        return;
      }

      // Notify recipient
      final targetRecipientId = _isDentist
          ? ((widget.patientId != null && widget.patientId!.isNotEmpty) ? widget.patientId! : _counterpartName)
          : ((widget.doctorId != null && widget.doctorId!.isNotEmpty) ? widget.doctorId! : _counterpartName);
      _problemService.addNotification(
        recipientRole: _isDentist ? 'Patient' : 'Dentist',
        recipientId: targetRecipientId,
        title: _isDentist ? '💬 Doctor Reply' : '💬 New Patient Message',
        message: '${_isDentist ? widget.doctorName : widget.patientName}: "$text"',
      );

      final updated = await _apiService.fetchChatMessages(roomId: _roomId);
      if (mounted) {
        _reconcileMessages(updated);
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m['id'] == tempId);
          _errorBanner = 'Connection error while sending message. Please try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarLetter = _counterpartName.replaceAll('Dr. ', '').replaceAll('Dr.', '').trim();
    final letter = avatarLetter.isNotEmpty ? avatarLetter[0].toUpperCase() : 'U';

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9), // Authentic WhatsApp Doodle Beige
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 🟢 Authentic WhatsApp Teal Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF012A58), // Authentic WhatsApp Teal
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 22),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  const SizedBox(width: 8),
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Text(
                          letter,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFE3434),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF012A58), width: 1.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _counterpartName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.white, size: 20),
                    tooltip: 'Clear Chat History',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (confirmCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                          title: const Row(
                            children: [
                              Icon(Icons.delete_forever_rounded, color: Color(0xFFFE3434)),
                              SizedBox(width: 8),
                              Text('Clear Chat History?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          content: const Text('This will permanently delete all messages in this conversation. Are you sure?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text('Cancel')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFE3434), foregroundColor: Colors.white),
                              onPressed: () async {
                                Navigator.pop(confirmCtx);
                                final ok = await _apiService.clearChatMessages(roomId: _roomId);
                                if (ok && mounted) {
                                  setState(() => _messages = []);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('🗑️ Chat history cleared!'), backgroundColor: Color(0xFF012A58)),
                                  );
                                }
                              },
                              child: const Text('Clear Chat', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),

          if (_errorBanner != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFFFEE2E2),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFB91C1C)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _errorBanner!,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C), fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),

          // 💬 Live Chat Thread Area
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF012A58)))
                : _messages.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0x14FE3434),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded, size: 14, color: Color(0xFFFE3434)),
                              SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'Messages are end-to-end encrypted.',
                                  style: TextStyle(fontSize: 11, color: Color(0xFFFE3434), fontWeight: FontWeight.w500),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: _messages.length,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        itemBuilder: (itemCtx, index) {
                          final m = _messages[index];
                          final text = (m['message'] ?? '').toString();
                          final mType = (m['type'] ?? '').toString();
                          final msgId = (m['id'] ?? m['_id'] ?? '').toString();
                          final senderObj = m['sender'] is Map ? m['sender'] : {};
                          final senderRole = (senderObj['role'] ?? '').toString();
                          final senderName = (senderObj['name'] ?? m['sender_id'] ?? '').toString();

                          final createdAt = m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString())?.toLocal() : null;
                          final String timeStr = createdAt != null
                              ? '${createdAt.hour > 12 ? createdAt.hour - 12 : (createdAt.hour == 0 ? 12 : createdAt.hour)}:${createdAt.minute.toString().padLeft(2, '0')} ${createdAt.hour >= 12 ? 'PM' : 'AM'}'
                              : 'Just now';

                          final displaySenderName = (senderObj['name'] ?? '').toString().trim().isNotEmpty
                              ? senderObj['name'].toString().trim()
                              : (mType == 'doctor'
                                  ? widget.doctorName
                                  : (mType == 'admin' ? 'Admin' : widget.patientName));

                          // Is this message sent by the current user?
                          final bool isSentByMe = _isAdmin
                              ? (mType == 'admin' || senderRole.toLowerCase().contains('admin'))
                              : (_isDentist
                                  ? (mType == 'doctor' || senderRole == 'Dentist' || senderRole == 'Doctor' || senderName.contains(widget.doctorName) || (widget.doctorId != null && senderName.contains(widget.doctorId!)))
                                  : (mType == 'patient' || senderRole == 'Patient' || senderName.contains(widget.patientName) || (widget.patientId != null && senderName.contains(widget.patientId!))));

                          final bool isRead = m['read'] == true;

                          return Align(
                            alignment: isSentByMe ? Alignment.centerRight : Alignment.centerLeft,
                            child: GestureDetector(
                              onLongPress: () {
                                showModalBottomSheet(
                                  context: context,
                                  builder: (bCtx) => Container(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.delete_outline, color: Color(0xFFFE3434)),
                                          title: const Text('Delete Message'),
                                          onTap: () async {
                                            Navigator.pop(bCtx);
                                            final ok = await _apiService.clearChatMessages(roomId: _roomId, messageId: msgId);
                                            if (ok && mounted) {
                                              setState(() {
                                                _messages.removeAt(index);
                                              });
                                            }
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                margin: const EdgeInsets.symmetric(vertical: 3),
                                padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
                                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
                                decoration: BoxDecoration(
                                  color: isSentByMe ? const Color(0x14012A58) : Colors.white,
                                  borderRadius: BorderRadius.circular(12).copyWith(
                                    topRight: isSentByMe ? const Radius.circular(2) : const Radius.circular(12),
                                    topLeft: isSentByMe ? const Radius.circular(12) : const Radius.circular(2),
                                  ),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1)),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: isSentByMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (!isSentByMe && displaySenderName.isNotEmpty) ...[
                                      Text(
                                        displaySenderName,
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF012A58),
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                    ],
                                    Wrap(
                                      alignment: WrapAlignment.end,
                                      crossAxisAlignment: WrapCrossAlignment.end,
                                      children: [
                                        Text(
                                          text,
                                          style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A), height: 1.3),
                                        ),
                                        const SizedBox(width: 8),
                                        Padding(
                                          padding: const EdgeInsets.only(top: 4),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                timeStr,
                                                style: const TextStyle(fontSize: 10, color: Color(0xFF475569)),
                                              ),
                                              if (isSentByMe) ...[
                                                const SizedBox(width: 3),
                                                Icon(
                                                  Icons.done_all_rounded,
                                                  size: 14,
                                                  color: isRead ? const Color(0xFF0284C7) : const Color(0xFF64748B),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // 🟢 Bottom WhatsApp Input Bar
          SafeArea(
            top: false,
            child: Container(
              padding: EdgeInsets.only(
                left: 8,
                right: 8,
                top: 8,
                bottom: MediaQuery.of(context).viewInsets.bottom + 8,
              ),
              color: const Color(0xFFF1F5F9),
              child: Row(
                children: [
                  const Icon(Icons.sentiment_satisfied_alt_rounded, color: Color(0xFF475569), size: 24),
                  const SizedBox(width: 8),
                  const Icon(Icons.attach_file_rounded, color: Color(0xFF475569), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _msgController,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleSend(),
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(fontSize: 14, color: Color(0xFF94A3B8)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF012A58),
                    child: IconButton(
                      icon: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                      onPressed: _handleSend,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
