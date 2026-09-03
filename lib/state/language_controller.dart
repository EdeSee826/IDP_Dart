import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final languageControllerProvider =
    StateNotifierProvider<LanguageController, String>((ref) {
  return LanguageController();
});

final appStringsProvider = Provider<AppStrings>((ref) {
  final language = ref.watch(languageControllerProvider);
  return AppStrings(language);
});

class LanguageController extends StateNotifier<String> {
  LanguageController() : super('English') {
    loadLanguage();
  }

  static const languageKey = 'settings.language';
  static const supportedLanguages = ['English', 'Malay', 'Chinese'];

  Future<void> loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(languageKey);
    if (saved != null && supportedLanguages.contains(saved)) {
      state = saved;
    }
  }

  Future<void> setLanguage(String language) async {
    if (!supportedLanguages.contains(language)) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(languageKey, language);
    state = language;
  }
}

class AppStrings {
  const AppStrings(this.language);

  final String language;

  static const Map<String, Map<String, String>> _translations = {
    'Malay': {
      'PICC Care Companion': 'Teman Penjagaan PICC',
      'Settings': 'Tetapan',
      'Logout': 'Log keluar',
      'Dashboard': 'Papan pemuka',
      'Guide': 'Panduan',
      'Event Log': 'Log Peristiwa',
      'Language': 'Bahasa',
      'Choose the language used by the application.':
          'Pilih bahasa yang digunakan oleh aplikasi.',
      'Application language': 'Bahasa aplikasi',
      'English': 'Inggeris',
      'Malay': 'Bahasa Melayu',
      'Chinese': 'Bahasa Cina',
      'Calibration': 'Kalibrasi',
      'Replace your original static neutral calibration reading.':
          'Gantikan bacaan kalibrasi neutral statik asal anda.',
      'Your next sensor connection will perform static neutral calibration and save the result as the new baseline.':
          'Sambungan sensor seterusnya akan menjalankan kalibrasi neutral statik dan menyimpan keputusan sebagai asas baharu.',
      'Perform new baseline calibration': 'Buat kalibrasi asas baharu',
      'Overwrite baseline calibration?': 'Ganti kalibrasi asas?',
      'Cancel': 'Batal',
      'Overwrite baseline': 'Ganti asas',
      'Ready. Connect the sensors to record the new baseline calibration.':
          'Sedia. Sambungkan sensor untuk merekod kalibrasi asas baharu.',
      'Data privacy': 'Privasi data',
      'Control whether approved family members can track your PICC status.':
          'Kawal sama ada ahli keluarga yang diluluskan boleh menjejaki status PICC anda.',
      'Allow family access': 'Benarkan akses keluarga',
      'Family tracking access is enabled.':
          'Akses penjejakan keluarga diaktifkan.',
      'Only you can view your status.': 'Hanya anda boleh melihat status anda.',
      'Family email address': 'Alamat e-mel keluarga',
      'This email will be allowed to view your PICC status.':
          'E-mel ini akan dibenarkan melihat status PICC anda.',
      'Enter a valid family email address.':
          'Masukkan alamat e-mel keluarga yang sah.',
      'Save family access': 'Simpan akses keluarga',
      'Family visibility access saved.':
          'Akses penglihatan keluarga telah disimpan.',
      'Caregiver access token': 'Token akses penjaga',
      'Caregiver access token copied.': 'Token akses penjaga disalin.',
      'Share this token securely with the family member. It is shown only once.':
          'Kongsi token ini dengan ahli keluarga secara selamat. Token ini hanya dipaparkan sekali.',
      'Copy token': 'Salin token',
      'Personal information': 'Maklumat peribadi',
      'Update the name and email stored for this account.':
          'Kemas kini nama yang disimpan untuk akaun ini.',
      'Name': 'Nama',
      'Email': 'E-mel',
      'Email identifies your calibration and event records.':
          'E-mel mengenal pasti rekod kalibrasi dan peristiwa anda.',
      'Save': 'Simpan',
      'Personal information saved.': 'Maklumat peribadi disimpan.',
      'Report a problem': 'Laporkan masalah',
      'Contact the developer team if something is not working.':
          'Hubungi pasukan pembangun jika sesuatu tidak berfungsi.',
      'Copy support email': 'Salin e-mel sokongan',
      'Developer support email copied.': 'E-mel sokongan pembangun disalin.',
      'Wearable Sensors': 'Sensor Boleh Pakai',
      'Wearable Sensor': 'Sensor Boleh Pakai',
      'Connecting sensors...': 'Menyambungkan sensor...',
      'Connecting sensor...': 'Menyambungkan sensor...',
      'Calibrating sensors...': 'Mengkalibrasi sensor...',
      'Calibrating sensor...': 'Mengkalibrasi sensor...',
      'Monitoring active': 'Pemantauan aktif',
      'Monitoring paused': 'Pemantauan dijeda',
      'Sensor 1: Upper Arm Sensor': 'Sensor 1: Sensor Lengan Atas',
      'Sensor 2: Wrist Sensor': 'Sensor 2: Sensor Pergelangan Tangan',
      'Connected': 'Bersambung',
      'Disconnected': 'Terputus',
      'Connected sensors': 'Sensor bersambung',
      'Connected sensor': 'Sensor bersambung',
      'Disconnect': 'Putuskan sambungan',
      'Reconnect Sensors': 'Sambung semula sensor',
      'Reconnect Sensor': 'Sambung semula sensor',
      'Connect Sensors': 'Sambungkan sensor',
      'Connect Sensor': 'Sambungkan sensor',
      'Checking sensors...': 'Memeriksa sensor...',
      'Checking sensor...': 'Memeriksa sensor...',
      'Static calibration complete': 'Kalibrasi statik selesai',
      'Calibration in progress': 'Kalibrasi sedang berjalan',
      'Static calibration required': 'Kalibrasi statik diperlukan',
      'Check sensor orientation': 'Periksa orientasi sensor',
      'Static calibration': 'Kalibrasi statik',
      'Preparing calibration after both sensors connect.':
          'Menyediakan kalibrasi selepas kedua-dua sensor bersambung.',
      'Preparing calibration after the sensor connects.':
          'Menyediakan kalibrasi selepas sensor bersambung.',
      'Calibration complete. Monitoring is starting.':
          'Kalibrasi selesai. Pemantauan bermula.',
      'The static neutral reading differs from the initial reading saved when this account was created. Check both sensors and make sure each orientation marker points down toward the earth.':
          'Bacaan neutral statik berbeza daripada bacaan awal semasa akaun ini dibuat. Periksa kedua-dua sensor dan pastikan penanda orientasi menghala ke bawah.',
      'The static neutral reading differs from the initial reading saved when this account was created. Check that the sensor marker points down toward the earth.':
          'Bacaan neutral statik berbeza daripada bacaan awal semasa akaun ini dibuat. Pastikan penanda sensor menghala ke bawah ke arah bumi.',
      'Static calibration differs from your initial baseline. Check that the sensor marker points down toward the earth.':
          'Kalibrasi statik berbeza daripada garis dasar awal anda. Pastikan penanda sensor menghala ke bawah ke arah bumi.',
      'Static calibration failed. Check that the sensor marker points down toward the earth.':
          'Kalibrasi statik gagal. Pastikan penanda sensor menghala ke bawah ke arah bumi.',
      'I understand': 'Saya faham',
      'Both sensors were not found. Check that they are powered on.':
          'Kedua-dua sensor tidak ditemui. Pastikan sensor dihidupkan.',
      'The wearable sensor was not found. Check that it is powered on.':
          'Sensor boleh pakai tidak ditemui. Pastikan sensor dihidupkan.',
      'Unable to connect sensors right now.':
          'Tidak dapat menyambungkan sensor sekarang.',
      'Unable to connect the sensor right now.':
          'Tidak dapat menyambungkan sensor sekarang.',
      'Unable to pause monitoring right now.':
          'Tidak dapat menjeda pemantauan sekarang.',
      'Stand still for calibration': 'Berdiri diam untuk kalibrasi',
      'Stand before calibration': 'Berdiri sebelum kalibrasi',
      'Both sensors are connected. Stand comfortably with your PICC arm relaxed beside your body, then tap I understand to begin calibration.':
          'Kedua-dua sensor telah disambungkan. Berdiri dengan selesa dan relakskan lengan PICC di sisi badan, kemudian tekan Saya faham untuk memulakan kalibrasi.',
      'The wearable sensor is connected. Stand comfortably with your PICC arm relaxed beside your body, then tap I understand to begin calibration.':
          'Sensor boleh pakai telah disambungkan. Berdiri dengan selesa dan relakskan lengan PICC di sisi badan, kemudian tekan Saya faham untuk memulakan kalibrasi.',
      '1. Stand comfortably with the PICC arm relaxed.':
          '1. Berdiri dengan selesa dan relakskan lengan PICC.',
      '2. Keep the arm still beside the body.':
          '2. Pastikan lengan diam di sisi badan.',
      '3. Make sure the sensor marker points down.':
          '3. Pastikan penanda sensor menghala ke bawah.',
      'Error loading events': 'Ralat memuatkan peristiwa',
      'Retry': 'Cuba lagi',
      'No risky events detected yet.': 'Tiada peristiwa berisiko dikesan lagi.',
      'Tap a day to open the events recorded on that date.':
          'Ketik hari untuk membuka peristiwa yang direkodkan pada tarikh itu.',
      'event': 'peristiwa',
      'events': 'peristiwa',
      'No event yet': 'Tiada peristiwa lagi',
      'Today\'s Care Overview': 'Ringkasan Penjagaan Hari Ini',
      'Dressing reminder': 'Peringatan balutan',
      'Daily care checklist': 'Senarai semak penjagaan harian',
      'complete': 'selesai',
      'You are doing well. Keep your PICC arm comfortable and continue your daily care routine.':
          'Anda melakukan dengan baik. Pastikan lengan PICC selesa dan teruskan rutin penjagaan harian.',
      'Please schedule your first dressing check':
          'Sila jadualkan pemeriksaan balutan pertama',
      'Next change tomorrow': 'Tukar seterusnya esok',
      'Dressing change due today': 'Penukaran balutan perlu dibuat hari ini',
      'Dressing change overdue': 'Penukaran balutan telah lewat',
      'Patient': 'Pesakit',
      'PICC Arm Status: Stable': 'Status Lengan PICC: Stabil',
      'Latest Event': 'Peristiwa Terkini',
      'Your monitoring is active and your care routine is on track today.':
          'Pemantauan anda aktif dan rutin penjagaan anda berada di landasan hari ini.',
      'Friendly tip: keep your PICC arm movements smooth and relaxed.':
          'Tip mesra: pastikan pergerakan lengan PICC lancar dan relaks.',
      'Today\'s Length': 'Panjang Hari Ini',
      'Status': 'Status',
      'POSSIBLE PICC DISLODGEMENT DETECTED':
          'KEMUNGKINAN PICC TERCABUT DIKESAN',
      'Difference is greater than 1.0 cm. Please contact your healthcare provider.':
          'Perbezaan melebihi 1.0 cm. Sila hubungi penyedia penjagaan kesihatan anda.',
      'Upload a photo to start tracking this dressing cycle.':
          'Muat naik foto untuk mula menjejak kitaran balutan ini.',
      'Difference is within the expected range for this dressing cycle.':
          'Perbezaan berada dalam julat dijangka untuk kitaran balutan ini.',
      'Create Account': 'Cipta Akaun',
      'Sign In': 'Log Masuk',
      'Patient Sign In': 'Log Masuk Pesakit',
      'Create': 'Cipta',
      'Caregiver': 'Penjaga',
      'Family': 'Keluarga',
      'Caregiver Access': 'Akses Penjaga',
      'Open Caregiver Dashboard': 'Buka Papan Pemuka Penjaga',
      'View summaries and trends for patients who shared access with you.':
          'Lihat ringkasan dan trend pesakit yang berkongsi akses dengan anda.',
      'Caregiver Dashboard': 'Papan Pemuka Penjaga',
      'Refresh': 'Muat semula',
      'Welcome': 'Selamat datang',
      'This is a read-only view of patients who shared access with you.':
          'Ini ialah paparan baca sahaja bagi pesakit yang berkongsi akses dengan anda.',
      'Viewing patient': 'Melihat pesakit',
      'Risk Level': 'Tahap Risiko',
      'Risky Events Today': 'Peristiwa Berisiko Hari Ini',
      'Low': 'Rendah',
      'Medium': 'Sederhana',
      'High': 'Tinggi',
      'No patient currently shares their PICC status with this caregiver account.':
          'Tiada pesakit yang sedang berkongsi status PICC dengan akaun penjaga ini.',
      'Create a new account to get started with PICC monitoring.':
          'Cipta akaun baharu untuk memulakan pemantauan PICC.',
      'Log in to continue to your patient dashboard.':
          'Log masuk untuk meneruskan ke papan pemuka pesakit.',
      'Full Name': 'Nama Penuh',
      'Password': 'Kata Laluan',
      'Access token': 'Token akses',
      'Access token is required': 'Token akses diperlukan',
      'Name is required': 'Nama diperlukan',
      'Email is required': 'E-mel diperlukan',
      'Enter a valid email': 'Masukkan e-mel yang sah',
      'Minimum 6 characters': 'Minimum 6 aksara',
      'Creating...': 'Sedang mencipta...',
      'Signing in...': 'Sedang log masuk...',
      'Patient To-Do Checklist': 'Senarai Tugasan Pesakit',
      'completed': 'selesai',
      'Missed Task Alerts': 'Amaran Tugasan Terlepas',
      'Smart Reminders': 'Peringatan Pintar',
      'Site check (redness, swelling, pain)':
          'Periksa tapak (kemerahan, bengkak, sakit)',
      'Dressing condition': 'Keadaan balutan',
      'Keep dressing clean, dry, and intact':
          'Pastikan balutan bersih, kering dan tidak rosak',
      'Flushing reminder': 'Peringatan pembilasan',
      'Flush line at prescribed schedule':
          'Bilas talian mengikut jadual yang ditetapkan',
      'Dryness check': 'Pemeriksaan kekeringan',
      'Medication timing': 'Waktu ubat',
      'Check catheter length (VERY IMPORTANT)':
          'Periksa panjang kateter (SANGAT PENTING)',
      'Look at external line and confirm same length as before':
          'Periksa talian luaran dan pastikan panjangnya sama seperti sebelumnya',
      'Avoid heavy movement or strain':
          'Elakkan pergerakan berat atau ketegangan',
      'Heavy lifting, sudden arm pulling, repetitive motion':
          'Mengangkat berat, tarikan lengan secara tiba-tiba, gerakan berulang',
      'Secure the line at all times': 'Pastikan talian sentiasa selamat',
      'Calendar': 'Kalendar',
      'Add event': 'Tambah peristiwa',
      'Add Calendar Event': 'Tambah Peristiwa Kalendar',
      'Event type': 'Jenis peristiwa',
      'Appointment': 'Janji temu',
      'Dressing change': 'Penukaran balutan',
      'Location': 'Lokasi',
      'Clinic / hospital / room': 'Klinik / hospital / bilik',
      'Dressing': 'Balutan',
      'Appt': 'Janji',
      'more': 'lagi',
      'Today\'s Movement Count': 'Kiraan Pergerakan Hari Ini',
      'Sensors Connected': 'Sensor Bersambung',
      'Care Attention Level': 'Tahap Perhatian Penjagaan',
      'Status:': 'Status:',
      'Battery:': 'Bateri:',
      'Connection status is managed by the backend.':
          'Status sambungan diuruskan oleh sistem backend.',
      'Upload a site photo to compare visible catheter length during this dressing cycle.':
          'Muat naik foto tapak untuk membandingkan panjang talian yang kelihatan sepanjang kitaran balutan ini.',
      'Not exposed': 'Tidak tersedia',
      'Monitoring services are ready. Use the Wearable Sensors panel to connect or pause monitoring.':
          'Perkhidmatan pemantauan sedia. Gunakan panel Sensor Boleh Pakai untuk menyambung atau menjeda pemantauan.',
      'Monitoring services are not ready yet. The app will reconnect when the backend is available.':
          'Perkhidmatan pemantauan belum sedia. Aplikasi akan menyambung semula apabila backend tersedia.',
      'Risky Events - Last 7 Days': 'Peristiwa Berisiko - 7 Hari Terakhir',
      'No events yet.': 'Tiada peristiwa lagi.',
      'Elbow flexion': 'Fleksi siku',
      'Shoulder adduction': 'Adduksi bahu',
      'AI Risk Trend Analysis': 'Analisis Trend Risiko AI',
      'Weekly Movement Review': 'Semakan Pergerakan Mingguan',
      'Weekly Trend': 'Trend Mingguan',
      'Peak Risk Time': 'Waktu Risiko Tertinggi',
      'Time-of-day pattern from weekly events':
          'Corak waktu berdasarkan peristiwa mingguan',
      'Common Risk': 'Risiko Lazim',
      'Most frequent movement needing extra awareness':
          'Pergerakan paling kerap yang memerlukan perhatian tambahan',
      'Stability': 'Kestabilan',
      'Consistent movement awareness days':
          'Hari kesedaran pergerakan yang konsisten',
      'Care Suggestion': 'Cadangan Penjagaan',
      'Gentle reminder tailored to this week\'s pattern':
          'Peringatan lembut berdasarkan corak minggu ini',
      'this week vs': 'minggu ini berbanding',
      'last week': 'minggu lalu',
    },
    'Chinese': {
      'PICC Care Companion': 'PICC 护理伙伴',
      'Settings': '设置',
      'Logout': '退出登录',
      'Dashboard': '主页',
      'Guide': '指南',
      'Event Log': '事件记录',
      'Language': '语言',
      'Choose the language used by the application.': '选择应用使用的语言。',
      'Application language': '应用语言',
      'English': '英语',
      'Malay': '马来语',
      'Chinese': '中文',
      'Calibration': '校准',
      'Replace your original static neutral calibration reading.':
          '\u66ff\u6362\u539f\u672c\u7684\u9759\u6001\u4e2d\u7acb\u6821\u51c6\u8bfb\u6570\u3002',
      'Your next sensor connection will perform static neutral calibration and save the result as the new baseline.':
          '\u4e0b\u6b21\u8fde\u63a5\u4f20\u611f\u5668\u65f6\u4f1a\u8fdb\u884c\u9759\u6001\u4e2d\u7acb\u6821\u51c6\uff0c\u5e76\u5c06\u7ed3\u679c\u4fdd\u5b58\u4e3a\u65b0\u7684\u57fa\u7ebf\u3002',
      'Perform new baseline calibration': '执行新的基线校准',
      'Overwrite baseline calibration?': '覆盖基线校准？',
      'Cancel': '取消',
      'Overwrite baseline': '覆盖基线',
      'Ready. Connect the sensors to record the new baseline calibration.':
          '已准备好。请连接传感器以记录新的基线校准。',
      'Data privacy': '数据隐私',
      'Control whether approved family members can track your PICC status.':
          '控制已批准的家人是否可以查看你的 PICC 状态。',
      'Allow family access': '允许家人访问',
      'Family tracking access is enabled.': '家人追踪访问已开启。',
      'Only you can view your status.': '只有你可以查看自己的状态。',
      'Family email address': '家人电子邮件地址',
      'This email will be allowed to view your PICC status.':
          '此电子邮件将被允许查看你的 PICC 状态。',
      'Enter a valid family email address.': '请输入有效的家人电子邮件地址。',
      'Save family access': '保存家人访问权限',
      'Family visibility access saved.': '家人查看权限已保存。',
      'Caregiver access token': '照护者访问令牌',
      'Caregiver access token copied.': '照护者访问令牌已复制。',
      'Share this token securely with the family member. It is shown only once.':
          '请安全地与家人共享此令牌。令牌只会显示一次。',
      'Copy token': '复制令牌',
      'Personal information': '个人信息',
      'Update the name and email stored for this account.': '更新此账户保存的姓名。',
      'Name': '姓名',
      'Email': '电子邮件',
      'Email identifies your calibration and event records.':
          '电子邮件用于识别你的校准和事件记录。',
      'Save': '保存',
      'Personal information saved.': '个人信息已保存。',
      'Report a problem': '报告问题',
      'Contact the developer team if something is not working.':
          '如果功能异常，请联系开发团队。',
      'Copy support email': '复制支持邮箱',
      'Developer support email copied.': '开发团队支持邮箱已复制。',
      'Wearable Sensors': '可穿戴传感器',
      'Wearable Sensor': '可穿戴传感器',
      'Connecting sensors...': '正在连接传感器...',
      'Connecting sensor...': '正在连接传感器...',
      'Calibrating sensors...': '正在校准传感器...',
      'Calibrating sensor...': '正在校准传感器...',
      'Monitoring active': '监测中',
      'Monitoring paused': '监测已暂停',
      'Sensor 1: Upper Arm Sensor': '传感器 1：上臂传感器',
      'Sensor 2: Wrist Sensor': '传感器 2：手腕传感器',
      'Connected': '已连接',
      'Disconnected': '未连接',
      'Connected sensors': '已连接传感器',
      'Connected sensor': '已连接传感器',
      'Disconnect': '断开连接',
      'Reconnect Sensors': '重新连接传感器',
      'Reconnect Sensor': '重新连接传感器',
      'Connect Sensors': '连接传感器',
      'Connect Sensor': '连接传感器',
      'Checking sensors...': '正在检查传感器...',
      'Checking sensor...': '正在检查传感器...',
      'Static calibration complete': '\u9759\u6001\u6821\u51c6\u5df2\u5b8c\u6210',
      'Static calibration required': '\u9700\u8981\u9759\u6001\u6821\u51c6',
      'Calibration in progress': '校准进行中',
      'Check sensor orientation': '检查传感器方向',
      'Static calibration': '静态校准',
      'Preparing calibration after both sensors connect.': '两个传感器连接后准备校准。',
      'Preparing calibration after the sensor connects.': '传感器连接后准备校准。',
      'Calibration complete. Monitoring is starting.': '校准完成。监测即将开始。',
      'The static neutral reading differs from the initial reading saved when this account was created. Check both sensors and make sure each orientation marker points down toward the earth.':
          '静态中立读数与创建账户时保存的初始读数不同。请检查两个传感器，并确保方向标记朝向地面。',
      'The static neutral reading differs from the initial reading saved when this account was created. Check that the sensor marker points down toward the earth.':
          '静态中立读数与创建账户时保存的初始读数不同。请确认传感器标记朝向地面。',
      'Static calibration differs from your initial baseline. Check that the sensor marker points down toward the earth.':
          '静态校准与初始基线不同。请确认传感器标记朝向地面。',
      'Static calibration failed. Check that the sensor marker points down toward the earth.':
          '\u9759\u6001\u6821\u51c6\u5931\u8d25\u3002\u8bf7\u786e\u8ba4\u4f20\u611f\u5668\u6807\u8bb0\u671d\u5411\u5730\u9762\u3002',
      'I understand': '我明白',
      'Both sensors were not found. Check that they are powered on.':
          '未找到两个传感器。请确认传感器已开启。',
      'The wearable sensor was not found. Check that it is powered on.':
          '未找到可穿戴传感器。请确认它已开机。',
      'Unable to connect sensors right now.': '现在无法连接传感器。',
      'Unable to connect the sensor right now.': '现在无法连接传感器。',
      'Unable to pause monitoring right now.': '现在无法暂停监测。',
      'Stand still for calibration': '站立不动进行校准',
      'Stand before calibration': '校准前请站立',
      'Both sensors are connected. Stand comfortably with your PICC arm relaxed beside your body, then tap I understand to begin calibration.':
          '两个传感器已连接。请舒适站立，将 PICC 手臂放松置于身体旁，然后点击“我明白”开始校准。',
      'The wearable sensor is connected. Stand comfortably with your PICC arm relaxed beside your body, then tap I understand to begin calibration.':
          '可穿戴传感器已连接。请舒适站立，让 PICC 手臂自然放松在身体旁，然后点击“我明白”开始校准。',
      '1. Stand comfortably with the PICC arm relaxed.': '1. 舒适站立，放松 PICC 手臂。',
      '2. Keep the arm still beside the body.': '2. 手臂保持在身体旁边不动。',
      '3. Make sure the sensor marker points down.': '3. 确保传感器标记朝下。',
      'Error loading events': '加载事件失败',
      'Retry': '重试',
      'No risky events detected yet.': '尚未检测到风险事件。',
      'Tap a day to open the events recorded on that date.': '点击日期查看当天记录的事件。',
      'event': '事件',
      'events': '事件',
      'No event yet': '暂无事件',
      'Today\'s Care Overview': '今日护理概览',
      'Dressing reminder': '敷料提醒',
      'Daily care checklist': '每日护理清单',
      'complete': '已完成',
      'You are doing well. Keep your PICC arm comfortable and continue your daily care routine.':
          '你做得很好。请保持 PICC 手臂舒适，并继续每日护理。',
      'Please schedule your first dressing check': '请安排第一次敷料检查',
      'Next change tomorrow': '明天更换',
      'Dressing change due today': '今天需要更换敷料',
      'Dressing change overdue': '敷料更换已逾期',
      'Patient': '患者',
      'PICC Arm Status: Stable': 'PICC 手臂状态：稳定',
      'Latest Event': '最新事件',
      'Your monitoring is active and your care routine is on track today.':
          '监测已开启，今天的护理流程正常。',
      'Friendly tip: keep your PICC arm movements smooth and relaxed.':
          '温馨提示：请保持 PICC 手臂动作平稳放松。',
      'Today\'s Length': '今日长度',
      'Status': '状态',
      'POSSIBLE PICC DISLODGEMENT DETECTED': '\u68c0\u6d4b\u5230 PICC \u53ef\u80fd\u79fb\u4f4d',
      'Difference is greater than 1.0 cm. Please contact your healthcare provider.':
          '\u5dee\u5f02\u5927\u4e8e 1.0 cm\u3002\u8bf7\u8054\u7cfb\u4f60\u7684\u533b\u7597\u62a4\u7406\u4eba\u5458\u3002',
      'Upload a photo to start tracking this dressing cycle.':
          '\u4e0a\u4f20\u7167\u7247\u4ee5\u5f00\u59cb\u8ffd\u8e2a\u672c\u6b21\u6577\u6599\u5468\u671f\u3002',
      'Difference is within the expected range for this dressing cycle.':
          '\u5dee\u5f02\u5728\u672c\u6b21\u6577\u6599\u5468\u671f\u7684\u9884\u671f\u8303\u56f4\u5185\u3002',
      'Create Account': '创建账户',
      'Sign In': '登录',
      'Patient Sign In': '患者登录',
      'Create': '创建',
      'Caregiver': '照护者',
      'Family': '家人',
      'Caregiver Access': '照护者访问',
      'Open Caregiver Dashboard': '打开照护者仪表板',
      'View summaries and trends for patients who shared access with you.':
          '查看已与你共享访问权限的患者摘要和趋势。',
      'Caregiver Dashboard': '照护者仪表板',
      'Refresh': '刷新',
      'Welcome': '欢迎',
      'This is a read-only view of patients who shared access with you.':
          '这是与你共享访问权限的患者的只读视图。',
      'Viewing patient': '正在查看患者',
      'Risk Level': '风险等级',
      'Risky Events Today': '今日风险事件',
      'Low': '低',
      'Medium': '中',
      'High': '高',
      'No patient currently shares their PICC status with this caregiver account.':
          '目前没有患者与此照护者账户共享 PICC 状态。',
      'Create a new account to get started with PICC monitoring.':
          '创建新账户以开始 PICC 监测。',
      'Log in to continue to your patient dashboard.': '登录以继续进入患者主页。',
      'Full Name': '姓名',
      'Password': '密码',
      'Access token': '访问令牌',
      'Access token is required': '请输入访问令牌',
      'Name is required': '请输入姓名',
      'Email is required': '请输入电子邮件',
      'Enter a valid email': '请输入有效的电子邮件',
      'Minimum 6 characters': '至少需要 6 个字符',
      'Creating...': '正在创建...',
      'Signing in...': '正在登录...',
      'Patient To-Do Checklist': '患者待办清单',
      'completed': '已完成',
      'Missed Task Alerts': '遗漏任务提醒',
      'Smart Reminders': '智能提醒',
      'Site check (redness, swelling, pain)': '检查部位（发红、肿胀、疼痛）',
      'Dressing condition': '敷料状况',
      'Keep dressing clean, dry, and intact': '保持敷料清洁、干燥且完整',
      'Flushing reminder': '冲管提醒',
      'Flush line at prescribed schedule': '按照规定时间冲管',
      'Dryness check': '干燥检查',
      'Medication timing': '用药时间',
      'Check catheter length (VERY IMPORTANT)': '检查导管长度（非常重要）',
      'Look at external line and confirm same length as before':
          '检查外露导管并确认长度与之前相同',
      'Avoid heavy movement or strain': '避免剧烈动作或用力',
      'Heavy lifting, sudden arm pulling, repetitive motion': '提重物、突然拉动手臂、重复动作',
      'Secure the line at all times': '始终固定好导管',
      'Calendar': '日历',
      'Add event': '添加事件',
      'Add Calendar Event': '添加日历事件',
      'Event type': '事件类型',
      'Appointment': '预约',
      'Dressing change': '更换敷料',
      'Location': '地点',
      'Clinic / hospital / room': '诊所 / 医院 / 房间',
      'Dressing': '敷料',
      'Appt': '预约',
      'more': '更多',
      'Today\'s Movement Count': '今日动作次数',
      'Sensors Connected': '已连接传感器',
      'Care Attention Level': '护理关注等级',
      'Status:': '状态：',
      'Battery:': '电量：',
      'Connection status is managed by the backend.': '连接状态由后端系统管理。',
      'Upload a site photo to compare visible catheter length during this dressing cycle.':
          '上传部位照片，以比较本次敷料周期中可见导管的长度。',
      'Not exposed': '不可用',
      'Monitoring services are ready. Use the Wearable Sensors panel to connect or pause monitoring.':
          '监测服务已准备好。请使用可穿戴传感器面板连接或暂停监测。',
      'Monitoring services are not ready yet. The app will reconnect when the backend is available.':
          '监测服务尚未准备好。后端可用时应用会重新连接。',
      'Risky Events - Last 7 Days': '风险事件 - 最近 7 天',
      'No events yet.': '暂无事件。',
      'Elbow flexion': '肘部弯曲',
      'Shoulder adduction': '肩部内收',
      'AI Risk Trend Analysis': 'AI 风险趋势分析',
      'Weekly Movement Review': '每周动作回顾',
      'Weekly Trend': '每周趋势',
      'Peak Risk Time': '风险高峰时间',
      'Time-of-day pattern from weekly events': '根据每周事件分析时段规律',
      'Common Risk': '常见风险',
      'Most frequent movement needing extra awareness': '最需要注意的常见动作',
      'Stability': '稳定性',
      'Consistent movement awareness days': '保持动作注意的天数',
      'Care Suggestion': '护理建议',
      'Gentle reminder tailored to this week\'s pattern': '根据本周规律提供温馨提醒',
      'this week vs': '本周，对比',
      'last week': '上周',
    },
  };

