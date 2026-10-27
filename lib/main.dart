import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'screens/communities_screen.dart';
import 'services/bluetooth_classic_service.dart';
import 'services/local_network_service.dart';

const String supportUrl = 'https://wsend.co/967737414884';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BlousabApp());
}

class BlousabApp extends StatelessWidget {
  const BlousabApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'بلوساب',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF128C7E)),
        useMaterial3: true,
        fontFamily: 'sans-serif',
        appBarTheme: const AppBarTheme(centerTitle: false),
      ),
      home: const BluetoothGate(),
    );
  }
}

class BluetoothGate extends StatefulWidget {
  const BluetoothGate({super.key});

  @override
  State<BluetoothGate> createState() => _BluetoothGateState();
}

class _BluetoothGateState extends State<BluetoothGate> {
  final BluetoothClassicService _bluetooth = BluetoothClassicService.instance;
  bool _checking = true;
  bool _supported = false;
  bool _enabled = false;
  bool _busy = false;
  String _status = 'جارٍ التحقق من البلوتوث…';

  @override
  void initState() {
    super.initState();
    _checkBluetooth();
  }

  Future<void> _checkBluetooth() async {
    if (mounted) setState(() { _checking = true; });
    try {
      final supported = await _bluetooth.isSupported();
      if (!supported) {
        if (mounted) setState(() {
          _supported = false;
          _enabled = false;
          _status = 'هذا الهاتف لا يدعم Bluetooth Classic.';
          _checking = false;
        });
        return;
      }
      final permissions = await _bluetooth.requestPermissions();
      if (!permissions) {
        if (mounted) setState(() {
          _supported = true;
          _enabled = false;
          _status = 'يلزم السماح بصلاحيات البلوتوث للمتابعة.';
          _checking = false;
        });
        return;
      }
      final enabled = await _bluetooth.isEnabled();
      if (!mounted) return;
      setState(() {
        _supported = true;
        _enabled = enabled;
        _status = enabled
            ? 'البلوتوث جاهز. يمكنك فتح بلوساب.'
            : 'شغّل البلوتوث للمتابعة إلى التطبيق.';
        _checking = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _status = 'تعذر التحقق من البلوتوث. تحقق من الصلاحيات ثم أعد المحاولة.';
        _checking = false;
      });
    }
  }

  Future<void> _enableBluetooth() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      if (!await _bluetooth.requestPermissions()) {
        _notice('لم تُمنح صلاحيات البلوتوث.');
        return;
      }
      if (!await _bluetooth.isEnabled()) {
        await _bluetooth.requestEnable();
        _notice('وافق على تشغيل البلوتوث في نافذة Android، ثم اضغط «إعادة التحقق».');
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await _checkBluetooth();
    } catch (e) {
      _notice('تعذر تشغيل البلوتوث: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    // Do not block the whole app when Bluetooth is disabled: Wi-Fi mode and settings must remain accessible.
    return const BlousabShell();

    /* Legacy Bluetooth gate UI retained below for reference.
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(Icons.bluetooth, size: 54,
                      color: Theme.of(context).colorScheme.onPrimaryContainer),
                  ),
                  const SizedBox(height: 24),
                  Text('بلوساب', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  const Text('تواصل محلي عبر Bluetooth Classic', textAlign: TextAlign.center),
                  const SizedBox(height: 18),
                  Text(_status, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  if (_checking || _busy) const CircularProgressIndicator(),
                  if (!_checking && !_enabled) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: _supported ? _enableBluetooth : null,
                        icon: const Icon(Icons.bluetooth_searching),
                        label: const Text('تشغيل البلوتوث'),
                      ),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _checkBluetooth,
                      child: const Text('إعادة التحقق'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    'لن تظهر واجهة المحادثات حتى يتم تفعيل البلوتوث.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    */
  }
}

class BlousabShell extends StatefulWidget {
  const BlousabShell({super.key});

