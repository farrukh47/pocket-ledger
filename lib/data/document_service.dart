import 'package:flutter/services.dart';

class DocumentService {
  static const _channel = MethodChannel('pocket_ledger/documents');
  static Future<bool> save(String name, String content, String mime) async =>
    await _channel.invokeMethod<bool>('save',
      {'name': name, 'content': content, 'mime': mime}) ?? false;
  static Future<String?> openBackup() => _channel.invokeMethod<String>('open');
}
