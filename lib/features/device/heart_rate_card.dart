import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:provider/provider.dart';
import 'package:rowmate/l10n/app_localizations.dart';
import '../../core/bluetooth/ble_service.dart';
import '../../core/bluetooth/heart_rate_service.dart';
import '../../shared/theme.dart';
import 'device_provider.dart';
import 'heart_rate_provider.dart';

/// Tarjeta "Pulsómetro" de la pestaña Dispositivo: buscar, conectar,
/// ver el pulso en vivo y desconectar/olvidar el sensor recordado.
class HeartRateCard extends StatelessWidget {
  const HeartRateCard({super.key});

  static const _color = MetricColors.heartRate;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hr = context.watch<HeartRateProvider>();
    final rowerStatus = context.select<DeviceProvider, BleStatus>((p) => p.status);
    final rowerBusy =
        rowerStatus == BleStatus.scanning || rowerStatus == BleStatus.connecting;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2E45),
        borderRadius: BorderRadius.circular(16),
        border: Border(top: BorderSide(color: _color.withValues(alpha: 0.6), width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.favorite,
                  size: 14, color: hr.isConnected ? _color : _color.withValues(alpha: 0.4)),
              const SizedBox(width: 6),
              Text(l10n.hrmTitle.toUpperCase(),
                  style: TextStyle(
                      fontSize: 12,
                      color: _color.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8)),
            ],
          ),
          const SizedBox(height: 12),
          _body(hr, l10n, rowerBusy),
          if (hr.error != null) ...[
            const SizedBox(height: 8),
            Text(
              HeartRateProvider.isIncompatible(hr.error!)
                  ? l10n.hrmIncompatible
                  : l10n.hrmConnectError('${hr.error}'),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _body(HeartRateProvider hr, AppLocalizations l10n, bool rowerBusy) {
    switch (hr.status) {
      case HrmStatus.connected:
        return _connected(hr, l10n);
      case HrmStatus.connecting:
        // Reintento automático (cada intento tarda hasta 15 s): mostrar el
        // estado "recordado · reconectando..." con Olvidar / Buscar otro, para
        // no dejar al usuario sin controles durante la reconexión.
        if (hr.isRetrying && hr.hasRemembered) {
          return _remembered(hr, l10n, rowerBusy);
        }
        return Row(
          children: [
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.hrmConnectingTo(hr.connectingName))),
          ],
        );
      case HrmStatus.scanning:
        return _scanning(hr, l10n);
      case HrmStatus.disconnected:
        return hr.hasRemembered
            ? _remembered(hr, l10n, rowerBusy)
            : _noSensor(hr, l10n, rowerBusy);
    }
  }

  Widget _noSensor(HeartRateProvider hr, AppLocalizations l10n, bool rowerBusy) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.hrmNoSensor,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(l10n.hrmWatchHint,
            style: const TextStyle(fontSize: 12, color: Colors.white38)),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          key: const Key('hrm-search'),
          onPressed: rowerBusy ? null : hr.startScan,
          icon: const Icon(Icons.bluetooth_searching, size: 18),
          label: Text(l10n.hrmSearch),
        ),
      ],
    );
  }

  Widget _scanning(HeartRateProvider hr, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 12),
            Text(l10n.hrmSearching,
                style: const TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
        // Material transparente propio: el fondo de la tarjeta taparía las
        // salpicaduras del ListTile (y Flutter lo señala con un assert).
        for (final r in hr.scanResults)
          Material(
            type: MaterialType.transparency,
            child: ListTile(
              key: Key('hrm-device-${r.device.remoteId.str}'),
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.favorite_border, color: _color),
              title: Text(_nameOf(r, l10n)),
              subtitle: Text(r.device.remoteId.str,
                  style: const TextStyle(fontSize: 11, color: Colors.white38)),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => hr.connect(r.device, name: _nameOf(r, l10n)),
            ),
          ),
      ],
    );
  }

  Widget _connected(HeartRateProvider hr, AppLocalizations l10n) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(hr.connectedDeviceName ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, color: Colors.white70)),
              const SizedBox(height: 4),
              // Con texto grande el número se encoge en vez de desbordar.
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(hr.bpm > 0 ? '${hr.bpm}' : '--',
                        style: const TextStyle(
                            fontSize: 52,
                            fontWeight: FontWeight.w800,
                            color: _color,
                            height: 1)),
                    const SizedBox(width: 6),
                    Text(l10n.hrmBpm,
                        style: TextStyle(
                            fontSize: 14, color: _color.withValues(alpha: 0.7))),
                  ],
                ),
              ),
            ],
          ),
        ),
        TextButton.icon(
          key: const Key('hrm-disconnect'),
          onPressed: hr.disconnect,
          icon: const Icon(Icons.bluetooth_disabled, size: 18),
          label: Text(l10n.hrmDisconnect),
          style: TextButton.styleFrom(foregroundColor: Colors.red.shade300),
        ),
      ],
    );
  }

  Widget _remembered(HeartRateProvider hr, AppLocalizations l10n, bool rowerBusy) {
    final suffix = hr.isRetrying ? l10n.hrmReconnecting : l10n.hrmNotFound;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${hr.rememberedDeviceName} · $suffix',
            style: const TextStyle(fontSize: 14, color: Colors.white70)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            FilledButton.tonalIcon(
              key: const Key('hrm-retry'),
              onPressed: hr.isRetrying || rowerBusy ? null : hr.retry,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(l10n.hrmConnect),
            ),
            OutlinedButton(
              key: const Key('hrm-search'),
              onPressed: rowerBusy ? null : hr.startScan,
              child: Text(l10n.hrmSearchOther),
            ),
            TextButton(
              key: const Key('hrm-forget'),
              onPressed: hr.forget,
              child: Text(l10n.hrmForget),
            ),
          ],
        ),
      ],
    );
  }

  static String _nameOf(ScanResult r, AppLocalizations l10n) {
    final n = r.device.platformName.isNotEmpty
        ? r.device.platformName
        : r.advertisementData.advName;
    return n.isNotEmpty ? n : l10n.hrmUnknownSensor;
  }
}
