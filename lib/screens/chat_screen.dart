import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:open_filex/open_filex.dart';

import '../models/blousab_message.dart';
import '../services/message_store.dart';
import '../services/community_store.dart';
import '../services/local_network_service.dart';
import '../services/bluetooth_classic_service.dart';

class ChatScreen extends StatefulWidget {
final String conversationId;
final String title;
final String currentUserId;
final String currentUserName;
final String? initialPeerAddress;
final bool connectionAlreadyEstablished;
final Future<void> Function(BlousabMessage message)? onSendMessage;

const ChatScreen({
super.key,
required this.conversationId,
required this.title,
required this.currentUserId,
required this.currentUserName,
this.initialPeerAddress,
this.connectionAlreadyEstablished = false,
this.onSendMessage,
});

@override
State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
final MessageStore _store = MessageStore();
final CommunityStore _communityStore = CommunityStore();
final BluetoothClassicService _bluetooth =
BluetoothClassicService.instance;

final TextEditingController _textController =
TextEditingController();
final ScrollController _scrollController = ScrollController();

final Set<String> _receivedIds = <String>{};

List<BlousabMessage> _messages = [];
List<BlousabDevice> _devices = [];

StreamSubscription<BlousabEvent>? _subscription;
StreamSubscription<BlousabEvent>? _lanSubscription;

String? _selectedAddress;
String _connectionStatus = 'غير متصل';
String _profileCoverPath = '';
String _connectionMode = 'bluetooth';

bool _loading = true;
bool _sending = false;
bool _working = false;
bool _isCommunityConversation = false;
double _messageFontSize = 16;
bool _showMessageTime = true;
bool _vibrateOnSend = true;
bool _compactBubbles = false;

@override
void initState() {
super.initState();
SharedPreferences.getInstance().then((prefs) {
  if (!mounted) return;
  setState(() {
    _profileCoverPath = prefs.getString('wasl_profile_cover') ?? '';
    _connectionMode = prefs.getString('blousab_connection_mode') ?? 'bluetooth';
    _messageFontSize = (prefs.getDouble('blousab_message_font_size') ?? 16).clamp(14, 22).toDouble();
    _showMessageTime = prefs.getBool('blousab_show_message_time') ?? true;
    _vibrateOnSend = prefs.getBool('blousab_vibrate_on_send') ?? true;
    _compactBubbles = prefs.getBool('blousab_compact_bubbles') ?? false;
  });
});
_selectedAddress = widget.initialPeerAddress;
_communityStore.findById(widget.conversationId).then((c) { if (mounted) setState(() => _isCommunityConversation = c != null); });
_loadMessages();
_listenToBluetooth();
_lanSubscription = LocalNetworkService.instance.events.listen(_handleBluetoothEvent);
_restoreLastConnection();
}

Future<void> _restoreLastConnection() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    if (widget.initialPeerAddress != null && widget.initialPeerAddress!.isNotEmpty) {
      await prefs.setString('blousab_last_device_${widget.conversationId}', widget.initialPeerAddress!);
      if (widget.connectionAlreadyEstablished) {
        if (mounted) setState(() {
          _selectedAddress = widget.initialPeerAddress;
          _connectionStatus = 'جاهز للمحادثة عبر البلوتوث';
        });
        return; // The invitation flow already established the RFCOMM connection.
      }
      try {
        await _bluetooth.connect(widget.initialPeerAddress!);
        if (mounted) setState(() { _selectedAddress = widget.initialPeerAddress; _connectionStatus = 'متصل عبر البلوتوث'; });
      } catch (_) {
        if (mounted) setState(() => _connectionStatus = 'تعذر الاتصال؛ استخدم زر البلوتوث لإعادة المحاولة');
      }
      return;
    }
    final address = prefs.getString('blousab_last_device_${widget.conversationId}');
    if (address == null || address.isEmpty) return;
    if (!await _bluetooth.isSupported() || !await _bluetooth.requestPermissions()) return;
    if (!await _bluetooth.isEnabled()) return;
    if (mounted) setState(() => _connectionStatus = 'جارٍ إعادة الاتصال بالجهاز المحفوظ...');
    await _bluetooth.connect(address);
    if (mounted) setState(() => _selectedAddress = address);
  } catch (_) {
    if (mounted) setState(() => _connectionStatus = 'غير متصل؛ يمكنك إعادة الاتصال من زر البلوتوث');
  }
}

