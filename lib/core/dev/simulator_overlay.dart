import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../bluetooth/ble_service.dart';
import '../bluetooth/simulated_ble_service.dart';

/// Presets de intensidad: (nombre, watts, spm)
const _presets = [
  ('Suave', 100, 20),
  ('Medio', 180, 24),
  ('Fuerte', 280, 30),
];

/// Cinta "SIMULADOR" + panel flotante para controlar el remo simulado.
/// Se monta en MaterialApp.builder (encima del Navigator): no hay Overlay,
/// así que no usar Tooltip, Slider ni bottom sheets acá.
class SimulatorOverlay extends StatefulWidget {
  const SimulatorOverlay({super.key, required this.child});

  final Widget child;

  @override
  State<SimulatorOverlay> createState() => _SimulatorOverlayState();
}

class _SimulatorOverlayState extends State<SimulatorOverlay> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Banner(
      message: 'SIMULADOR',
      location: BannerLocation.topStart,
      color: Colors.deepOrange,
      child: Stack(
        children: [
          widget.child,
          Positioned(
            right: 16,
            bottom: 96, // por encima de la NavigationBar
            child: _open
                ? _SimulatorPanel(onClose: () => setState(() => _open = false))
                : FloatingActionButton.small(
                    heroTag: null,
                    onPressed: () => setState(() => _open = true),
                    child: const Icon(Icons.build),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SimulatorPanel extends StatefulWidget {
  const _SimulatorPanel({required this.onClose});

  final VoidCallback onClose;

  @override
  State<_SimulatorPanel> createState() => _SimulatorPanelState();
}

class _SimulatorPanelState extends State<_SimulatorPanel> {
  // Se lee en cada uso: tras un hot reload RowerApp crea otro servicio,
  // pero el Provider conserva el original (el que emite los datos).
  SimulatedBleService get _ble =>
      context.read<BleService>() as SimulatedBleService;

  @override
  Widget build(BuildContext context) {
    final sim = _ble.simulator;
    // Altura acotada + scroll: en ventanas bajas (landscape, ventana chica)
    // el panel no debe pasarse del borde superior y tapar el botón de cerrar.
    final maxHeight = MediaQuery.sizeOf(context).height -
        96 -
        MediaQuery.paddingOf(context).top -
        16;
    return Card(
      elevation: 8,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 280,
          maxWidth: 280,
          maxHeight: maxHeight < 120 ? 120 : maxHeight,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Simulador', style: Theme.of(context).textTheme.titleMedium),
                  const Spacer(),
                  IconButton(
                    key: const Key('sim-close'),
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                children: [
                  for (final (name, watts, spm) in _presets)
                    ActionChip(
                      label: Text(name),
                      onPressed: () => setState(() {
                        sim.targetWatts = watts;
                        sim.targetSpm = spm;
                      }),
                    ),
                ],
              ),
              _StepperRow(
                label: 'Watts',
                value: '${sim.targetWatts} W',
                keyPrefix: 'sim-watts',
                onMinus: () => setState(() => sim.targetWatts -= 10),
                onPlus: () => setState(() => sim.targetWatts += 10),
              ),
              _StepperRow(
                label: 'Ritmo',
                value: '${sim.targetSpm} spm',
                keyPrefix: 'sim-spm',
                onMinus: () => setState(() => sim.targetSpm -= 1),
                onPlus: () => setState(() => sim.targetSpm += 1),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Remando'),
                value: sim.rowing,
                onChanged: (v) => setState(() => sim.rowing = v),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.link_off),
                label: const Text('Simular desconexión'),
                onPressed: () => _ble.simulateDisconnect(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.label,
    required this.value,
    required this.keyPrefix,
    required this.onMinus,
    required this.onPlus,
  });

  final String label;
  final String value;
  final String keyPrefix;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        IconButton(
          key: Key('$keyPrefix-minus'),
          icon: const Icon(Icons.remove),
          onPressed: onMinus,
        ),
        SizedBox(
          width: 72,
          child: Text(value, textAlign: TextAlign.center),
        ),
        IconButton(
          key: Key('$keyPrefix-plus'),
          icon: const Icon(Icons.add),
          onPressed: onPlus,
        ),
      ],
    );
  }
}
