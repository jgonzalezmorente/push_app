import 'dart:io';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:push_app/config/local_notifications/local_notifications.dart';
import 'package:push_app/domain/entities/push_message.dart';
import 'package:push_app/firebase_options.dart';

part 'notifications_event.dart';
part 'notifications_state.dart';

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();  
}

class NotificationsBloc extends Bloc<NotificationsEvent, NotificationsState> {
  
  FirebaseMessaging messaging = FirebaseMessaging.instance;
  int pushNumberId = 0;

  final Future<void> Function()? requestLocalNotificationPermissions;  
  final void Function({ required int id, String? title, String? body, String? data })? showLocalNotification;  

  NotificationsBloc({ 
    this.requestLocalNotificationPermissions,
    this.showLocalNotification
  }) : super( const NotificationsState() ) {

    on<NotificationsStatusChanged>( _onNotificationsStatusChanged );    
    on<NotificationReceived>( _onPushMessageReceived );

    // Verificar estado de las notificaciones      
    _initialStatusCheck();

    // Listener para notificacioens en Foreground
    _onForegroundMessage();
  }

  static Future<void> initializeFCM() async {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform
    );
  }

  void _onNotificationsStatusChanged( NotificationsStatusChanged event, Emitter<NotificationsState> emit ) {
    emit( state.copyWith(
      status: event.status
    ));
    _getFCMToken();
  }

  void _onPushMessageReceived( NotificationReceived event, Emitter<NotificationsState> emit ) {    
    emit( state.copyWith(
      notifications: [ event.pushMessage, ...state.notifications ]
    ));
  }

  void _initialStatusCheck() async {
    final settings = await messaging.getNotificationSettings();
    add( NotificationsStatusChanged( settings.authorizationStatus ) );    
  }

  void _getFCMToken() async {    
    if ( state.status != AuthorizationStatus.authorized ) return;
    final token = await messaging.getToken();
    print( token );
  }

  void handleRemoteMessage( RemoteMessage message ) {    
    if (message.notification == null) return; 
    final notification = PushMessage(
      messageId: message.messageId?.replaceAll(':', '').replaceAll('%', '') ?? '',
      title: message.notification!.title ?? '',
      body: message.notification!.body ?? '',
      sendDate: message.sentTime ?? DateTime.now(),
      data: message.data,
      imageUrl: Platform.isAndroid
        ? message.notification!.android?.imageUrl
        : message.notification!.apple?.imageUrl
    );

    if ( showLocalNotification != null ) {
      showLocalNotification!(
        id: ++pushNumberId,
        body: notification.body,
        data: notification.messageId,
        title: notification.title
      );
    }

    add( NotificationReceived( notification ) );    
  }

  void _onForegroundMessage() {
    FirebaseMessaging.onMessage.listen( handleRemoteMessage );
  }

  void requestPermission() async {
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,          //* Solicita permisos para alertas visuales (banners o mensajes emergentes)
      announcement: false,  //* Relacionado con la capacidad de hacer anuncios, como notificaciones de voz especialmente en dispositivos de asistencia. No se solicita permiso
      badge: true,          //* Solicita permiso para modificar el "badge" de la aplicación, que es un indicador númérico que aparece en el icono de la aplicación, para mostrar el número de notificaciones
      carPlay: false,       //* Determina si las notificaciones pueden aparecer mientras el dispositivo está conectado a Apple CarPlay. No se solicita permiso
      criticalAlert: true,  //* Solicita permiso par alertas críticas que pueden sonar incluso cuando el dispositivo está en modo silencioso
      provisional: false,   //* Permite enviar notificaciones silenciosas que aparecen en el centro de notificaciones sin interrumpir al usuario. No se solicita permiso
      sound: true,          //* Solicita permiso para reproducir sonidos en las notificaciones
    );

    // Solicitar permiso a las local notifications
    if ( requestLocalNotificationPermissions != null ) {
      await requestLocalNotificationPermissions!();
    }

    add( NotificationsStatusChanged( settings.authorizationStatus ) );

  }

  PushMessage? getMessageById( String pushMessageId ) {
    final exist = state.notifications.any((element) => element.messageId == pushMessageId );
    if ( !exist ) return null;
    
    return state.notifications.firstWhere((element) => element.messageId == pushMessageId );
  }
}
