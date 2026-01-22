import 'package:flutter/material.dart';

/// Card widget for displaying a single telemetry value
class TelemetryCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final IconData icon;
  final Color? backgroundColor;
  final Color? textColor;
  final bool isWarning;
  final bool isCritical;

  const TelemetryCard({
    super.key,
    required this.title,
    required this.value,
    required this.unit,
    required this.icon,
    this.backgroundColor,
    this.textColor,
    this.isWarning = false,
    this.isCritical = false,
  });

  Color _getBackgroundColor() {
    if (isCritical) return Colors.red.shade700;
    if (isWarning) return Colors.orange.shade600;
    return backgroundColor ?? Colors.blueGrey.shade800;
  }

  Color _getTextColor() {
    if (isCritical || isWarning) return Colors.white;
    return textColor ?? Colors.white;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      decoration: BoxDecoration(
        color: _getBackgroundColor(),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _getBackgroundColor().withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: _getTextColor().withOpacity(0.8), size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: _getTextColor().withOpacity(0.8),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isCritical) ...[
                  const Spacer(),
                  _buildPulsingIndicator(),
                ],
              ],
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    color: _getTextColor(),
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    unit,
                    style: TextStyle(
                      color: _getTextColor().withOpacity(0.7),
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            if (isCritical)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'CRITICAL - LAND IMMEDIATELY',
                  style: TextStyle(
                    color: Colors.yellow.shade300,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            if (isWarning && !isCritical)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'WARNING - LOW BATTERY',
                  style: TextStyle(
                    color: Colors.yellow.shade100,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPulsingIndicator() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.5, end: 1.0),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, child) {
        return Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: Colors.yellow.withOpacity(value),
            shape: BoxShape.circle,
          ),
        );
      },
      onEnd: () {},
    );
  }
}

/// Battery gauge widget with visual indicator
class BatteryGauge extends StatelessWidget {
  final double voltage;
  final double percentage;
  final bool isWarning;
  final bool isCritical;

  const BatteryGauge({
    super.key,
    required this.voltage,
    required this.percentage,
    required this.isWarning,
    required this.isCritical,
  });

  Color _getColor() {
    if (isCritical) return Colors.red;
    if (isWarning) return Colors.orange;
    if (percentage > 50) return Colors.green;
    return Colors.yellow;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blueGrey.shade900,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.battery_full, color: _getColor()),
              const SizedBox(width: 8),
              const Text(
                'Battery Level',
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percentage / 100,
              minHeight: 20,
              backgroundColor: Colors.grey.shade800,
              valueColor: AlwaysStoppedAnimation<Color>(_getColor()),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${percentage.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: _getColor(),
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${voltage.toStringAsFixed(2)}V',
                style: const TextStyle(color: Colors.white54, fontSize: 16),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