Future<void> _loadMessages() async {
try {
final messages =
await _store.getMessages(widget.conversationId);

  if (!mounted) return;

  setState(() {
    _messages = messages;
    _receivedIds.addAll(messages.map((m) => m.id));
    _loading = false;
  });

  _scrollToBottom();
} catch (_) {
  if (!mounted) return;
  setState(() => _loading = false);
  _showNotice('تعذر تحميل سجل الرسائل.');
}

}

void _listenToBluetooth() {
_subscription = _bluetooth.events.listen(
_handleBluetoothEvent,
onError: (Object error) {
if (!mounted) return;
setState(() {
_connectionStatus = 'خطأ في أحداث البلوتوث';
});
},
);
}

void _handleBluetoothEvent(BlousabEvent event) {
if (!mounted) return;

switch (event.type) {
  case 'connected':
    setState(() {
      _selectedAddress = event.address ?? _selectedAddress;
      _connectionStatus =
          'متصل: ${event.name ?? 'جهاز'}';
    });
    if (event.address != null) { SharedPreferences.getInstance().then((p) => p.setString('blousab_last_device_${widget.conversationId}', event.address!)); }
    _showNotice('تم الاتصال بجهاز ${event.name ?? ''}');
    break;

  case 'disconnected':
    if (_selectedAddress == event.address) {
      setState(() {
        _selectedAddress = null;
        _connectionStatus = 'انقطع الاتصال';
      });
    }
    break;

  case 'message':
    final raw = event.message;
    if (raw != null) {
      _handleIncomingMessage(raw, event.address);
    }
    break;

  case 'connectionError':
  case 'serverError':
    setState(() => _connectionStatus = 'حدث خطأ في الاتصال');
    _showNotice(event.message ?? 'تعذر الاتصال بالبلوتوث.');
    break;

  case 'serverStarted':
    setState(() {
      _connectionStatus = 'جاهز لاستقبال الاتصالات';
    });
    break;

  case 'serverStopped':
    setState(() {
      _connectionStatus = 'الاستقبال متوقف';
    });
    break;
}

}

Future<void> _handleIncomingMessage(
String raw,
String? address,
) async {
try {
final dynamic decoded = jsonDecode(raw);

  if (decoded is! Map) return;

  final senderId = decoded['senderId']?.toString() ?? '';
  final senderName =
      decoded['senderName']?.toString() ?? 'مستخدم';
  final packetType = decoded['type']?.toString() ?? 'text';
  String text = decoded['text']?.toString() ?? '';
  String? attachmentPath;
  String? attachmentName;
  if (packetType == 'file') {
    attachmentName = decoded['fileName']?.toString() ?? 'ملف مستلم';
    final encoded = decoded['data']?.toString() ?? '';
    if (encoded.isEmpty || encoded.length > 6000000) return;
    final bytes = base64Decode(encoded);
    final dir = await getApplicationDocumentsDirectory();
    final safeName = attachmentName.replaceAll(RegExp(r'[^\w.\- ()\u0600-\u06FF]'), '_');
    final file = File('${dir.path}/received_${DateTime.now().millisecondsSinceEpoch}_$safeName');
    await file.writeAsBytes(bytes, flush: true);
    attachmentPath = file.path;
    text = '📎 $attachmentName';
  }
  final messageId = decoded['id']?.toString() ??
      '${DateTime.now().microsecondsSinceEpoch}_$senderId';

  final incomingConversation =
      decoded['conversationId']?.toString() ?? '';

  if ((text.trim().isEmpty && packetType != 'file') ||
      senderId.isEmpty ||
      senderId == widget.currentUserId) {
    return;
  }

  // لا تعرض رسائل محادثة مختلفة في هذه المحادثة.
  if (incomingConversation.isNotEmpty &&
      incomingConversation != widget.conversationId) {
    return;
  }

  final localCommunity = await _communityStore.findById(widget.conversationId);
  if (localCommunity != null) {
    final sender = localCommunity.members.where((member) => member.id == senderId).toList();
    if (sender.isEmpty || sender.first.status.name != 'approved') return;
  }

  if (_receivedIds.contains(messageId)) return;

  final message = BlousabMessage(
    id: messageId,
    conversationId: widget.conversationId,
    senderId: senderId,
    senderName: senderName,
    text: text,
    sentAt: DateTime.tryParse(
          decoded['sentAt']?.toString() ?? '',
        )?.toLocal() ??
        DateTime.now(),
    isMine: false,
    attachmentPath: attachmentPath,
    attachmentName: attachmentName,
  );

  _receivedIds.add(messageId);

  await _store.saveMessage(message);

  if (!mounted) return;

  setState(() {
    _messages.add(message);
    _selectedAddress ??= address;
  });

  _scrollToBottom();
} catch (_) {
  _showNotice('تعذر قراءة الرسالة المستلمة.');
}

}

