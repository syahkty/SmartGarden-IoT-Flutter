import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_service.dart';

void main() {
  runApp(const AplikasiMonitoringKecamatan());
}

class AplikasiMonitoringKecamatan extends StatelessWidget {
  const AplikasiMonitoringKecamatan({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF5F7F9),
        fontFamily: 'Inter',
      ),
      home: const SplashScreen(),
    );
  }
}

// ========================================================
// WARNA IDENTIK SESUAI FIGMA
// ========================================================
const Color kHeaderGradStart = Color.fromRGBO(14, 180, 136, 1);
const Color kHeaderGradEnd = Color.fromRGBO(6, 78, 59, 1);
const Color kGreenPrimary = Color.fromRGBO(16, 185, 129, 1);
const Color kGreenBadgeBg = Color.fromRGBO(230, 247, 244, 1);
const Color kBgColor = Color(0xFFF5F7F9);
const Color kTextDark = Color(0xFF1D1D1D);
const Color kTextGrey = Color(0xFF8C8C8C);

// Warna Baru dari Palet Tombol
const Color kWateringCardGradStart = Color.fromRGBO(12, 157, 115, 1);
const Color kWateringCardGradEnd = Color.fromRGBO(5, 92, 68, 1);
const Color kTestButtonBlue = Color.fromRGBO(6, 182, 212, 1);
const Color kTestButtonOuterBorder = Color.fromRGBO(6, 78, 59, 0.11);

