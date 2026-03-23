import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart' as fln;
import 'package:recon/auxiliary.dart';
import 'package:recon/models/invite_request.dart';
import 'package:recon/models/message.dart';
import 'package:recon/models/session.dart';

class NotificationChannel {
  final String id;
  final String name;
  final String description;

  const NotificationChannel({required this.name, required this.id, required this.description});
}

class NotificationClient {
  static const NotificationChannel _messageChannel = NotificationChannel(
    id: "messages",
    name: "Messages",
    description: "Messages received from your friends",
  );
  static const String _windowsAppName = "ReCon";
  static const String _windowsAppUserModelId = "de.voidspace.recon";
  static const String _windowsGuid = "f4d0e6f9-8f19-4f32-91b2-40b66b0b4f77";

  final fln.FlutterLocalNotificationsPlugin _notifier = fln.FlutterLocalNotificationsPlugin();
  late final Future<bool?> _initialization = _notifier.initialize(
    const fln.InitializationSettings(
      android: fln.AndroidInitializationSettings("ic_notification"),
      iOS: fln.DarwinInitializationSettings(),
      macOS: fln.DarwinInitializationSettings(),
      linux: fln.LinuxInitializationSettings(defaultActionName: "Open ReCon"),
      windows: fln.WindowsInitializationSettings(
        appName: _windowsAppName,
        appUserModelId: _windowsAppUserModelId,
        guid: _windowsGuid,
      ),
    ),
  );

  Future<void> _ensureInitialized() async {
    final result = await _initialization;
    if (result == false) {
      throw StateError("Notification client failed to initialize");
    }
  }

  String _messagePreview(Message message) {
    switch (message.type) {
      case MessageType.unknown:
        return "Unknown Message Type";
      case MessageType.text:
        return message.formattedContent.toString().stripHtml();
      case MessageType.sound:
        return "Audio Message";
      case MessageType.sessionInvite:
        try {
          final session = Session.fromMap(jsonDecode(message.content));
          return "Session Invite to ${session.formattedName}";
        } catch (e) {
          return "Session Invite";
        }
      case MessageType.object:
        return "Asset";
      case MessageType.inviteRequest:
        try {
          final request = InviteRequest.fromMap(jsonDecode(message.content));
          return "${request.usernameToInvite} Requested an Invite";
        } catch (e) {
          return "Invite Request";
        }
    }
  }

  String _notificationBody(List<Message> messages) {
    if (messages.length == 1) {
      return _messagePreview(messages.single);
    }

    final latestPreview = _messagePreview(messages.last);
    return "${messages.length} unread messages. Latest: $latestPreview";
  }

  String _senderLabel(String senderId, Map<String, String> senderNames) {
    final senderName = senderNames[senderId]?.trim();
    if (senderName != null && senderName.isNotEmpty) {
      return senderName;
    }

    return senderId.stripUid();
  }

  Future<void> showUnreadMessagesNotification(
    Iterable<Message> messages, {
    Map<String, String> senderNames = const {},
  }) async {
    if (messages.isEmpty) return;

    await _ensureInitialized();

    final bySender = groupBy(messages, (p0) => p0.senderId);

    for (final entry in bySender.entries) {
      final senderMessages = entry.value.toList(growable: false);
      final senderLabel = _senderLabel(entry.key, senderNames);
      await _notifier.show(
        entry.key.hashCode,
        senderLabel,
        _notificationBody(senderMessages),
        fln.NotificationDetails(
          android: fln.AndroidNotificationDetails(
            _messageChannel.id,
            _messageChannel.name,
            channelDescription: _messageChannel.description,
            importance: fln.Importance.high,
            priority: fln.Priority.max,
            actions: [],
            //TODO: Make clicking message notification open chat of specified user.
            styleInformation: fln.MessagingStyleInformation(
              fln.Person(
                name: senderLabel,
                bot: false,
              ),
              groupConversation: false,
              messages: senderMessages.map((message) {
                return fln.Message(
                  _messagePreview(message),
                  message.sendTime.toLocal(),
                  fln.Person(
                    name: senderLabel,
                    bot: false,
                  ),
                );
              }).toList(),
            ),
          ),
          windows: fln.WindowsNotificationDetails(
            subtitle: senderMessages.length == 1 ? null : "${senderMessages.length} unread messages",
          ),
        ),
      );
    }
  }
}