  String text(String english) {
    return _translations[language]?[english] ?? english;
  }

  String eventCount(int count) {
    final word = count == 1 ? text('event') : text('events');
    return '$count $word';
  }

  String dailyChecklistProgress(int completed, int total) {
    return '${text('Daily care checklist')}: $completed / $total ${text('complete')}';
  }

  String nextChangeInDays(int days) {
    if (language == 'Malay') {
      return 'Tukar seterusnya dalam $days hari';
    }
    if (language == 'Chinese') {
      return '$days 天后更换';
    }
    return 'Next change in $days days';
  }

  String completedCount(int completed, int total) {
    return '$completed / $total ${text('completed')}';
  }

  String flushingMissed(int count) {
    if (language == 'Malay') {
      return 'Pembilasan terlepas selama $count hari.';
    }
    if (language == 'Chinese') {
      return '冲管已遗漏 $count 天。';
    }
    return 'Flushing was missed $count day(s).';
  }

  String medicationMissed(int count) {
    if (language == 'Malay') {
      return 'Waktu ubat terlepas selama $count hari.';
    }
    if (language == 'Chinese') {
      return '用药时间已遗漏 $count 天。';
    }
    return 'Medication timing was missed $count day(s).';
  }

  String dressingCheckMissed(int count) {
    if (language == 'Malay') {
      return 'Pemeriksaan keadaan balutan terlepas selama $count hari.';
    }
    if (language == 'Chinese') {
      return '敷料状况检查已遗漏 $count 天。';
    }
    return 'Dressing condition check was missed $count day(s).';
  }