// ========================================================
// 1. SPLASH SCREEN
// ========================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Timer(const Duration(seconds: 3), () {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainLayoutScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kHeaderGradStart, kHeaderGradEnd],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.eco_outlined,
                size: 64,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Sistem Monitoring Tanaman\nBerbasis IoT",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              "Smart Plant Monitoring",
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 40),
            const SizedBox(
              width: 100,
              child: LinearProgressIndicator(
                backgroundColor: Colors.white30,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================================
// 2. MAIN LAYOUT (NAVIGASI)
// ========================================================
class MainLayoutScreen extends StatefulWidget {
  const MainLayoutScreen({super.key});

  @override
  State<MainLayoutScreen> createState() => _MainLayoutScreenState();
}

class _MainLayoutScreenState extends State<MainLayoutScreen> {
  int _selectedIndex = 0;
  bool _showWifiSettings = false;

  String _wifiSSID = "Tidak Terhubung";
  bool _isConnected = false;
  int _latency = 0;

  // Real-Time Data & Sensor
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;
  Timer? _pingTimer;

  final FirebaseService _dbService = FirebaseService();
  String _suhu = "--";
  String _kelembapan = "--";
  bool _isPumpOn = false;
  final List<DateTime> _riwayatSiram = [];

  @override
  void initState() {
    super.initState();
    _initWifiInfo();
    _startConnectivityListener();
    _initDatabase();
  }

  void _startConnectivityListener() {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((
      List<ConnectivityResult> results,
    ) {
      if (results.contains(ConnectivityResult.wifi)) {
        _initWifiInfo(); // Refresh WiFi name
        _startPingTimer();
      } else {
        setState(() {
          _wifiSSID = "Tidak Terhubung";
          _isConnected = false;
          _latency = 0;
        });
        _pingTimer?.cancel();
      }
    });
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (!_isConnected) return;
      final stopwatch = Stopwatch()..start();
      try {
        final socket = await Socket.connect(
          '8.8.8.8',
          53,
          timeout: const Duration(seconds: 2),
        );
        socket.destroy();
        stopwatch.stop();
        if (mounted) {
          setState(() {
            _latency = stopwatch.elapsedMilliseconds;
          });
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _latency = 0; // Ping gagal
          });
        }
      }
    });
  }

  Future<void> _initDatabase() async {
    await _dbService.initialize();

    _dbService.sensorDataStream.listen((data) {
      if (mounted) {
        setState(() {
          _suhu = data['temp'] ?? "--";
          _kelembapan = data['hum'] ?? "--";
          _isPumpOn = data['pump_on'] == true;
        });
      }
    });
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    _pingTimer?.cancel();
    _dbService.dispose();
    super.dispose();
  }

  Future<void> _initWifiInfo() async {
    // Meminta izin lokasi sekali di awal (Wajib di Android untuk baca WiFi)
    var status = await Permission.location.request();
    if (status.isGranted) {
      final info = NetworkInfo();
      String? wifiName = await info.getWifiName();
      if (wifiName != null && wifiName.isNotEmpty) {
        setState(() {
          _wifiSSID = wifiName.replaceAll('"', '');
          _isConnected = true;
          _latency = 31; // Dummy latency, as checking latency needs actual ping
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildCurrentPage(),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildCurrentPage() {
    if (_selectedIndex == 0) {
      return HalamanUtama(
        wifiSSID: _wifiSSID,
        isConnected: _isConnected,
        latency: _latency,
        suhu: _suhu,
        kelembapan: _kelembapan,
        isGlobalPumpOn: _isPumpOn,
        riwayatSiram: _riwayatSiram,
        onSiram: (bool nyala) {
          if (nyala) {
            setState(() {
              _riwayatSiram.insert(0, DateTime.now());
            });
          }
          _dbService.publishWatering(nyala);
        },
      );
    }
    if (_selectedIndex == 1) {
      return _showWifiSettings
          ? HalamanSettingsWifi(
            onKembali: () {
              setState(() => _showWifiSettings = false);
            },
            onSimpan: (String ssid, String password) async {
              // Minta perizinan dulu
              await Permission.location.request();

              // Coba untuk connect
              bool isConnected = await WiFiForIoTPlugin.connect(
                ssid,
                password: password,
                security: NetworkSecurity.WPA,
                joinOnce: true,
              );

              if (isConnected) {
                if (mounted) {
                  setState(() {
                    _wifiSSID = ssid;
                    _isConnected = true;
                    _latency = 32; // Placeholder
                    _showWifiSettings = false;
                  });
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text("Berhasil terhubung ke WiFi alat!"),
                    ),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        "Gagal terhubung, pastikan jaringan tersedia (Hardware Error).",
                      ),
                    ),
                  );
                }
              }
            },
          )
          : HalamanSettings(
            isPumpOn: _isPumpOn,
            onBukaWifi: () {
              setState(() => _showWifiSettings = true);
            },
            onSiramManual: (bool val) {
              if (val) {
                setState(() {
                  _riwayatSiram.insert(0, DateTime.now());
                });
              }
              _dbService.publishWatering(val);
            },
          );
    }
    return HalamanInformasi(
      wifiSSID: _wifiSSID,
      isConnected: _isConnected,
      latency: _latency,
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildNavItem(0, Icons.home_rounded, "Home"),
            _buildNavItem(1, Icons.settings_rounded, "Settings"),
            _buildNavItem(2, Icons.info_outline_rounded, "Info"),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    bool isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedIndex = index;
          _showWifiSettings = false;
        });
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected ? kGreenBadgeBg : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              icon,
              color: isSelected ? kGreenPrimary : kTextGrey,
              size: 28,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? kGreenPrimary : kTextGrey,
            ),
          ),
        ],
      ),
    );
  }
}

