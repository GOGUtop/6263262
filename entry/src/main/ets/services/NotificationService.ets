import { notificationManager } from '@kit.NotificationKit';
import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from './AppConfig';

export class NotificationService {
  private context: common.UIAbilityContext;
  private tapAgent?: WantAgent;
  private refreshAgent?: WantAgent;
  private clearAgent?: WantAgent;

  constructor(context: common.UIAbilityContext) {
    this.context = context;
  }

  async init(): Promise<void> {
    try {
      await notificationManager.requestEnableNotification(this.context);
    } catch (err) {
      const e = err as BusinessError;
      console.warn(`requestEnableNotification: ${e.code} ${e.message}`);
    }

    // 快捷操作与 AI 回复使用不同通知通道，降低被系统聚合到同一卡片的概率。
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
    } catch (err) {
      const e = err as BusinessError;
      console.warn(`add service slot: ${e.code} ${e.message}`);
    }
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SOCIAL_COMMUNICATION);
    } catch (err) {
      const e = err as BusinessError;
      console.warn(`add social slot: ${e.code} ${e.message}`);
    }

    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{
          bundleName: AppConfig.BUNDLE_NAME,
          abilityName: AppConfig.ABILITY_NAME,
        }],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: 88001,
        wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG],
      };
      this.tapAgent = await wantAgent.getWantAgent(info);
    } catch (err) {
      const e = err as BusinessError;
      console.warn(`get tap WantAgent: ${e.code} ${e.message}`);
    }

    this.refreshAgent = await this.createCommonEventAgent(AppConfig.EVENT_REFRESH, 88010);
    this.clearAgent = await this.createCommonEventAgent(AppConfig.EVENT_CLEAR, 88011);
    await this.publishControlPanel();
  }

  private async createCommonEventAgent(action: string, requestCode: number): Promise<WantAgent | undefined> {
    try {
      const info: wantAgent.WantAgentInfo = {
        wants: [{ action }],
        actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
        requestCode,
        wantAgentFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG],
      };
      return await wantAgent.getWantAgent(info);
    } catch (err) {
      const e = err as BusinessError;
      console.warn(`get common event WantAgent failed: ${e.code} ${e.message}`);
      return undefined;
    }
  }

  async publishControlPanel(): Promise<void> {
    if (!this.refreshAgent || !this.clearAgent) {
      console.warn('control notification skipped: action WantAgent not ready');
      return;
    }

    const request: notificationManager.NotificationRequest = {
      id: AppConfig.CONTROL_NOTIFICATION_ID,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      groupName: AppConfig.CONTROL_NOTIFICATION_GROUP,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: 'SillyTavern · 快捷操作',
          text: '酒馆正在运行',
          additionalText: '可直接刷新网页或清理网页数据',
        },
      },
      wantAgent: this.tapAgent,
      actionButtons: [
        {
          title: '刷新',
          wantAgent: this.refreshAgent,
        },
        {
          title: '清理',
          wantAgent: this.clearAgent,
        },
      ],
      // 关键：运行中 + 不可移除。效果类似“正在进行的任务”，而不是普通提醒。
      isOngoing: true,
      isUnremovable: true,
      isAlertOnce: true,
      tapDismissed: false,
      showDeliveryTime: false,
    };

    try {
      await notificationManager.publish(request);
    } catch (err) {
      const e = err as BusinessError;
      console.error(`publish control notification failed: ${e.code} ${e.message}`);
    }
  }

  async publishReplyFinished(preview: string = ''): Promise<void> {
    const text = preview.trim().length > 0 ? preview.trim().slice(0, 120) : 'AI 已经回复完毕，点击返回酒馆查看。';
    const request: notificationManager.NotificationRequest = {
      id: AppConfig.REPLY_NOTIFICATION_ID,
      notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
      groupName: AppConfig.REPLY_NOTIFICATION_GROUP,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: 'SillyTavern · AI 回复完成',
          text,
          additionalText: '点击打开酒馆',
        },
      },
      wantAgent: this.tapAgent,
      tapDismissed: true,
      isOngoing: false,
      isUnremovable: false,
      badgeNumber: 1,
    };

    try {
      await notificationManager.publish(request);
    } catch (err) {
      const e = err as BusinessError;
      console.error(`publish notification failed: ${e.code} ${e.message}`);
    }
  }

  static async cancelControlPanel(): Promise<void> {
    try {
      await notificationManager.cancel(AppConfig.CONTROL_NOTIFICATION_ID);
    } catch (err) {
      const e = err as BusinessError;
      console.warn(`cancel control notification failed: ${e.code} ${e.message}`);
    }
  }
}
