import 'package:flutter/material.dart';
import 'package:steps_counter_sensor_app/services/step_counter_service.dart';

class StepDisplayWidget extends StatefulWidget {
  const StepDisplayWidget({super.key});

  @override
  State<StepDisplayWidget> createState() => _StepDisplayWidgetState();
}

class _StepDisplayWidgetState extends State<StepDisplayWidget> {
  final StepCounterService _stepService = StepCounterService();
  int _steps = 0;

  @override
  void initState() {
    super.initState();
    _stepService.stepCountStream.listen(
      (steps) {
        setState(() {
          _steps = steps;
        });
      },
      onError: (error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $error')));
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('Steps: $_steps', style: const TextStyle(fontSize: 48)),
        const Text('Data is being collected and synced to Firebase.'),
      ],
    );
  }
}