Future<void> _prepareBluetooth() async {
if (_working) return;

setState(() => _working = true);

try {
  if (!await _bluetooth.isSupported()) {
    _showNotice('هذا الهاتف لا يدعم البلوتوث.');
    return;
  }

  final granted = await _bluetooth.requestPermissions();

  if (!granted) {
    _showNotice('امنح صلاحيات البلوتوث للتطبيق.');
    return;
  }

  if (!await _bluetooth.isEnabled()) {
    await _bluetooth.requestEnable();
    _showNotice('فعّل البلوتوث ثم اضغط الزر مرة أخرى.');
    return;
  }

  _showNotice('جارٍ البحث عن الأجهزة القريبة…');
  _devices = await _bluetooth.discoverNearbyDevices(
    timeout: const Duration(seconds: 8),
  );

  if (!mounted) return;

  await _showDevicePicker();
} on PlatformException catch (e) {
  _showNotice(e.message ?? 'تعذر تجهيز البلوتوث.');
} catch (e) {
  _showNotice('حدث خطأ أثناء تجهيز البلوتوث.');
} finally {
  if (mounted) setState(() => _working = false);
}

}

Future<void> _showDevicePicker() async {
if (!mounted) return;

final device = await showModalBottomSheet<BlousabDevice>(
  context: context,
  builder: (sheetContext) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _devices.isEmpty
            ? const Text(
                'لم يُعثر على أجهزة قريبة.\n'
                'اجعل هاتف الطرف الآخر مرئيًا من زر البلوتوث أو اقترن به من إعدادات Android.',
                textAlign: TextAlign.center,
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  const Text(
                    'اختر جهازًا قريبًا أو مقترنًا',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._devices.map(
                    (d) => ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: Text(d.name),
                      subtitle: Text(d.address),
                      onTap: () =>
                          Navigator.pop(sheetContext, d),
                    ),
                  ),
                ],
              ),
      ),
    );
  },
);

if (device == null || !mounted) return;

setState(() {
  _selectedAddress = device.address;
  _connectionStatus = 'جارٍ الاتصال بـ ${device.name}...';
});
final prefs = await SharedPreferences.getInstance();
await prefs.setString('blousab_last_device_${widget.conversationId}', device.address);

try {
  await _bluetooth.connect(device.address);
} on PlatformException catch (e) {
  if (mounted) {
    setState(() => _connectionStatus = 'فشل الاتصال');
  }
  _showNotice(e.message ?? 'تعذر الاتصال بالجهاز.');
} catch (_) {
  _showNotice('تعذر الاتصال بالجهاز.');
}

}

