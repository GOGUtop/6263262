export class AppConfig {
  static readonly HOME_URL: string = 'http://aaa.xixisillytavern.top:8001/';
  static readonly BUNDLE_NAME: string = 'top.xixisillytavern.tavern';
  static readonly ABILITY_NAME: string = 'EntryAbility';
  static readonly BRIDGE_NAME: string = 'HarmonyBridge';

  // 两张通知完全分离：快捷操作为常驻服务通知，AI 回复完成是普通提醒。
  static readonly CONTROL_NOTIFICATION_ID: number = 88000;
  static readonly REPLY_NOTIFICATION_ID: number = 88001;
  static readonly CONTROL_NOTIFICATION_GROUP: string = 'sillytavern.control';
  static readonly REPLY_NOTIFICATION_GROUP: string = 'sillytavern.reply';

  // 通知栏按钮通过公共事件把操作发送给正在运行的 ArkUI 页面。
  static readonly EVENT_REFRESH: string = 'top.xixisillytavern.tavern.action.REFRESH';
  static readonly EVENT_CLEAR: string = 'top.xixisillytavern.tavern.action.CLEAR';
}