  @override
  State<BlousabShell> createState() => _BlousabShellState();
}

class _BlousabShellState extends State<BlousabShell> {
  String _userName = 'مستخدم بلوساب';
  String _background = 'افتراضي';
  String _chatWallpaper = 'mint';
  String _profilePhotoPath = ''; // صورة الملف الشخصي 
  bool _lanEnabled = true;
  String _connectionMode = 'bluetooth';
  double _messageFontSize = 16;
  bool _showMessageTime = true;
  bool _vibrateOnSend = true;
  bool _compactBubbles = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _startBluetoothListener();
  }

  Future<void> _startBluetoothListener() async {
    try {
      await BluetoothClassicService.instance.startServer();
    } catch (_) {
      // The user can start listening from the Bluetooth action if Android
      // has just returned from the system permission/enable dialog.
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('wasl_user_name') ?? 'مستخدم بلوساب';
      _background = prefs.getString('wasl_background') ?? 'افتراضي';
      _chatWallpaper = prefs.getString('wasl_chat_wallpaper') ?? 'mint';
      _profilePhotoPath = prefs.getString('wasl_profile_photo') ?? '';
      _lanEnabled = prefs.getBool('blousab_lan_enabled') ?? true;
      _connectionMode = prefs.getString('blousab_connection_mode') ?? 'bluetooth';
      _messageFontSize = (prefs.getDouble('blousab_message_font_size') ?? 16).clamp(14, 22).toDouble();
      _showMessageTime = prefs.getBool('blousab_show_message_time') ?? true;
      _vibrateOnSend = prefs.getBool('blousab_vibrate_on_send') ?? true;
      _compactBubbles = prefs.getBool('blousab_compact_bubbles') ?? false;
    });
    if (_lanEnabled || _connectionMode == 'wifi') {
      final id = prefs.getString('wasl_user_id') ?? 'blousab-user';
      try { await LocalNetworkService.instance.start(userId: id, userName: _userName); } catch (_) {}
    }
  }

  Future<String?> _pickAndStoreProfilePhoto() async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 88,
        maxWidth: 1200,
      );
      if (picked == null) return null;
      // Gallery providers may return temporary/cache paths. Copy the image
      // into the app's documents directory so the profile photo persists.
      final directory = await getApplicationDocumentsDirectory();
      final profileDirectory = Directory('${directory.path}/profile');
      if (!await profileDirectory.exists()) {
        await profileDirectory.create(recursive: true);
      }
      final extension = picked.path.contains('.')
          ? picked.path.substring(picked.path.lastIndexOf('.'))
          : '.jpg';
      final destination = File(
        '${profileDirectory.path}/profile_photo${extension.toLowerCase()}',
      );
      if (await destination.exists()) await destination.delete();
      await File(picked.path).copy(destination.path);
      return destination.path;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر اختيار الصورة. تحقق من صلاحية الوصول للصور ثم حاول مجددًا.')),
        );
      }
      return null;
    }
  }

  Future<void> _openSettings() async {
    final nameController = TextEditingController(text: _userName);
    String selectedBackground = _background;
    String selectedWallpaper = _chatWallpaper;
    String selectedPhotoPath = _profilePhotoPath;
    bool selectedLan = _lanEnabled;
    String selectedMode = _connectionMode;
    double selectedFontSize = _messageFontSize;
    bool selectedShowTime = _showMessageTime;
    bool selectedVibrate = _vibrateOnSend;
    bool selectedCompact = _compactBubbles;
    final result = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          insetPadding: EdgeInsets.zero,
          constraints: const BoxConstraints.expand(),
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
          elevation: 0,
          backgroundColor: Theme.of(context).colorScheme.surface,
          titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          title: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.settings_outlined, color: Theme.of(context).colorScheme.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('الإعدادات', style: TextStyle(fontWeight: FontWeight.bold))),
            IconButton(
              tooltip: 'إغلاق الإعدادات',
              onPressed: () => Navigator.pop(dialogContext),
              icon: const Icon(Icons.close),
            ),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.45),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(children: [
                    GestureDetector(
                      onTap: () async {
                        final path = await _pickAndStoreProfilePhoto();
                        if (path != null) setDialogState(() => selectedPhotoPath = path);
                      },
                      child: Stack(alignment: Alignment.bottomRight, children: [
                        CircleAvatar(
                          radius: 43,
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                          backgroundImage: selectedPhotoPath.isNotEmpty && File(selectedPhotoPath).existsSync() ? FileImage(File(selectedPhotoPath)) : null,
                          child: selectedPhotoPath.isEmpty || !File(selectedPhotoPath).existsSync() ? const Icon(Icons.person, size: 48) : null,
                        ),
                        CircleAvatar(radius: 14, child: const Icon(Icons.camera_alt, size: 16)),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    Text(nameController.text.trim().isEmpty ? 'مستخدم بلوساب' : nameController.text.trim(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(height: 3),
                    Text('اضغط على الصورة لتغييرها', style: Theme.of(context).textTheme.bodySmall),
                    if (selectedPhotoPath.isNotEmpty)
                      TextButton.icon(onPressed: () => setDialogState(() => selectedPhotoPath = ''), icon: const Icon(Icons.delete_outline), label: const Text('إزالة الصورة')),
                  ]),
                ),
                TextField(
                  controller: nameController,
                  maxLength: 40,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedBackground,
                  decoration: const InputDecoration(
                    labelText: 'مظهر التطبيق',
                    prefixIcon: Icon(Icons.palette_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'افتراضي', child: Text('افتراضي')),
                    DropdownMenuItem(value: 'فاتح', child: Text('فاتح')),
                    DropdownMenuItem(value: 'داكن', child: Text('داكن')),
                  ],
                  onChanged: (value) {
                    if (value != null) setDialogState(() => selectedBackground = value);
                  },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedWallpaper,
                  decoration: const InputDecoration(
                    labelText: 'خلفية المحادثة',
                    prefixIcon: Icon(Icons.wallpaper_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'mint', child: Text('أخضر هادئ')),
                    DropdownMenuItem(value: 'cream', child: Text('كريمي')),
                    DropdownMenuItem(value: 'plain', child: Text('أبيض بسيط')),
                    DropdownMenuItem(value: 'night', child: Text('داكن')),
                  ],
                  onChanged: (value) { if (value != null) setDialogState(() => selectedWallpaper = value); },
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedMode,
                  decoration: const InputDecoration(
                    labelText: 'طريقة الاتصال الأساسية',
                    prefixIcon: Icon(Icons.compare_arrows),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'bluetooth', child: Text('Bluetooth Classic')),
                    DropdownMenuItem(value: 'wifi', child: Text('Wi-Fi عبر نقطة اتصال')),
                  ],
                  onChanged: (value) { if (value != null) setDialogState(() => selectedMode = value); },
                ),
                if (selectedMode == 'wifi')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('شغّل نقطة الاتصال من إعدادات Android في الهاتف المنشئ، ثم صِل الهاتف الآخر بها. يجب أن يكون الهاتفان على الشبكة نفسها. لا يستطيع التطبيق تشغيل نقطة الاتصال تلقائيًا على كل الأجهزة.', style: TextStyle(fontSize: 12)),
                  ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Row(children: [Icon(Icons.chat_bubble_outline), SizedBox(width: 8), Text('تخصيص المحادثات', style: TextStyle(fontWeight: FontWeight.bold))]),
                      const SizedBox(height: 8),
                      Row(children: [const Expanded(child: Text('حجم نص الرسائل')), Text('${selectedFontSize.round()}')]),
                      Slider(value: selectedFontSize, min: 14, max: 22, divisions: 8, label: '${selectedFontSize.round()}', onChanged: (value) => setDialogState(() => selectedFontSize = value)),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('إظهار وقت الرسالة'), subtitle: const Text('عرض وقت الإرسال أسفل كل رسالة'), value: selectedShowTime, onChanged: (value) => setDialogState(() => selectedShowTime = value)),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('فقاعات مضغوطة'), subtitle: const Text('عرض رسائل أكثر على الشاشة'), value: selectedCompact, onChanged: (value) => setDialogState(() => selectedCompact = value)),
                      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('اهتزاز خفيف عند الإرسال'), subtitle: const Text('اهتزاز محلي عند إرسال الرسالة بنجاح'), value: selectedVibrate, onChanged: (value) => setDialogState(() => selectedVibrate = value)),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: selectedLan,
                  title: const Text('استخدام الشبكة المحلية Wi-Fi'),
                  subtitle: const Text('لإرسال رسائل المجتمعات إلى الأجهزة على شبكة Wi-Fi نفسها.'),
                  onChanged: (value) { if (value != null) setDialogState(() => selectedLan = value); },
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(children: [
                    const ListTile(
                      leading: Icon(Icons.account_circle_outlined),
                      title: Text('الملف الشخصي'),
                      subtitle: Text('صورة الحساب منفصلة عن خلفية المحادثة'),
                    ),
                    ListTile(
                      leading: const Icon(Icons.photo_library_outlined),
                      title: const Text('اختيار صورة من المعرض'),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () async {
                        final path = await _pickAndStoreProfilePhoto();
                        if (path != null) setDialogState(() => selectedPhotoPath = path);
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 8),
                const SizedBox(height: 8),
                const Text(
                  'تُحفظ هذه الإعدادات على هذا الهاتف. لا تُزامَن تلقائيًا مع الأجهزة الأخرى.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext),
                icon: const Icon(Icons.close),
                label: const Text('إلغاء'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              )),
              const SizedBox(width: 12),
              Expanded(child: FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, {
                  'name': nameController.text.trim(),
                  'background': selectedBackground,
                  'wallpaper': selectedWallpaper,
                  'photoPath': selectedPhotoPath,
                  'lanEnabled': selectedLan,
                  'connectionMode': selectedMode,
                  'messageFontSize': selectedFontSize,
                  'showMessageTime': selectedShowTime,
                  'vibrateOnSend': selectedVibrate,
                  'compactBubbles': selectedCompact,
                }),
                icon: const Icon(Icons.save_outlined),
                label: const Text('حفظ التغييرات'),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              )),
            ]),
          ],
        ),
      ),
    );
    nameController.dispose();
    if (result == null) return;
    final enteredName = (result['name'] as String? ?? '').trim();
    final cleanName = enteredName.isEmpty ? 'مستخدم بلوساب' : enteredName;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('wasl_user_name', cleanName);
    await prefs.setString('wasl_background', result['background'] as String);
    await prefs.setString('wasl_chat_wallpaper', result['wallpaper'] as String? ?? 'mint');
    final photoPath = result['photoPath'] as String? ?? '';
    if (photoPath.isEmpty) { await prefs.remove('wasl_profile_photo'); } else { await prefs.setString('wasl_profile_photo', photoPath); }
    final lanEnabled = result['lanEnabled'] as bool? ?? true;
    await prefs.setBool('blousab_lan_enabled', lanEnabled);
    final connectionMode = result['connectionMode'] as String? ?? 'bluetooth';
    await prefs.setString('blousab_connection_mode', connectionMode);
    final messageFontSize = (result['messageFontSize'] as double? ?? 16).clamp(14, 22).toDouble();
    final showMessageTime = result['showMessageTime'] as bool? ?? true;
    final vibrateOnSend = result['vibrateOnSend'] as bool? ?? true;
    final compactBubbles = result['compactBubbles'] as bool? ?? false;
    await prefs.setDouble('blousab_message_font_size', messageFontSize);
    await prefs.setBool('blousab_show_message_time', showMessageTime);
    await prefs.setBool('blousab_vibrate_on_send', vibrateOnSend);
    await prefs.setBool('blousab_compact_bubbles', compactBubbles);
    final userId = prefs.getString('wasl_user_id') ?? 'blousab-user';
    if (lanEnabled || connectionMode == 'wifi') {
      try {
        await LocalNetworkService.instance.start(userId: userId, userName: cleanName);
      } catch (_) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تشغيل الشبكة المحلية. تحقق من اتصال Wi-Fi.')));
      }
    } else {
      await LocalNetworkService.instance.stop();
    }
    if (!mounted) return;
    setState(() {
      _userName = cleanName;
      _background = result['background'] as String;
      _chatWallpaper = result['wallpaper'] as String? ?? 'mint';
      _profilePhotoPath = photoPath;
      _lanEnabled = lanEnabled;
      _connectionMode = connectionMode;
      _messageFontSize = messageFontSize;
      _showMessageTime = showMessageTime;
      _vibrateOnSend = vibrateOnSend;
      _compactBubbles = compactBubbles;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(connectionMode == 'wifi' ? 'تم حفظ الإعدادات. تأكد من اتصال الهاتفين بالشبكة نفسها.' : 'تم حفظ الإعدادات على هذا الهاتف.')));
  }

  Future<void> _openSupport() async {
    // Try the WhatsApp app first, then its official HTTPS deep link.
    final targets = <Uri>[
      Uri.parse('whatsapp://send?phone=967737414884'),
      Uri.parse('https://wa.me/967737414884'),
      Uri.parse('https://api.whatsapp.com/send?phone=967737414884'),
      Uri.parse(supportUrl),
    ];
    for (final uri in targets) {
      try {
        final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (opened) return;
      } catch (_) {
        // Continue to the next compatible WhatsApp link.
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح واتساب. ثبّت التطبيق أو تأكد من اتصال الإنترنت.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = _background == 'داكن' ? Brightness.dark : Brightness.light;
    return Theme(
      data: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF128C7E),
          brightness: brightness,
        ),
        useMaterial3: true,
        fontFamily: 'sans-serif',
      ),
      child: Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.all(7),
          child: CircleAvatar(
            backgroundImage: _profilePhotoPath.isNotEmpty && File(_profilePhotoPath).existsSync() ? FileImage(File(_profilePhotoPath)) : null,
            child: _profilePhotoPath.isEmpty || !File(_profilePhotoPath).existsSync() ? const Icon(Icons.person_outline) : null,
          ),
        ),
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('بلوساب'), Text(_connectionMode == 'wifi' ? 'الاتصال: Wi-Fi محلي' : 'الاتصال: Bluetooth Classic', style: const TextStyle(fontSize: 11))]),
        actions: [
          IconButton(
            tooltip: 'الحساب والإعدادات',
            onPressed: _openSettings,
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: 'التواصل مع الدعم عبر واتساب',
            onPressed: _openSupport,
            icon: const Icon(Icons.support_agent),
          ),
        ],
      ),
      body: const CommunitiesScreen(),
      floatingActionButton: FloatingActionButton.small(
        tooltip: _connectionMode == 'wifi' ? 'وضع الاتصال عبر Wi-Fi' : 'استقبال البلوتوث وإظهار الهاتف للأجهزة القريبة',
        onPressed: () async {
          if (_connectionMode == 'wifi') {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('وضع Wi-Fi محدد. تأكد من اتصال الهواتف بالشبكة نفسها.')));
            return;
          }
          final service = BluetoothClassicService.instance;
          try {
            final enabled = await service.isEnabled();
            if (!enabled) {
              await service.requestEnable();
            } else {
              await service.startServer();
              await service.requestDiscoverable();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('بدأ استقبال البلوتوث. وافق على جعل الهاتف مرئيًا للأجهزة القريبة لمدة 5 دقائق للانضمام الأول.')),
                );
              }
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('تعذر تشغيل استقبال البلوتوث: $e')),
              );
            }
          }
        },
        child: Icon(_connectionMode == 'wifi' ? Icons.wifi : Icons.bluetooth_searching),
      ),
      ),
    );
  }
}