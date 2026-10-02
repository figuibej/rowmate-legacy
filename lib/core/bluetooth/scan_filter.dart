import 'dart:io';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// Filtro de resultados de escaneo por servicio anunciado.
///
/// En Android e iOS el filtro `withServices` lo aplica el sistema. En Windows
/// (`flutter_blue_plus_winrt`) y Linux el plugin lo ignora y entrega todos los
/// dispositivos BLE cercanos, así que hay que filtrar en el cliente por los
/// UUIDs anunciados. En iOS/macOS NO se filtra en el cliente: un servicio puede
/// viajar en los "overflow UUIDs" y no figurar en `serviceUuids` aunque el
/// sistema lo haya aceptado.
bool get scanFilterIsClientSide => Platform.isWindows || Platform.isLinux;

bool advertisesService(ScanResult r, Guid service) =>
    r.advertisementData.serviceUuids.contains(service);

/// true si [r] debe mostrarse como candidato para [service] en esta
/// plataforma. [clientSide] se inyecta en tests; por defecto depende del SO.
bool acceptScanResult(ScanResult r, Guid service, {bool? clientSide}) =>
    !(clientSide ?? scanFilterIsClientSide) || advertisesService(r, service);