// ========================================================
// 3. HEADER DENGAN DEKORASI LINGKARAN
// ========================================================
class CustomHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? customTrailing;

  const CustomHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.customTrailing,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [kHeaderGradStart, kHeaderGradEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -60,
              right: -40,
              child: Container(
                width: 220,
                height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              top: 40,
              right: -80,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.05),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: 60,
                left: 24,
                right: 24,
                bottom: 32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (subtitle != null && icon == null) ...[
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(icon, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 16),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (subtitle != null && icon != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                subtitle!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (customTrailing != null) ...[
                    const SizedBox(height: 20),
                    customTrailing!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ========================================================
// 4. HALAMAN UTAMA (HOME)
// ========================================================
class HalamanUtama extends StatefulWidget {
  final String wifiSSID;
  final bool isConnected;
  final int latency;
  final String suhu;
  final String kelembapan;
  final bool isGlobalPumpOn;
  final List<DateTime> riwayatSiram;
  final Function(bool) onSiram;

  const HalamanUtama({
    super.key,
    required this.wifiSSID,
    required this.isConnected,
    this.latency = 0,
    required this.suhu,
    required this.kelembapan,
    required this.isGlobalPumpOn,
    required this.riwayatSiram,
    required this.onSiram,
  });

  @override
  State<HalamanUtama> createState() => _HalamanUtamaState();
}

class _HalamanUtamaState extends State<HalamanUtama> {
  bool _isTesting = false;

  void _showSweetAlert(
    String title,
    String message,
    IconData icon,
    Color color, {
    bool autoClose = false,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !autoClose,
      builder:
          (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 60),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                if (!autoClose) ...[
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: color,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      "OK",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
    );

    if (autoClose) {
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  void _jalankanTesSiram() {
    if (widget.isGlobalPumpOn) {
      _showSweetAlert(
        "Pompa Sedang Aktif!",
        "Penyiraman sedang menyala melalui mode manual. Matikan terlebih dahulu sebelum memulai tes.",
        Icons.warning_rounded,
        Colors.orange,
      );
      return;
    }

    if (_isTesting) return; // Mencegah klik ganda

    setState(() {
      _isTesting = true;
    });

    _showSweetAlert(
      "Berhasil!",
      "Proses penyiraman dimulai (Tunggu 2.5 detik).",
      Icons.check_circle_rounded,
      kGreenPrimary,
      autoClose: true,
    );

    widget.onSiram(true); // Kirim perintah ON ke perangkat dan tambah riwayat

    // Tahan 2.5 detik lalu kembalikan ke hijau dan kirim perintah OFF
    Future.delayed(const Duration(milliseconds: 2500), () {
      if (mounted) {
        widget.onSiram(false);
        setState(() {
          _isTesting = false;
        });

        _showSweetAlert(
          "Selesai!",
          "Tes penyiraman dihentikan.",
          Icons.info_outline_rounded,
          Colors.blue,
          autoClose: true,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CustomHeader(
            title: "Monitoring Tanaman",
            subtitle: "Selamat Datang",
            customTrailing: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    widget.isConnected
                        ? "• Terhubung • ${widget.latency}ms"
                        : "• Tidak Terhubung",
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.isConnected ? Icons.wifi : Icons.wifi_off,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle(Icons.sensors, "Data Sensor"),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDataCard(
                        title: "Suhu Sekitar",
                        value: widget.suhu,
                        unit: "°C",
                        status: "Normal",
                        icon: Icons.thermostat,
                        iconColor: Colors.orange,
                        statusColor: kGreenPrimary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDataCard(
                        title: "Kelembaban",
                        value: widget.kelembapan,
                        unit: "%",
                        status: "Baik",
                        icon: Icons.water_drop,
                        iconColor: Colors.blue,
                        statusColor: kGreenPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildPlantConditionCard(),
                const SizedBox(height: 16),
                const Text(
                  "Riwayat Penyiraman",
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.riwayatSiram.isEmpty) ...[
                  const Text(
                    "Belum ada riwayat hari ini",
                    style: TextStyle(
                      color: kTextGrey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ] else ...[
                  ...widget.riwayatSiram
                      .take(3)
                      .map((waktu) => _buildLastWateredCard(waktu))
                      .toList(),
                ],
                const SizedBox(height: 24),
                _buildSectionTitle(Icons.devices, "Tes Perangkat"),
                const SizedBox(height: 24),

                // --- TOMBOL TES SIRAM ---
                Center(
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _jalankanTesSiram,
                        child: CustomPaint(
                          painter: DashedCirclePainter(
                            color: kTestButtonOuterBorder,
                            strokeWidth: 2,
                            dashWidth: 4,
                            dashSpace: 4,
                          ),
                          child: SizedBox(
                            width: 140, // circular-button-outer
                            height: 140,
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 120, // circular-button-inner
                                height: 120,
                                decoration: BoxDecoration(
                                  color:
                                      _isTesting
                                          ? kTestButtonBlue
                                          : kGreenPrimary,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_isTesting
                                              ? kTestButtonBlue
                                              : kGreenPrimary)
                                          .withOpacity(0.3),
                                      blurRadius: 16,
                                      spreadRadius: 2,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedSwitcher(
                                      duration: const Duration(
                                        milliseconds: 300,
                                      ),
                                      child: Icon(
                                        (_isTesting || widget.isGlobalPumpOn)
                                            ? Icons.stop
                                            : Icons.waves,
                                        key: ValueKey<bool>(
                                          _isTesting || widget.isGlobalPumpOn,
                                        ),
                                        color: Colors.white,
                                        size: 36,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      (_isTesting || widget.isGlobalPumpOn)
                                          ? "Menyiram"
                                          : "Tes Siram",
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        "Tekan untuk menguji penyiraman",
                        style: TextStyle(color: kTextGrey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, color: kGreenPrimary, size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: kTextDark,
          ),
        ),
      ],
    );
  }

  Widget _buildDataCard({
    required String title,
    required String value,
    required String unit,
    required String status,
    required IconData icon,
    required Color iconColor,
    required Color statusColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Icon(icon, color: iconColor, size: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: kGreenBadgeBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    color: statusColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: kTextGrey, fontSize: 12)),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    color: kTextDark,
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                TextSpan(
                  text: unit,
                  style: const TextStyle(
                    color: kTextGrey,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlantConditionCard() {
    double humValue = double.tryParse(widget.kelembapan) ?? 72.0;
    String statusTanaman = "Lembab";
    Color statusColor = kTextDark;

    if (humValue < 40) {
      statusTanaman = "Kering (Butuh Air)";
      statusColor = Colors.redAccent;
    } else if (humValue > 70) {
      statusTanaman = "Sangat Basah";
      statusColor = Colors.blueAccent;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Kondisi Tanaman",
                style: TextStyle(color: kTextGrey, fontSize: 12),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: kGreenBadgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.grass, color: kGreenPrimary, size: 20),
              ),
            ],
          ),
          Text(
            statusTanaman,
            style: TextStyle(
              color: statusColor,
              fontSize: 22,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "• Kelembaban tanah: ${widget.kelembapan}%",
                style: const TextStyle(color: kGreenPrimary, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (double.tryParse(widget.kelembapan) ?? 72) / 100,
              backgroundColor: kGreenBadgeBg,
              valueColor: AlwaysStoppedAnimation<Color>(kGreenPrimary),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastWateredCard(DateTime waktu) {
    // Format AM/PM dan JAM
    String menit = waktu.minute.toString().padLeft(2, '0');
    String jam = waktu.hour.toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, color: kGreenPrimary),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Riwayat Siram",
                style: TextStyle(color: kTextGrey, fontSize: 12),
              ),
              Text(
                "Hari ini, $jam:$menit WITA",
                style: const TextStyle(
                  color: kTextDark,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ========================================================
// CUSTOM PAINTER UNTUK BORDER PUTUS-PUTUS (DASHED BORDER)
// ========================================================
class DashedCirclePainter extends CustomPainter {
  final Color color;
  final double strokeWidth;
  final double dashWidth;
  final double dashSpace;

  DashedCirclePainter({
    required this.color,
    this.strokeWidth = 2.0,
    this.dashWidth = 4.0,
    this.dashSpace = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke;

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    // Perhitungan panjang keliling lingkaran
    double circumference = size.width * math.pi;
    int dashCount = (circumference / (dashWidth + dashSpace)).floor();

    double sweepAngle = (dashWidth / circumference) * 2 * math.pi;
    double spaceAngle = (dashSpace / circumference) * 2 * math.pi;
    double startAngle = 0;

    for (int i = 0; i < dashCount; i++) {
      canvas.drawArc(rect, startAngle, sweepAngle, false, paint);
      startAngle += sweepAngle + spaceAngle;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ========================================================
// 5. HALAMAN SETTINGS
// ========================================================
class HalamanSettings extends StatefulWidget {
  final VoidCallback onBukaWifi;
  final Function(bool) onSiramManual;
  final bool isPumpOn;

  const HalamanSettings({
    super.key,
    required this.onBukaWifi,
    required this.onSiramManual,
    required this.isPumpOn,
  });

  @override
  State<HalamanSettings> createState() => _HalamanSettingsState();
}

class _HalamanSettingsState extends State<HalamanSettings> {
  bool _isManualOn = false;

  @override
  void initState() {
    super.initState();
    _isManualOn = widget.isPumpOn;
  }

  @override
  void didUpdateWidget(covariant HalamanSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isPumpOn != widget.isPumpOn) {
      if (mounted) {
        setState(() {
          _isManualOn = widget.isPumpOn;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CustomHeader(
          title: "Pengaturan",
          subtitle: "Konfigurasi perangkat IoT",
          icon: Icons.settings,
        ),
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "KONEKTIVITAS",
                style: TextStyle(
                  color: kTextGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: widget.onBukaWifi,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4),
                    ],
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: Color(0xFFE3F2FD),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.wifi, color: Colors.blue),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              "Pengaturan WiFi",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            Text(
                              "Ganti jaringan WiFi terhubung",
                              style: TextStyle(color: kTextGrey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: kTextGrey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 32),
              const Text(
                "PENYIRAMAN",
                style: TextStyle(
                  color: kTextGrey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // --- KARTU SIRAM MANUAL ---
              Container(
                height: 72, // Fixed height mengikuti properti Figma
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kWateringCardGradStart, kWateringCardGradEnd],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4),
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.waves, color: Colors.white, size: 32),
                    const SizedBox(width: 12), // Gap 12px
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Siram Manual",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            "Tekan toggle untuk menyiram",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isManualOn,
                      activeColor: kGreenPrimary,
                      activeTrackColor: Colors.white,
                      inactiveThumbColor: kTextGrey,
                      inactiveTrackColor: Colors.white,
                      onChanged: (val) {
                        setState(() {
                          _isManualOn = val;
                        });

                        ScaffoldMessenger.of(context).hideCurrentSnackBar();

                        // Memunculkan Loading SweetAlert
                        showDialog(
                          context: context,
                          barrierDismissible: false,
                          builder:
                              (ctx) => AlertDialog(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                content: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const CircularProgressIndicator(
                                      color: kGreenPrimary,
                                    ),
                                    const SizedBox(height: 20),
                                    Text(
                                      val
                                          ? "Menyalakan Pompa..."
                                          : "Mematikan Pompa...",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    const Text(
                                      "Harap tunggu sebentar",
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                        );

                        // Kirim Perintah
                        widget.onSiramManual(val);

                        // Simulasikan delay dan tutup dialog
                        Future.delayed(const Duration(milliseconds: 1500), () {
                          if (mounted && Navigator.canPop(context)) {
                            Navigator.pop(context); // Tutup dialog

                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text("Perintah berhasil terkirim!"),
                                backgroundColor: kGreenPrimary,
                                behavior: SnackBarBehavior.floating,
                                duration: Duration(seconds: 2),
                              ),
                            );
                          }
                        });
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ========================================================
// 6. HALAMAN PENGATURAN WIFI (SUB-SETTINGS)
// ========================================================
class HalamanSettingsWifi extends StatefulWidget {
  final VoidCallback onKembali;
  final Future<void> Function(String, String) onSimpan;

  const HalamanSettingsWifi({
    super.key,
    required this.onKembali,
    required this.onSimpan,
  });

  @override
  State<HalamanSettingsWifi> createState() => _HalamanSettingsWifiState();
}

class _HalamanSettingsWifiState extends State<HalamanSettingsWifi> {
  final TextEditingController _ssidController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _ssidController.dispose();
    _passController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CustomHeader(
          title: "Pengaturan WiFi",
          subtitle: "Hubungkan ke jaringan baru",
          icon: Icons.bar_chart_rounded,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Nama WiFi (SSID)",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ssidController,
                  decoration: InputDecoration(
                    hintText: "Masukkan SSID",
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "Password",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: kTextDark,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _passController,
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: "Masukkan Password",
                    filled: true,
                    fillColor: Colors.white,
                    suffixIcon: const Icon(
                      Icons.visibility_off,
                      color: kTextGrey,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black12),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Colors.black12),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kGreenBadgeBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kGreenPrimary.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline, color: kGreenPrimary),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Pastikan perangkat IoT berada dalam jangkauan WiFi",
                          style: TextStyle(color: kHeaderGradEnd, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : widget.onKembali,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          side: const BorderSide(color: Colors.black12),
                        ),
                        child: const Text(
                          "Kembali",
                          style: TextStyle(
                            color: kTextGrey,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            _isLoading
                                ? null
                                : () async {
                                  setState(() {
                                    _isLoading = true;
                                  });
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        "Sedang menghubungkan ke IoT...",
                                      ),
                                      duration: Duration(seconds: 4),
                                    ),
                                  );

                                  try {
                                    await widget.onSimpan(
                                      _ssidController.text,
                                      _passController.text,
                                    );
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        _isLoading = false;
                                      });
                                    }
                                  }
                                },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kWateringCardGradStart,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child:
                            _isLoading
                                ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                                : const Text(
                                  "Simpan",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ========================================================
// 7. HALAMAN INFORMASI
// ========================================================
class HalamanInformasi extends StatelessWidget {
  final String wifiSSID;
  final bool isConnected;
  final int latency;

  const HalamanInformasi({
    super.key,
    required this.wifiSSID,
    required this.isConnected,
    this.latency = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CustomHeader(title: "Informasi", icon: Icons.info_outline),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                _buildInfoCard(
                  icon: isConnected ? Icons.wifi : Icons.wifi_off,
                  title: "Status WiFi",
                  content: Column(
                    children: [
                      _buildInfoRow("Jaringan", wifiSSID),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        "Status",
                        isConnected ? "• Terhubung" : "• Terputus",
                        valueColor: isConnected ? kGreenPrimary : Colors.red,
                        isBadge: true,
                      ),
                      const SizedBox(height: 8),
                      _buildInfoRow(
                        "Latency",
                        isConnected ? "$latency ms" : "-",
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoCard(
                  icon: Icons.account_balance,
                  title: "Instansi Pemerintah",
                  content: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: kBgColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/images/logo_parimo.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Pemerintah Kecamatan Parigi Selatan\nKabupaten Parigi Moutong, Sulawesi Tengah",
                          style: TextStyle(fontSize: 12, color: kTextDark),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _buildInfoCard(
                  icon: Icons.school,
                  title: "Universitas",
                  content: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: kBgColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/images/logo_untad.jpg',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          "Universitas Tadulako\nFakultas Teknik Jurusan Teknologi Informasi\nProdi Sistem Informasi",
                          style: TextStyle(fontSize: 12, color: kTextDark),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kGreenPrimary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 16),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text(
                            "Andi Syahkty Alifah Assalam",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            "F 521 23 043",
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String title,
    required Widget content,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: kGreenBadgeBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: kGreenPrimary, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: kTextDark,
                ),
              ),
            ],
          ),
          const Divider(height: 24),
          content,
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBadge = false,
  }) {
    Widget valueWidget = Text(
      value,
      style: TextStyle(
        color: valueColor ?? kTextDark,
        fontSize: 13,
        fontWeight: FontWeight.bold,
      ),
    );

    if (isBadge) {
      valueWidget = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: kGreenBadgeBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: valueWidget,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: kTextGrey, fontSize: 13)),
        valueWidget,
      ],
    );
  }
}