Future<void> _startListening() async {
if (_working) return;

setState(() => _working = true);

try {
  final supported = await _bluetooth.isSupported();

  if (!supported) {
    _showNotice('هذا الهاتف لا يدعم البلوتوث.');
    return;
  }

  final granted = await _bluetooth.requestPermissions();

  if (!granted) {
    _showNotice('امنح صلاحيات البلوتوث للتطبيق.');
    return;
  }

  if (!await _bluetooth.isEnabled()) {
    await _bluetooth.requestEnable();
    _showNotice('فعّل البلوتوث ثم حاول تشغيل الاستقبال.');
    return;
  }

  await _bluetooth.startServer();

  if (mounted) {
    setState(() {
      _connectionStatus = 'جارٍ تشغيل استقبال الرسائل...';
    });
  }
} on PlatformException catch (e) {
  _showNotice(e.message ?? 'تعذر تشغيل استقبال الرسائل.');
} catch (_) {
  _showNotice('حدث خطأ أثناء تشغيل الاستقبال.');
} finally {
  if (mounted) setState(() => _working = false);
}

}

Future<bool> _maySendToCurrentConversation() async {
  final community = await _communityStore.findById(widget.conversationId);
  if (community == null) return true;
  final member = community.members.where((item) => item.id == widget.currentUserId).toList();
  return member.isNotEmpty && member.first.status.name == 'approved';
}

Future<void> _broadcastGroupPayload(String payload) async {
  var sent = false;
  try {
    await _bluetooth.broadcastMessage(payload);
    sent = true;
  } catch (_) {}
  try {
    await LocalNetworkService.instance.broadcastMessage(payload);
    sent = true;
  } catch (_) {}
  if (!sent) {
    throw PlatformException(
      code: 'BROADCAST_FAILED',
      message: 'لا توجد أجهزة متصلة عبر البلوتوث أو الشبكة المحلية.',
    );
  }
}

Future<void> _sendMessage() async {
final text = _textController.text.trim();

if (text.isEmpty || _sending) return;
if (!await _maySendToCurrentConversation()) {
  _showNotice('لا يمكنك الإرسال لأن عضويتك غير مقبولة أو محظورة.');
  return;
}

final isCommunity = await _communityStore.findById(widget.conversationId) != null;
final prefs = await SharedPreferences.getInstance();
final wifiMode = prefs.getString('blousab_connection_mode') == 'wifi';
final address = _selectedAddress;

if (!isCommunity && !wifiMode && (address == null || address.isEmpty)) {
  _showNotice('اتصل بهاتف مقترن أولًا لإرسال الرسائل.');
  return;
}

setState(() => _sending = true);

final message = BlousabMessage(
  id: '${DateTime.now().microsecondsSinceEpoch}_${widget.currentUserId}',
  conversationId: widget.conversationId,
  senderId: widget.currentUserId,
  senderName: widget.currentUserName,
  text: text,
  sentAt: DateTime.now(),
  isMine: true,
);

try {
  final payload = jsonEncode({
    'type': 'chat',
    'hops': 0,
    'relay': isCommunity,
    'id': message.id,
    'conversationId': message.conversationId,
    'senderId': message.senderId,
    'senderName': message.senderName,
    'text': message.text,
    'sentAt': message.sentAt.toIso8601String(),
  });

  if (wifiMode) {
    await LocalNetworkService.instance.broadcastMessage(payload);
  } else if (isCommunity) {
    await _bluetooth.sendMessage(address: '*', message: payload);
  } else {
    await _bluetooth.sendMessage(address: address!, message: payload);
  }

  await _store.saveMessage(message);

  if (widget.onSendMessage != null) {
    await widget.onSendMessage!(message);
  }

  if (!mounted) return;

  _receivedIds.add(message.id);

  setState(() {
    _messages.add(message);
    _textController.clear();
  });

  _scrollToBottom();
  if (_vibrateOnSend) HapticFeedback.lightImpact();
} on PlatformException catch (e) {
  _showNotice(e.message ?? 'فشل إرسال الرسالة.');
} catch (e) {
  _showNotice('تعذر إرسال الرسالة. تحقق من الاتصال.');
} finally {
  if (mounted) setState(() => _sending = false);
}

}

