import 'dart:async';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

class MqttService {
  MqttServerClient? client;
  final String broker = 'broker.emqx.io';
  final int port = 1883;

  final String topicSensor = "smartgarden_parigi/sensor";
  final String topicAktuator = "smartgarden_parigi/pump";

  final _sensorDataController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get sensorDataStream =>
      _sensorDataController.stream;

  Future<bool> initialize() async {
    final clientId = 'flutter_client_${DateTime.now().millisecondsSinceEpoch}';
    client = MqttServerClient(broker, clientId);
    client!.port = port;
    client!.keepAlivePeriod = 60;
    client!.secure = false;
    client!.logging(on: false);

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);

    client!.connectionMessage = connMess;

    try {
      await client!.connect();
    } catch (e) {
      client!.disconnect();
      return false;
    }

    if (client!.connectionStatus!.state == MqttConnectionState.connected) {
      client!.subscribe(topicSensor, MqttQos.atMostOnce);

      client!.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        try {
          final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
          final String pt = MqttPublishPayload.bytesToStringAsString(
            recMess.payload.message,
          );

          // Menggunakan JSON Parser atau split koma "temp,hum" => "32,70"
          final parts = pt.split(',');
          if (parts.length >= 2) {
            _sensorDataController.add({
              'temp': parts[0].trim(),
              'hum': parts[1].trim(),
            });
          }
        } catch (e) {
          // Abaikan kalau gagal parsing
        }
      });
      return true;
    } else {
      client!.disconnect();
      return false;
    }
  }

  void publishWatering(bool state) {
    if (client != null &&
        client!.connectionStatus!.state == MqttConnectionState.connected) {
      final builder = MqttClientPayloadBuilder();
      builder.addString(state ? "ON" : "OFF");
      client!.publishMessage(
        topicAktuator,
        MqttQos.atMostOnce,
        builder.payload!,
      );
    }
  }

  void dispose() {
    client?.disconnect();
    _sensorDataController.close();
  }
}
