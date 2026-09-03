import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

class FirebaseService {
  // Ganti parameter ini dengan rahasia Firebase dari ESP32 Anda
  final String baseUrl =
      "https://smart-garden-iot-456f3-default-rtdb.asia-southeast1.firebasedatabase.app";
  final String authSecret = "rqx7cwmLSywPCLImvPrwnu6IsYaswrodZxw3MaTe";

  final _sensorDataController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get sensorDataStream =>
      _sensorDataController.stream;
  Timer? _pollingTimer;
  bool _isActive = false;

  Future<bool> initialize() async {
    _isActive = true;
    _startPolling();
    return true; // REST HTTP tidak membutuhkan jabat tangan (handshake) yang kaku sebelum mulai
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      if (!_isActive) return;
      try {
        final url = Uri.parse(
          "$baseUrl/smartgarden_parigi.json?auth=$authSecret",
        );
        final response = await http
            .get(url)
            .timeout(const Duration(seconds: 3));

        if (response.statusCode == 200 && response.body != "null") {
          final data = jsonDecode(response.body);
          if (data != null) {
            final sensor = data['sensor'];
            final pump = data['pump'];

            String temp = "--";
            String hum = "--";
            bool pumpOn = false;

            if (sensor != null) {
              temp = sensor['suhu']?.toString() ?? "--";
              hum = sensor['kelembaban']?.toString() ?? "--";
            }
            if (pump != null) {
              // Tergantung ESP merubah state/status
              final statusPump = pump['status']?.toString() ?? "OFF";
              pumpOn = statusPump.toUpperCase() == "ON";
            }

            _sensorDataController.add({
              'temp': temp,
              'hum': hum,
              'pump_on': pumpOn,
            });
          }
        }
      } catch (e) {
        // Gagal mengambil data sementara, abaikan (mencegah crash)
      }
    });
  }

  Future<void> publishWatering(bool state) async {
    try {
      final status = state ? "ON" : "OFF";
      final url = Uri.parse(
        "$baseUrl/smartgarden_parigi/pump/status.json?auth=$authSecret",
      );

      // Update data di database menjadi "ON" / "OFF" berupa string
      await http.put(url, body: jsonEncode(status));
    } catch (e) {
      // Gagal update pompa
    }
  }

  void dispose() {
    _isActive = false;
    _pollingTimer?.cancel();
    _sensorDataController.close();
  }
}
