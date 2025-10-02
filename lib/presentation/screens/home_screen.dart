import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:steps_counter_sensor_app/presentation/screens/history_screen.dart';
import 'package:steps_counter_sensor_app/providers/step_provider.dart';
import 'package:steps_counter_sensor_app/services/auth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AuthService _authService;
  bool _isPermissionGranted = false;
  bool _isCheckingPermission = true;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _authService = context
        .read<AuthService>(); // Use Provider instead of creating new instance

    // Pulse animation for step counter
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Request permission after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestPermission();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _requestPermission() async {
    final status = await Permission.activityRecognition.request();

    setState(() {
      _isPermissionGranted = status.isGranted;
      _isCheckingPermission = false;
    });

    if (!status.isGranted && mounted) {
      _showPermissionDialog();
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
          'Activity recognition permission is needed to count your steps. Please grant permission in settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      context.read<StepProvider>().stopListening();
      await _authService.logout();
      if (mounted) Navigator.pushReplacementNamed(context, '/');
    }
  }

  void _showLocalDataDialog() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getStringList('step_data') ?? [];

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Local Storage'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Total Entries: ${data.length}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              if (data.isEmpty)
                const Text('No local data stored')
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: data.length > 5 ? 5 : data.length,
                    itemBuilder: (context, index) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        '${index + 1}. ${data[index].substring(0, data[index].length > 50 ? 50 : data[index].length)}...',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
              if (data.length > 5)
                Text(
                  '\n... and ${data.length - 5} more entries',
                  style: const TextStyle(fontStyle: FontStyle.italic),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stepProvider = Provider.of<StepProvider>(context);
    const dailyGoal = 10000;
    final progress = (stepProvider.sessionSteps / dailyGoal).clamp(0.0, 1.0);

    // Trigger pulse animation when steps increase
    if (stepProvider.isRunning) {
      _pulseController.forward(from: 0);
    }

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        title: const Text(
          'Step Counter',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF667eea), Color(0xFF764ba2)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        actions: [
          IconButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HistoryScreen()),
            ),
            icon: const Icon(Icons.history_rounded, color: Colors.white),
            tooltip: 'View History',
          ),
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'Logout',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [const Color(0xFF667eea).withOpacity(0.1), Colors.white],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: _isCheckingPermission
            ? const Center(child: CircularProgressIndicator())
            : !_isPermissionGranted
            ? _buildPermissionRequired()
            : _buildMainContent(stepProvider, dailyGoal, progress),
      ),
    );
  }

  Widget _buildPermissionRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline_rounded, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 24),
            const Text(
              'Permission Required',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'We need activity recognition permission to count your steps',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _requestPermission,
              icon: const Icon(Icons.refresh),
              label: const Text('Grant Permission'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent(
    StepProvider stepProvider,
    int dailyGoal,
    double progress,
  ) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            // Step Counter Card
            ScaleTransition(
              scale: _pulseAnimation,
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF667eea), Color(0xFF764ba2)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF667eea).withOpacity(0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    const Icon(
                      Icons.directions_walk_rounded,
                      size: 48,
                      color: Colors.white70,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      '${stepProvider.sessionSteps}',
                      style: const TextStyle(
                        fontSize: 64,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: -2,
                      ),
                    ),
                    const Text(
                      'Steps Today',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Progress Section
            _buildProgressCard(progress, stepProvider.sessionSteps, dailyGoal),
            const SizedBox(height: 32),

            // Control Buttons
            _buildControlButtons(stepProvider),
            const SizedBox(height: 20),

            // Utility Buttons
            _buildUtilityButtons(stepProvider),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard(double progress, int currentSteps, int dailyGoal) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Daily Goal',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF667eea),
                ),
              ),
              Text(
                '${(progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF764ba2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: Colors.grey[200],
              valueColor: const AlwaysStoppedAnimation(Color(0xFF667eea)),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '$currentSteps / $dailyGoal steps',
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildControlButtons(StepProvider stepProvider) {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            label: 'Start',
            icon: Icons.play_arrow_rounded,
            color: const Color(0xFF4CAF50),
            onPressed: stepProvider.isRunning
                ? null
                : () => stepProvider.startListening(
                    _authService.currentUser?.uid ?? '',
                  ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            label: 'Stop',
            icon: Icons.stop_rounded,
            color: const Color(0xFFEF5350),
            onPressed: stepProvider.isRunning
                ? stepProvider.stopListening
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildUtilityButtons(StepProvider stepProvider) {
    return Row(
      children: [
        Expanded(
          child: _buildActionButton(
            label: 'Simulate',
            icon: Icons.add_circle_outline_rounded,
            color: const Color(0xFF42A5F5),
            onPressed: stepProvider.isRunning
                ? stepProvider.simulateStep
                : null,
            isOutlined: true,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionButton(
            label: 'Local Data',
            icon: Icons.storage_rounded,
            color: const Color(0xFF78909C),
            onPressed: _showLocalDataDialog,
            isOutlined: true,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    bool isOutlined = false,
  }) {
    return SizedBox(
      height: 56,
      child: isOutlined
          ? OutlinedButton.icon(
              onPressed: onPressed,
              icon: Icon(
                icon,
                size: 20,
                color: onPressed == null ? Colors.grey : color,
              ),
              label: Text(
                label,
                style: TextStyle(
                  color: onPressed == null ? Colors.grey : color,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: color,
                side: BorderSide(
                  color: onPressed == null ? Colors.grey : color,
                  width: 2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledForegroundColor: Colors.grey[400],
              ),
            )
          : ElevatedButton.icon(
              onPressed: onPressed,
              icon: Icon(icon, size: 20, color: Colors.white),
              label: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: onPressed == null ? Colors.grey[300] : color,
                foregroundColor: Colors.white,
                elevation: onPressed == null ? 0 : 4,
                shadowColor: color.withOpacity(0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                disabledBackgroundColor: Colors.grey[300],
                disabledForegroundColor: Colors.grey[600],
              ),
            ),
    );
  }
}
