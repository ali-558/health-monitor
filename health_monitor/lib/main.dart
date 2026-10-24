import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:overlay_support/overlay_support.dart';
import 'dart:async';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:vibration/vibration.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return OverlaySupport.global(
      child: MaterialApp(
        title: 'Health Monitor',
        theme: ThemeData(
          primarySwatch: Colors.teal,
          useMaterial3: true,
        ),
        home: HomeScreen(),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  double _heartRate = 75.0;
  double _spo2 = 98.0;
  double _temperature = 36.8;

  Map<String, dynamic>? _analysisData;
  bool _isAnalyzing = false;
  int _selectedIndex = 0;
  List<Map<String, String>> _chatHistory = [];
  TextEditingController _chatController = TextEditingController();
  bool _isChatLoading = false;
  final String _backendUrl = 'http://192.168.1.101:8000';
  Timer? _monitoringTimer;
  bool _isMonitoring = false;
  String _lastStatus = 'NORMAL';
  Timer? _pollingTimer;
  bool _isConnected = false;
  String _lastUpdate = 'Never';
  String _lastTimestamp = '';
  List<FlSpot> _ecgData = [];
  double _ecgXCounter = 0;
  WebSocketChannel? _ecgChannel;
  bool _ecgConnected = false;
  final int _maxEcgPoints = 1250;

  @override
  void initState() {
    super.initState();
    _startPolling();
  }

  void _connectEcgWebSocket() {
    try {
      _ecgChannel = WebSocketChannel.connect(
        Uri.parse('ws://192.168.1.165:81'),
      );
      setState(() => _ecgConnected = true);
      _ecgChannel!.stream.listen(
        (data) {
          final samples = data.toString().split(',');
          setState(() {
            for (var sample in samples) {
              final value = double.tryParse(sample.trim());
              if (value != null) {
                _ecgData.add(FlSpot(_ecgXCounter, value));
                _ecgXCounter += 1;
                if (_ecgData.length > _maxEcgPoints) {
                  _ecgData.removeAt(0);
                }
              }
            }
          });
        },
        onError: (error) {
          setState(() => _ecgConnected = false);
          Future.delayed(Duration(seconds: 3), () {
            if (mounted) _connectEcgWebSocket();
          });
        },
        onDone: () {
          setState(() => _ecgConnected = false);
        },
      );
    } catch (e) {
      setState(() => _ecgConnected = false);
    }
  }

  void _disconnectEcgWebSocket() {
    _ecgChannel?.sink.close();
    setState(() {
      _ecgConnected = false;
      _ecgData.clear();
      _ecgXCounter = 0;
    });
  }

  void _startPolling() {
    FirebaseFirestore.instance
        .collection('users')
        .doc('esp32_user')
        .collection('readings')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        final reading = snapshot.docs.first.data();
        setState(() {
          _heartRate = (reading['ppg'] ?? _heartRate).toDouble();
          _spo2 = (reading['spo2'] ?? _spo2).toDouble();
          _temperature = (reading['temperature'] ?? _temperature).toDouble();
          _isConnected = true;
          _lastUpdate = 'Live';
        });
      }
    }, onError: (e) {
      setState(() {
        _isConnected = false;
        _lastUpdate = 'Connection lost';
      });
    });
    _fetchLatestReading();
    _pollingTimer = Timer.periodic(Duration(seconds: 10), (_) {
      _fetchLatestReading();
    });
  }

  Future<void> _fetchLatestReading() async {
    try {
      final response = await http.get(
        Uri.parse('$_backendUrl/user/esp32_user/latest'),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data['reading'] != null) {
          final reading = data['reading'];
          setState(() {
            _heartRate = (reading['ppg'] ?? _heartRate).toDouble();
            _spo2 = (reading['spo2'] ?? _spo2).toDouble();
            _temperature = (reading['temperature'] ?? _temperature).toDouble();
            _isConnected = true;
            _lastUpdate = 'Just now';
            final newTimestamp = data['reading']['timestamp'] ?? '';
            if (newTimestamp != _lastTimestamp && newTimestamp != '') {
              _lastTimestamp = newTimestamp;
              _analyzeVitals();
            }
          });
        }
      }
    } catch (e) {
      setState(() {
        _isConnected = false;
        _lastUpdate = 'Connection lost';
      });
    }
  }

  void _startMonitoring() {
    setState(() => _isMonitoring = true);
    _analyzeVitals();
    _monitoringTimer = Timer.periodic(Duration(seconds: 30), (_) {
      _analyzeVitals();
    });
  }

  void _stopMonitoring() {
    _monitoringTimer?.cancel();
    setState(() => _isMonitoring = false);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> _screens = [
      _buildVitalsScreen(),
      _buildEcgScreen(),
      _buildChatScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedIndex == 0 ? 'Health Monitor' : _selectedIndex == 1 ? 'ECG Monitor' : 'Ask AI'),
        backgroundColor: Colors.teal,
        elevation: 0,
      ),
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        selectedItemColor: Colors.teal,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.favorite),
            label: 'Vitals',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.monitor_heart),
            label: 'ECG',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: 'Ask AI',
          ),
        ],
      ),
    );
  }

  Widget _buildVitalsScreen() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _isConnected ? Colors.green.shade50 : Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _isConnected ? Colors.green.shade200 : Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.circle, size: 10, color: _isConnected ? Colors.green : Colors.red),
                SizedBox(width: 8),
                Text(
                  _isConnected ? 'Live from ESP32 sensors' : 'Waiting for sensor data...',
                  style: TextStyle(fontSize: 13, color: _isConnected ? Colors.green.shade700 : Colors.red.shade700),
                ),
                Spacer(),
                Text(_lastUpdate, style: TextStyle(fontSize: 11, color: Colors.grey)),
              ],
            ),
          ),
          _buildVitalCard('Heart Rate', '${_heartRate.toInt()} bpm', Icons.favorite, Colors.red),
          SizedBox(height: 12),
          _buildVitalCard('SpO2', '${_spo2.toInt()}%', Icons.air, Colors.blue),
          SizedBox(height: 12),
          _buildVitalCard('Temperature', '${_temperature.toStringAsFixed(1)} \u00b0C', Icons.thermostat, Colors.orange),
          SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isAnalyzing ? null : (_isMonitoring ? _stopMonitoring : _startMonitoring),
              icon: _isAnalyzing
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                  : Icon(_isMonitoring ? Icons.stop_circle : Icons.monitor_heart),
              label: Text(
                _isAnalyzing ? 'Analyzing...' : (_isMonitoring ? 'Stop Monitoring' : 'Start Monitoring'),
                style: TextStyle(fontSize: 16),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isMonitoring ? Colors.red : Colors.teal,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          if (_isMonitoring)
            Padding(
              padding: EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.circle, color: Colors.green, size: 10),
                  SizedBox(width: 6),
                  Text(
                    'Monitoring active - checking every 30 seconds',
                    style: TextStyle(fontSize: 12, color: Colors.green[700]),
                  ),
                ],
              ),
            ),
          SizedBox(height: 24),
          if (_analysisData != null) _buildAnalysisCard(),
        ],
      ),
    );
  }

  Widget _buildEcgScreen() {
    return Column(
      children: [
        Container(
          padding: EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.circle, size: 10, color: _ecgConnected ? Colors.green : Colors.red),
              SizedBox(width: 8),
              Text(
                _ecgConnected ? 'ECG Live Stream' : 'ECG Disconnected',
                style: TextStyle(fontSize: 14, color: _ecgConnected ? Colors.green[700] : Colors.red[700]),
              ),
              Spacer(),
              ElevatedButton.icon(
                onPressed: _ecgConnected ? _disconnectEcgWebSocket : _connectEcgWebSocket,
                icon: Icon(_ecgConnected ? Icons.stop : Icons.play_arrow, size: 18),
                label: Text(_ecgConnected ? 'Stop' : 'Start'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _ecgConnected ? Colors.red : Colors.teal,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(8),
            child: _ecgData.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.monitor_heart, size: 64, color: Colors.grey[300]),
                        SizedBox(height: 16),
                        Text('Press Start to view ECG waveform', style: TextStyle(fontSize: 16, color: Colors.grey[600])),
                        SizedBox(height: 8),
                        Text('Real-time 250Hz ECG from AD8232', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  )
                : LineChart(
                    LineChartData(
                      gridData: FlGridData(show: true, drawVerticalLine: false, horizontalInterval: 500,
                        getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.withOpacity(0.2), strokeWidth: 1)),
                      titlesData: FlTitlesData(show: false),
                      borderData: FlBorderData(show: false),
                      minY: 0,
                      maxY: 4095,
                      lineTouchData: LineTouchData(enabled: false),
                      clipData: FlClipData.all(),
                      lineBarsData: [
                        LineChartBarData(
                          spots: _ecgData,
                          isCurved: false,
                          color: Colors.green,
                          barWidth: 1.5,
                          dotData: FlDotData(show: false),
                          belowBarData: BarAreaData(show: false),
                        ),
                      ],
                    ),
                    duration: Duration.zero,
                  ),
          ),
        ),
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            border: Border(top: BorderSide(color: Colors.grey[300]!)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Column(children: [
                Text('Sample Rate', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text('250 Hz', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              Column(children: [
                Text('Filter', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text('Moving Avg', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
              Column(children: [
                Text('Points', style: TextStyle(fontSize: 11, color: Colors.grey)),
                Text('${_ecgData.length}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              ]),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatScreen() {
    return Column(
      children: [
        Expanded(
          child: _chatHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[300]),
                      SizedBox(height: 16),
                      Text(
                        'Ask me about your health',
                        style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Your vitals: HR ${_heartRate.toInt()}, SpO2 ${_spo2.toInt()}%, Temp ${_temperature.toStringAsFixed(1)}\u00b0C',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: EdgeInsets.all(16),
                  reverse: true,
                  itemCount: _chatHistory.length,
                  itemBuilder: (context, index) {
                    final reverseIndex = _chatHistory.length - 1 - index;
                    final message = _chatHistory[reverseIndex];
                    final isUser = message['role'] == 'user';

                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: EdgeInsets.only(bottom: 12),
                        padding: EdgeInsets.all(12),
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.75,
                        ),
                        decoration: BoxDecoration(
                          color: isUser ? Colors.teal : Colors.grey[200],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          message['content']!,
                          style: TextStyle(
                            color: isUser ? Colors.white : Colors.black87,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        if (_isChatLoading)
          Padding(
            padding: EdgeInsets.all(8),
            child: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('AI is thinking...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          ),
        Container(
          padding: EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -2)),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _chatController,
                  decoration: InputDecoration(
                    hintText: 'Ask about your health...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  onSubmitted: (_) => _sendChatMessage(),
                ),
              ),
              SizedBox(width: 8),
              FloatingActionButton(
                mini: true,
                onPressed: _isChatLoading ? null : _sendChatMessage,
                backgroundColor: Colors.teal,
                child: Icon(Icons.send, color: Colors.white, size: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _sendChatMessage() async {
    if (_chatController.text.trim().isEmpty) return;

    final userMessage = _chatController.text.trim();
    _chatController.clear();

    setState(() {
      _chatHistory.add({'role': 'user', 'content': userMessage});
      _isChatLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'message': userMessage,
          'vitals': {
            'hr': _heartRate,
            'spo2': _spo2,
            'temp': _temperature,
          },
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _chatHistory.add({
            'role': 'assistant',
            'content': data['response'],
          });
        });
      } else {
        _showError('Chat failed: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Connection error: $e');
    } finally {
      setState(() => _isChatLoading = false);
    }
  }

  Widget _buildVitalCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                SizedBox(height: 4),
                Text(value, style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_getStatusIcon(_analysisData!['status']), color: _getStatusColor(_analysisData!['status']), size: 32),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_analysisData!['status'] ?? 'ANALYZING', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: _getStatusColor(_analysisData!['status']))),
                      Text(_analysisData!['reason'] ?? 'Processing...', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _showRecommendationsBottomSheet(context),
                icon: Icon(Icons.medical_information),
                label: Text('View Recommendations'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _analyzeVitals() async {
    setState(() => _isAnalyzing = true);

    try {
      final response = await http.post(
        Uri.parse('$_backendUrl/analyze'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': 'app_user',
          'deviceID': 'flutter_app',
          'ecg': _heartRate,
          'ppg': _heartRate,
          'temperature': _temperature,
          'spo2': _spo2,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() => _analysisData = data);
        _showSmartNotification(data);
      } else {
        _showError('Analysis failed: ${response.statusCode}');
      }
    } catch (e) {
      _showError('Connection error: $e');
    } finally {
      setState(() => _isAnalyzing = false);
    }
  }

  void _showSmartNotification(Map<String, dynamic> analysisData) {
    final status = analysisData['status'];
    final reason = analysisData['reason'] ?? 'Check your vitals';

    if (status == _lastStatus && status == 'NORMAL') return;
    _lastStatus = status;

    if (status == 'CRITICAL') {
      showSimpleNotification(
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.error, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('CRITICAL ALERT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 2),
                    Text(reason, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
        background: Colors.red,
        duration: Duration(seconds: 8),
        slideDismissDirection: DismissDirection.up,
        context: context,
      );
      Future.delayed(Duration(milliseconds: 500), () {
        if (mounted) _showRecommendationsBottomSheet(context);
      });
      Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
    } else if (status == 'WARNING') {
      showSimpleNotification(
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.white, size: 24),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Health Advisory', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    SizedBox(height: 2),
                    Text(reason, style: TextStyle(color: Colors.white.withOpacity(0.9), fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
        ),
        background: Colors.orange,
        duration: Duration(seconds: 5),
        slideDismissDirection: DismissDirection.up,
        context: context,
      );
      Vibration.vibrate(duration: 300);
    } else {
      HapticFeedback.selectionClick();
    }
  }

  void _showRecommendationsBottomSheet(BuildContext context) {
    if (_analysisData == null) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.75,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(margin: EdgeInsets.only(top: 10), width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            Container(
              padding: EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.medical_information, color: _getStatusColor(_analysisData!['status']), size: 28),
                  SizedBox(width: 12),
                  Expanded(child: Text('Health Recommendations', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                  IconButton(icon: Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: _getStatusColor(_analysisData!['status']).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _getStatusColor(_analysisData!['status'])),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_getStatusIcon(_analysisData!['status']), size: 16, color: _getStatusColor(_analysisData!['status'])),
                          SizedBox(width: 6),
                          Text(_analysisData!['status'] ?? 'UNKNOWN', style: TextStyle(color: _getStatusColor(_analysisData!['status']), fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(_analysisData!['reason'] ?? 'Analysis complete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, height: 1.3)),
                    SizedBox(height: 24),
                    if (_analysisData!['recommendations'] != null) ...[
                      _buildSectionHeader('What to do:', Icons.lightbulb, Colors.orange),
                      SizedBox(height: 12),
                      ...(_analysisData!['recommendations'] as List).map((rec) => _buildBulletPoint(rec, Colors.orange)).toList(),
                      SizedBox(height: 24),
                    ],
                    if (_analysisData!['causes'] != null) ...[
                      _buildSectionHeader('Possible causes:', Icons.psychology, Colors.purple),
                      SizedBox(height: 12),
                      ...(_analysisData!['causes'] as List).map((cause) => _buildBulletPoint(cause, Colors.purple)).toList(),
                      SizedBox(height: 24),
                    ],
                    if (_analysisData!['seek_care'] != null) ...[
                      Container(
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: _analysisData!['status'] == 'CRITICAL' ? Colors.red.shade50 : Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _analysisData!['status'] == 'CRITICAL' ? Colors.red.shade200 : Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.local_hospital, color: _analysisData!['status'] == 'CRITICAL' ? Colors.red.shade700 : Colors.orange.shade700, size: 20),
                                SizedBox(width: 8),
                                Text('When to seek medical care:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: _analysisData!['status'] == 'CRITICAL' ? Colors.red.shade900 : Colors.orange.shade900)),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(_analysisData!['seek_care'], style: TextStyle(fontSize: 14, height: 1.4, color: _analysisData!['status'] == 'CRITICAL' ? Colors.red.shade900 : Colors.orange.shade900)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 20),
        SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildBulletPoint(String text, Color color) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(margin: EdgeInsets.only(top: 6), width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(fontSize: 14, height: 1.4))),
        ],
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'NORMAL': return Colors.green;
      case 'WARNING': return Colors.orange;
      case 'CRITICAL': return Colors.red;
      default: return Colors.grey;
    }
  }

  IconData _getStatusIcon(String? status) {
    switch (status) {
      case 'NORMAL': return Icons.check_circle;
      case 'WARNING': return Icons.warning;
      case 'CRITICAL': return Icons.error;
      default: return Icons.help;
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _monitoringTimer?.cancel();
    _ecgChannel?.sink.close();
    _chatController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