Future<void> _sendFile() async {
  if (_sending) return;
  if (!await _maySendToCurrentConversation()) {
    _showNotice('لا يمكنك إرسال الملفات لأن عضويتك غير مقبولة أو محظورة.');
    return;
  }
  final isCommunity = await _communityStore.findById(widget.conversationId) != null;
  final prefs = await SharedPreferences.getInstance();
  final wifiMode = prefs.getString('blousab_connection_mode') == 'wifi';
  final address = _selectedAddress;
  if (!isCommunity && !wifiMode && (address == null || address.isEmpty)) {
    _showNotice('اتصل بجهاز مقترن أولًا لإرسال ملف.');
    return;
  }
  try {
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes ?? (picked.path != null ? await File(picked.path!).readAsBytes() : null);
    if (bytes == null || bytes.isEmpty) {
      _showNotice('تعذر قراءة الملف المحدد.');
      return;
    }
    if (bytes.length > 4 * 1024 * 1024) {
      _showNotice('حجم الملف أكبر من 4 ميغابايت. اختر ملفًا أصغر لضمان نقله عبر البلوتوث.');
      return;
    }
    setState(() => _sending = true);
    final id = '${DateTime.now().microsecondsSinceEpoch}_${widget.currentUserId}';
    final dir = await getApplicationDocumentsDirectory();
    final safeName = picked.name.replaceAll(RegExp(r'[^\w.\- ()\u0600-\u06FF]'), '_');
    final localFile = File('${dir.path}/sent_${DateTime.now().millisecondsSinceEpoch}_$safeName');
    await localFile.writeAsBytes(bytes, flush: true);
    final message = BlousabMessage(
      id: id,
      conversationId: widget.conversationId,
      senderId: widget.currentUserId,
      senderName: widget.currentUserName,
      text: '📎 ${picked.name}',
      sentAt: DateTime.now(),
      isMine: true,
      attachmentPath: localFile.path,
      attachmentName: picked.name,
    );
    final payload = jsonEncode({
      'type': 'file', 'hops': 0, 'relay': isCommunity,
      'id': id, 'conversationId': message.conversationId,
      'senderId': message.senderId, 'senderName': message.senderName,
      'sentAt': message.sentAt.toIso8601String(), 'fileName': picked.name,
      'data': base64Encode(bytes),
    });
    if (wifiMode) {
      await LocalNetworkService.instance.broadcastMessage(payload);
    } else if (isCommunity) {
      await _bluetooth.sendMessage(address: '*', message: payload);
    } else {
      await _bluetooth.sendMessage(address: address!, message: payload);
    }
    await _store.saveMessage(message);
    if (!mounted) return;
    _receivedIds.add(id);
    setState(() => _messages.add(message));
    _scrollToBottom();
    _showNotice('تم إرسال الملف عبر البلوتوث.');
  } on PlatformException catch (e) {
    _showNotice(e.message ?? 'تعذر إرسال الملف.');
  } catch (e) {
    _showNotice('تعذر إرسال الملف: $e');
  } finally {
    if (mounted) setState(() => _sending = false);
  }
}

Future<void> _openAttachment(BlousabMessage message) async {
  final path = message.attachmentPath;
  if (path == null || !File(path).existsSync()) {
    _showNotice('الملف غير موجود على هذا الجهاز.');
    return;
  }
  final result = await OpenFilex.open(path);
  if (result.type != ResultType.done) _showNotice('تعذر فتح الملف: ${result.message}');
}

void _scrollToBottom() {
WidgetsBinding.instance.addPostFrameCallback((_) {
  if (!_scrollController.hasClients) return;

  _scrollController.animateTo(
    _scrollController.position.maxScrollExtent,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );
});

}

void _showNotice(String text) {
if (!mounted) return;

ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

}

