import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/api_service.dart';
import '../services/patient_problem_service.dart';

/// Authentic WhatsApp-Themed Real-Time 1-on-1 Chat Modal
/// Supports instant optimistic messaging, 2-second auto-polling, and real-time sync.
class WhatsAppChatModal extends StatefulWidget {
  final String patientName;
  final String doctorName;
  final String currentUserRole; // 'Patient' | 'Dentist' | 'Admin'
  final String? patientId;
  final String? doctorId;

  const WhatsAppChatModal({
    super.key,
    required this.patientName,
    required this.doctorName,
    required this.currentUserRole,
    this.patientId,
    this.doctorId,
  });

  static void show(
    BuildContext context, {
    required String patientName,
    required String doctorName,
    required String currentUserRole,
    String? patientId,
    String? doctorId,
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
      ),
    );
  }

  @override
  State<WhatsAppChatModal> createState() => _WhatsAppChatModalState();
}

class _WhatsAppChatModalState extends State<WhatsAppChatModal> {
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ApiService _apiService = ApiService();
  final PatientProblemService _problemService = PatientProblemService();

  late String _roomId;
  List<dynamic> _messages = [];
  bool _isLoading = true;
  Timer? _pollTimer;

  bool get _isDentist => widget.currentUserRole.toLowerCase().contains('dentist') || widget.currentUserRole.toLowerCase().contains('doctor');

  String get _counterpartName => _isDentist 
      ? (widget.patientName.isNotEmpty ? widget.patientName : 'Patient')
      : (widget.doctorName.isNotEmpty ? widget.doctorName : 'Doctor');

