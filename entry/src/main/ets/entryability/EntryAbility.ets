import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { BusinessError } from '@kit.BasicServicesKit';
import { NotificationService } from '../services/NotificationService';

export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    try {
      webview.WebviewController.initializeWebEngine();
    } catch (_) {}
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    windowStage.loadContent('pages/Index', (err: BusinessError) => {
      if (err.code) {
        console.error(`loadContent failed: ${err.code} ${err.message}`);
      }
    });
  }

  onDestroy(): void {
    // 应用真正退出/Ability 被销毁时移除常驻快捷卡片。
    NotificationService.cancelControlPanel();
  }
}