@override
void dispose() {
_subscription?.cancel();
_lanSubscription?.cancel();
_textController.dispose();
_scrollController.dispose();
super.dispose();
}

@override
Widget build(BuildContext context) {
return Scaffold(
appBar: AppBar(
title: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(widget.title),
Text(
_connectionStatus,
style: const TextStyle(fontSize: 12),
),
],
),
actions: [
IconButton(
  tooltip: 'مكالمة فيديو',
  onPressed: () => _showNotice('مكالمات الفيديو تحتاج إلى تنفيذ قناة صوت وصورة واختبارها بين هاتفين. الزر لا يبدأ بثًا حيًا في هذه النسخة.'),
  icon: const Icon(Icons.videocam_outlined),
),
IconButton(
tooltip: 'تشغيل استقبال الرسائل',
onPressed: _working ? null : _startListening,
icon: Icon(_connectionMode == 'wifi' ? Icons.wifi : Icons.bluetooth_searching),
),
IconButton(
tooltip: 'الاتصال بجهاز مقترن',
onPressed: _working ? null : _prepareBluetooth,
icon: Icon(_connectionMode == 'wifi' ? Icons.wifi : Icons.bluetooth_connected),
),
],
),
body: Column(
children: [
Expanded(
child: _loading
? const Center(child: CircularProgressIndicator())
: _messages.isEmpty
? const Center(
child: Text('لا توجد رسائل بعد. ابدأ المحادثة.'),
)
: ListView.builder(
controller: _scrollController,
padding: const EdgeInsets.all(12),
itemCount: _messages.length,
itemBuilder: (context, index) {
final message = _messages[index];
final mine = message.isMine;

                      return Align(
                        alignment: mine
                            ? AlignmentDirectional.centerEnd
                            : AlignmentDirectional.centerStart,
                        child: Container(
                          constraints: BoxConstraints(
                            maxWidth:
                                MediaQuery.of(context).size.width * 0.8,
                          ),
                          margin: const EdgeInsets.symmetric(
                            vertical: 4,
                          ),
                          padding: EdgeInsets.all(_compactBubbles ? 8 : 12),
                          decoration: BoxDecoration(
                            color: mine
                                ? Theme.of(context)
                                    .colorScheme
                                    .primaryContainer
                                : Theme.of(context)
                                    .colorScheme
                                    .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              if (!mine && _isCommunityConversation)
                                Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    message.senderName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ),
                              if (message.attachmentPath != null &&
                                  RegExp(r'.*\.(png|jpe?g|gif|webp|bmp)$', caseSensitive: false).hasMatch(message.attachmentName ?? ''))
                                GestureDetector(
                                  onTap: () => _openAttachment(message),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.file(File(message.attachmentPath!), width: 220, fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => Text(message.attachmentName ?? 'صورة')),
                                  ),
                                )
                              else if (message.attachmentPath != null)
                                InkWell(
                                  onTap: () => _openAttachment(message),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    const Icon(Icons.attach_file),
                                    const SizedBox(width: 6),
                                    Flexible(child: Text(message.attachmentName ?? message.text)),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.open_in_new, size: 16),
                                  ]),
                                )
                              else Text(message.text, style: TextStyle(fontSize: _messageFontSize)),
                              if (_showMessageTime) const SizedBox(height: 4),
                              if (_showMessageTime) Text(
                                '${message.sentAt.toLocal().hour.toString().padLeft(2, '0')}:'
                                '${message.sentAt.toLocal().minute.toString().padLeft(2, '0')}',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
          child: Row(
            children: [
              IconButton(
                tooltip: 'إرسال ملف أو صورة',
                onPressed: _sending ? null : _sendFile,
                icon: const Icon(Icons.attach_file),
              ),
              Expanded(
                child: TextField(
                  controller: _textController,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _sendMessage(),
                  decoration: const InputDecoration(
                    hintText: 'اكتب رسالتك...',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                tooltip: 'إرسال',
                onPressed: _sending ? null : _sendMessage,
                icon: _sending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.send),
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