  String flushDue(String time, int minutes) {
    if (language == 'Malay') {
      return 'Jadual pembilasan perlu dibuat pada $time (peringatan awal $minutes minit).';
    }
    if (language == 'Chinese') {
      return '冲管时间为 $time（提前 $minutes 分钟提醒）。';
    }
    return 'Flush schedule due at $time (adaptive lead $minutes min).';
  }

  String medicationDue(String time, int minutes) {
    if (language == 'Malay') {
      return 'Waktu ubat perlu pada $time (peringatan awal $minutes minit).';
    }
    if (language == 'Chinese') {
      return '用药时间为 $time（提前 $minutes 分钟提醒）。';
    }
    return 'Medication timing due at $time (adaptive lead $minutes min).';
  }

  String dressingTomorrow(String date) {
    if (language == 'Malay') {
      return 'Balutan ditukar 6 hari lalu. Sila tukar balutan esok ($date).';
    }
    if (language == 'Chinese') {
      return '敷料已在 6 天前更换。请于明天更换敷料（$date）。';
    }
    return 'Dressing was changed 6 days ago. Please change dressing tomorrow ($date).';
  }

  String dressingTarget(String date, int minutes) {
    if (language == 'Malay') {
      return 'Tarikh sasaran penukaran balutan ialah $date (setiap 7 hari, peringatan awal $minutes minit).';
    }
    if (language == 'Chinese') {
      return '敷料更换目标日期为 $date（每 7 天，提前 $minutes 分钟提醒）。';
    }
    return 'Dressing change target is $date (every 7 days, adaptive lead $minutes min).';
  }