  @override
  void initState() {
    super.initState();
    _roomId = ApiService.getChatRoomId(
      patientIdOrName: widget.patientName.isNotEmpty ? widget.patientName : (widget.patientId ?? 'PATIENT'),
      dentistIdOrName: widget.doctorName.isNotEmpty ? widget.doctorName : (widget.doctorId ?? 'DOCTOR'),
    );

    _loadMessages();

    // ⚡ Real-Time 2-second background refresh for instant WhatsApp-like synchronization
    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _pollMessages();
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      final msgs = await _apiService.fetchChatMessages(roomId: _roomId);
      if (mounted) {
        _reconcileMessages(msgs);
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _pollMessages() async {
    try {
      final msgs = await _apiService.fetchChatMessages(roomId: _roomId);
      if (mounted) {
        _reconcileMessages(msgs);
      }
    } catch (_) {}
  }

  void _reconcileMessages(List<dynamic> serverMsgs) {
    if (!mounted) return;

    // Retain any pending optimistic messages not yet reflected in serverMsgs
    final unconfirmed = _messages.where((m) {
      final id = (m['id'] ?? '').toString();
      if (!id.startsWith('temp_')) return false;
      final text = (m['message'] ?? '').toString();
      final type = (m['type'] ?? '').toString();
      return !serverMsgs.any((sm) =>
          (sm['message'] ?? '').toString() == text &&
          (sm['type'] ?? '').toString() == type);
    }).toList();

    final merged = [...serverMsgs, ...unconfirmed];
    if (merged.length != _messages.length || (serverMsgs.isNotEmpty && _messages.isEmpty)) {
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
    if (text.isEmpty) return;

    _msgController.clear();

    final authUser = Supabase.instance.client.auth.currentUser;
    final currentUserId = authUser?.id ?? '';

    final effectiveSenderId = _isDentist
        ? (widget.doctorId?.isNotEmpty == true ? widget.doctorId! : (currentUserId.isNotEmpty ? currentUserId : widget.doctorName))
        : (widget.patientId?.isNotEmpty == true ? widget.patientId! : (currentUserId.isNotEmpty ? currentUserId : widget.patientName));

    final msgType = _isDentist ? 'doctor' : 'patient';

    // 🟢 1. Instant Optimistic UI Update (Guaranteed to stay in list)
    final optimisticMsg = {
      'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
      'room_id': _roomId,
      'sender_id': effectiveSenderId,
      'message': text,
      'type': msgType,
      'created_at': DateTime.now().toIso8601String(),
      'read': false,
    };

    setState(() {
      _messages.add(optimisticMsg);
    });
    _scrollToBottom();

    // 🟢 2. Send to Supabase & Backend API
    try {
      await _apiService.sendMessage(
        senderId: effectiveSenderId,
        message: text,
        roomId: _roomId,
        type: msgType,
        senderRole: _isDentist ? 'Dentist' : 'Patient',
        receiverId: _isDentist ? widget.patientId : widget.doctorId,
      );

      // Notification
      _problemService.addNotification(
        recipientRole: _isDentist ? 'Patient' : 'Dentist',
        recipientId: _counterpartName,
        title: _isDentist ? '💬 Doctor Reply' : '💬 New Patient Message',
        message: '${_isDentist ? widget.doctorName : widget.patientName}: "$text"',
      );

      // Fetch and reconcile
      final updated = await _apiService.fetchChatMessages(roomId: _roomId);
      if (mounted) {
        _reconcileMessages(updated);
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarLetter = _counterpartName.replaceAll('Dr. ', '').replaceAll('Dr.', '').trim();
    final letter = avatarLetter.isNotEmpty ? avatarLetter[0].toUpperCase() : 'U';

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: const BoxDecoration(
        color: Color(0xFFE5DDD5), // Authentic WhatsApp Doodle Beige
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 🟢 Authentic WhatsApp Teal Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF075E54), // Authentic WhatsApp Teal
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
                            color: const Color(0xFF25D366),
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFF075E54), width: 1.5),
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
                        const Text(
                          'online',
                          style: TextStyle(fontSize: 11, color: Color(0xFFB9E5E1), fontWeight: FontWeight.w400),
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
                              Icon(Icons.delete_forever_rounded, color: Color(0xFFEF4444)),
                              SizedBox(width: 8),
                              Text('Clear Chat History?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          content: const Text('This will permanently delete all messages in this conversation. Are you sure?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(confirmCtx), child: const Text('Cancel')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
                              onPressed: () async {
                                Navigator.pop(confirmCtx);
                                final ok = await _apiService.clearChatMessages(roomId: _roomId);
                                if (ok && mounted) {
                                  setState(() => _messages = []);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('🗑️ Chat history cleared!'), backgroundColor: Color(0xFF10B981)),
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

          // 💬 Live Chat Thread Area
          Expanded(
            child: _isLoading && _messages.isEmpty
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF075E54)))
                : _messages.isEmpty
                    ? Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF5C4),
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 4)],
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_rounded, size: 14, color: Color(0xFF856404)),
                              SizedBox(width: 6),
                              Text(
                                'Messages are end-to-end encrypted.',
                                style: TextStyle(fontSize: 11, color: Color(0xFF856404), fontWeight: FontWeight.w500),
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

                          final createdAt = m['created_at'] != null ? DateTime.tryParse(m['created_at'].toString()) : null;
                          final String timeStr = createdAt != null
                              ? '${createdAt.hour > 12 ? createdAt.hour - 12 : (createdAt.hour == 0 ? 12 : createdAt.hour)}:${createdAt.minute.toString().padLeft(2, '0')} ${createdAt.hour >= 12 ? 'PM' : 'AM'}'
                              : 'Just now';

                          // Is this message sent by the current user?
                          final bool isSentByMe = _isDentist
                              ? (mType == 'doctor' || senderRole == 'Dentist' || senderName.contains(widget.doctorName) || (widget.doctorId != null && senderName.contains(widget.doctorId!)))
                              : (mType == 'patient' || senderRole == 'Patient' || senderName.contains(widget.patientName) || (widget.patientId != null && senderName.contains(widget.patientId!)));

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
                                          leading: const Icon(Icons.delete_outline, color: Colors.red),
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
                                  color: isSentByMe ? const Color(0xFFDCF8C6) : Colors.white,
                                  borderRadius: BorderRadius.circular(12).copyWith(
                                    topRight: isSentByMe ? const Radius.circular(2) : const Radius.circular(12),
                                    topLeft: isSentByMe ? const Radius.circular(12) : const Radius.circular(2),
                                  ),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 3, offset: const Offset(0, 1)),
                                  ],
                                ),
                                child: Wrap(
                                  alignment: WrapAlignment.end,
                                  crossAxisAlignment: WrapCrossAlignment.end,
                                  children: [
                                    Text(
                                      text,
                                      style: const TextStyle(fontSize: 14, color: Color(0xFF111B21), height: 1.3),
                                    ),
                                    const SizedBox(width: 8),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            timeStr,
                                            style: const TextStyle(fontSize: 10, color: Color(0xFF667781)),
                                          ),
                                          if (isSentByMe) ...[
                                            const SizedBox(width: 3),
                                            const Icon(Icons.done_all_rounded, size: 14, color: Color(0xFF34B7F1)),
                                          ],
                                        ],
                                      ),
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
              color: const Color(0xFFF0F2F5),
              child: Row(
                children: [
                  const Icon(Icons.sentiment_satisfied_alt_rounded, color: Color(0xFF54656F), size: 24),
                  const SizedBox(width: 8),
                  const Icon(Icons.attach_file_rounded, color: Color(0xFF54656F), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: TextField(
                        controller: _msgController,
                        style: const TextStyle(fontSize: 14, color: Color(0xFF111B21)),
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _handleSend(),
                        decoration: const InputDecoration(
                          hintText: 'Message',
                          hintStyle: TextStyle(fontSize: 14, color: Color(0xFF8696A0)),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF075E54),
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