  String appointmentScheduled(bool tomorrow) {
    if (language == 'Malay') {
      return tomorrow
          ? 'Janji temu dijadualkan untuk esok.'
          : 'Janji temu dijadualkan untuk hari ini.';
    }
    if (language == 'Chinese') {
      return tomorrow ? '预约安排在明天。' : '预约安排在今天。';
    }
    return tomorrow
        ? 'Appointment is scheduled for tomorrow.'
        : 'Appointment is scheduled for today.';
  }

  List<String> get weekLabels {
    if (language == 'Malay') {
      return const ['Isn', 'Sel', 'Rab', 'Kha', 'Jum', 'Sab', 'Ahd'];
    }
    if (language == 'Chinese') {
      return const ['一', '二', '三', '四', '五', '六', '日'];
    }
    return const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  }

  String monthYear(DateTime date) {
    const english = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];
    const malay = [
      'Januari',
      'Februari',
      'Mac',
      'April',
      'Mei',
      'Jun',
      'Julai',
      'Ogos',
      'September',
      'Oktober',
      'November',
      'Disember',
    ];
    if (language == 'Malay') {
      return '${malay[date.month - 1]} ${date.year}';
    }
    if (language == 'Chinese') {
      return '${date.year}年${date.month}月';
    }
    return '${english[date.month - 1]} ${date.year}';
  }

  String moreEvents(int count) {
    if (language == 'Chinese') {
      return '另有 $count 项';
    }
    return '+$count ${text('more')}';
  }
}
