import { webview } from '@kit.ArkWeb';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { promptAction } from '@kit.ArkUI';
import { AppConfig } from '../services/AppConfig';
import { NotificationService } from '../services/NotificationService';
import { BackgroundKeepAlive } from '../services/BackgroundKeepAlive';
import { DownloadService } from '../services/DownloadService';

class TavernNativeBridge {
  private onStart: () => void;
  private onFinish: (preview: string) => void;
  private onStop: () => void;

  constructor(onStart: () => void, onFinish: (preview: string) => void, onStop: () => void) {
    this.onStart = onStart;
    this.onFinish = onFinish;
    this.onStop = onStop;
  }

  generationStarted(): string {
    this.onStart();
    return 'ok';
  }

  generationFinished(preview: string): string {
    this.onFinish(preview || '');
    return 'ok';
  }

  generationStopped(): string {
    this.onStop();
    return 'ok';
  }
}

@Entry
@Component
struct Index {
  private controller: webview.WebviewController = new webview.WebviewController();
  private popupController: webview.WebviewController = new webview.WebviewController();
  private popupDownloadService?: DownloadService;
  private notification?: NotificationService;
  private keepAlive?: BackgroundKeepAlive;
  private downloadService?: DownloadService;
  private hostContext?: common.UIAbilityContext;
  private controlSubscriber?: commonEventManager.CommonEventSubscriber;

  @State loadingProgress: number = 0;
  @State generationActive: boolean = false;
  @State popupVisible: boolean = false;
  @State textPromptVisible: boolean = false;
  @State textPromptMessage: string = '';
  @State textPromptValue: string = '';
  @State httpAuthVisible: boolean = false;
  @State httpAuthHost: string = '';
  @State httpAuthRealm: string = '';
  @State httpAuthUser: string = '';
  @State httpAuthPassword: string = '';
  @State webFullscreen: boolean = false;

  private textPromptConfirm?: (value: string) => void;
  private textPromptCancel?: () => void;
  private httpAuthConfirm?: (user: string, password: string) => void;
  private httpAuthCancel?: () => void;

  private bridge: TavernNativeBridge = new TavernNativeBridge(
    () => this.handleGenerationStarted(),
    (preview: string) => this.handleGenerationFinished(preview),
    () => this.handleGenerationStopped(),
  );

  aboutToAppear(): void {
    const ctx = this.getUIContext().getHostContext();
    if (ctx) {
      this.hostContext = ctx as common.UIAbilityContext;
      this.notification = new NotificationService(this.hostContext);
      this.keepAlive = new BackgroundKeepAlive(this.hostContext);
      this.downloadService = new DownloadService(this.controller, this.hostContext);
    }
  }

  aboutToDisappear(): void {
    if (this.controlSubscriber) {
      commonEventManager.unsubscribe(this.controlSubscriber, (err: BusinessError) => {
        if (err && err.code) {
          console.warn(`unsubscribe control events failed: ${err.code} ${err.message}`);
        }
      });
      this.controlSubscriber = undefined;
    }
  }

  private async initControlEvents(): Promise<void> {
    if (this.controlSubscriber) {
      return;
    }

    const subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
      events: [AppConfig.EVENT_REFRESH, AppConfig.EVENT_CLEAR],
    };

    try {
      this.controlSubscriber = await commonEventManager.createSubscriber(subscribeInfo);
      commonEventManager.subscribe(this.controlSubscriber,
        (err: BusinessError, data: commonEventManager.CommonEventData) => {
          if (err && err.code) {
            console.warn(`control event failed: ${err.code} ${err.message}`);
            return;
          }

          if (data.event === AppConfig.EVENT_REFRESH) {
            this.controller.refresh();
            promptAction.showToast({ message: '已刷新' });
            return;
          }

          if (data.event === AppConfig.EVENT_CLEAR) {
            this.clearWebData();
          }
        });
    } catch (err) {
      const e = err as BusinessError;
      console.error(`subscribe control events failed: ${e.code} ${e.message}`);
    }
  }

  private async initNativeServices(): Promise<void> {
    await this.initControlEvents();
    await this.notification?.init();
    try {
      this.downloadService?.attach();
    } catch (err) {
      const e = err as BusinessError;
      console.error(`attach download delegate failed: ${e.code} ${e.message}`);
    }
  }

  private handleGenerationStarted(): void {
    this.generationActive = true;
    this.keepAlive?.startForGeneration();
  }

  private async handleGenerationFinished(preview: string): Promise<void> {
    this.generationActive = false;
    // 先发完成提醒，再结束长时任务。
    await this.notification?.publishReplyFinished(preview);
    await this.keepAlive?.stop();
  }

  private async handleGenerationStopped(): Promise<void> {
    this.generationActive = false;
    await this.keepAlive?.stop();
  }


  private injectSillyTavernHook(): void {
    const script: string = `
(() => {
  if (window.__HarmonyTavernHookInstalled) return 'already-installed';

  const install = () => {
    try {
      const st = window.SillyTavern;
      const ctx = st && typeof st.getContext === 'function' ? st.getContext() : null;
      if (!ctx || !ctx.eventSource || !ctx.event_types || !window.${AppConfig.BRIDGE_NAME}) {
        setTimeout(install, 800);
        return;
      }

      window.__HarmonyTavernHookInstalled = true;
      const es = ctx.eventSource;
      const ev = ctx.event_types;
      let completedThisTurn = false;

      const preview = () => {
        try {
          // 每次完成时重新取 context，避免切换聊天后仍引用旧 chat 数组。
          const liveCtx = window.SillyTavern && typeof window.SillyTavern.getContext === 'function'
            ? window.SillyTavern.getContext()
            : ctx;
          const chat = liveCtx.chat || [];
          const last = chat.length ? chat[chat.length - 1] : null;
          const text = last && typeof last.mes === 'string' ? last.mes : '';
          return text.replace(/<[^>]*>/g, '').replace(/\\s+/g, ' ').slice(0, 120);
        } catch (_) {
          return '';
        }
      };

      if (ev.GENERATION_STARTED) {
        es.on(ev.GENERATION_STARTED, () => {
          completedThisTurn = false;
          try { window.${AppConfig.BRIDGE_NAME}.generationStarted(); } catch (_) {}
        });
      }

      const notifyDone = () => {
        if (completedThisTurn) return;
        completedThisTurn = true;
        try { window.${AppConfig.BRIDGE_NAME}.generationFinished(preview()); } catch (_) {}
      };

      // 两个完成事件都监听：不同 SillyTavern 版本、生成模式和扩展链路
      // 可能只稳定触发其中一个。completedThisTurn 会阻止重复通知。
      if (ev.GENERATION_ENDED) {
        es.on(ev.GENERATION_ENDED, notifyDone);
      }
      if (ev.MESSAGE_RECEIVED) {
        es.on(ev.MESSAGE_RECEIVED, notifyDone);
      }

      if (ev.GENERATION_STOPPED) {
        es.on(ev.GENERATION_STOPPED, () => {
          // 中断/取消后封住本轮，避免晚到的 MESSAGE_RECEIVED 被误判为正常完成。
          completedThisTurn = true;
          try { window.${AppConfig.BRIDGE_NAME}.generationStopped(); } catch (_) {}
        });
      }
      return 'installed';
    } catch (_) {
      setTimeout(install, 1000);
    }
  };

  install();
  return 'installing';
})();`;

    this.controller.runJavaScript(script).then((result: string) => {
      console.info(`SillyTavern hook: ${result}`);
    }).catch((err: BusinessError) => {
      console.error(`inject hook failed: ${err.code} ${err.message}`);
    });
  }

  private async requestOsPermissions(permissions: Permissions[]): Promise<boolean> {
    if (!this.hostContext || permissions.length === 0) {
      return permissions.length === 0;
    }
    try {
      const atManager = abilityAccessCtrl.createAtManager();
      const result = await atManager.requestPermissionsFromUser(this.hostContext, permissions);
      return result.authResults.every((item: number) => item === 0);
    } catch (err) {
      const e = err as BusinessError;
      console.warn(`request web permissions failed: ${e.code} ${e.message}`);
      return false;
    }
  }

  private openTextPrompt(
    message: string,
    value: string,
    onConfirm: (result: string) => void,
    onCancel: () => void,
  ): void {
    this.textPromptMessage = message;
    this.textPromptValue = value;
    this.textPromptConfirm = onConfirm;
    this.textPromptCancel = onCancel;
    this.textPromptVisible = true;
  }

  private closeTextPrompt(confirm: boolean): void {
    const value = this.textPromptValue;
    const onConfirm = this.textPromptConfirm;
    const onCancel = this.textPromptCancel;
    this.textPromptVisible = false;
    this.textPromptConfirm = undefined;
    this.textPromptCancel = undefined;
    if (confirm) {
      onConfirm?.(value);
    } else {
      onCancel?.();
    }
  }

  private openHttpAuth(
    host: string,
    realm: string,
    onConfirm: (user: string, password: string) => void,
    onCancel: () => void,
  ): void {
    this.httpAuthHost = host;
    this.httpAuthRealm = realm;
    this.httpAuthUser = '';
    this.httpAuthPassword = '';
    this.httpAuthConfirm = onConfirm;
    this.httpAuthCancel = onCancel;
    this.httpAuthVisible = true;
  }

  private closeHttpAuth(confirm: boolean): void {
    const onConfirm = this.httpAuthConfirm;
    const onCancel = this.httpAuthCancel;
    const user = this.httpAuthUser;
    const password = this.httpAuthPassword;
    this.httpAuthVisible = false;
    this.httpAuthConfirm = undefined;
    this.httpAuthCancel = undefined;
    if (confirm) {
      onConfirm?.(user, password);
    } else {
      onCancel?.();
    }
  }

  private clearWebData(): void {
    try {
      this.controller.removeCache(true);
    } catch (err) {
      const e = err as BusinessError;
      console.warn(`removeCache failed: ${e.code} ${e.message}`);
    }

    const clearScript = `
      try { localStorage.clear(); } catch (_) {}
      try { sessionStorage.clear(); } catch (_) {}
      'cleared';`;
    this.controller.runJavaScript(clearScript).finally(() => {
      this.controller.refresh();
      promptAction.showToast({ message: '已清理网页缓存与本地存储' });
    });
  }

  build() {
    Stack({ alignContent: Alignment.Top }) {
      Web({ src: AppConfig.HOME_URL, controller: this.controller })
        .width('100%')
        .height('100%')
        .javaScriptAccess(true)
        .domStorageAccess(true)
        .fileAccess(true)
        .zoomAccess(true)
        .multiWindowAccess(true)
        .allowWindowOpenMethod(true)
        .mixedMode(MixedMode.All)
        // H5 JavaScript alert()/confirm()：ArkWeb 不会自动显示浏览器原生弹窗，
        // 必须由应用侧接管并把用户选择通过 JsResult 回传给网页。
        .onAlert((event) => {
          if (!event) {
            return false;
          }
          AlertDialog.show({
            title: '网页提示',
            message: event.message,
            primaryButton: {
              value: '确定',
              action: () => {
                event.result.handleConfirm();
              }
            },
            cancel: () => {
              // alert 没有“取消”语义；用户用返回键/点外部关闭时也按确认处理，避免 JS 一直挂起。
              event.result.handleConfirm();
            }
          });
          return true;
        })
        .onConfirm((event) => {
          if (!event) {
            return false;
          }
          AlertDialog.show({
            title: '网页提示',
            message: event.message,
            primaryButton: {
              value: '取消',
              action: () => {
                event.result.handleCancel();
              }
            },
            secondaryButton: {
              value: '确定',
              action: () => {
                event.result.handleConfirm();
              }
            },
            cancel: () => {
              event.result.handleCancel();
            }
          });
          return true;
        })
        .onPrompt((event) => {
          if (!event) {
            return false;
          }
          this.openTextPrompt(
            event.message,
            event.value ?? '',
            (value: string) => event.result.handlePromptConfirm(value),
            () => event.result.handleCancel(),
          );
          return true;
        })
        .onBeforeUnload((event) => {
          if (!event) {
            return false;
          }
          AlertDialog.show({
            title: '离开此页面？',
            message: event.message || '系统可能不会保存您所做的更改。',
            primaryButton: {
              value: '取消',
              action: () => event.result.handleCancel()
            },
            secondaryButton: {
              value: '离开',
              action: () => event.result.handleConfirm()
            },
            cancel: () => event.result.handleCancel()
          });
          return true;
        })
        .geolocationAccess(true)
        .onGeolocationShow((event) => {
          if (!event) {
            return;
          }
          AlertDialog.show({
            title: '位置权限请求',
            message: `是否允许 ${event.origin} 获取您的位置信息？`,
            primaryButton: {
              value: '拒绝',
              action: () => event.geolocation.invoke(event.origin, false, false)
            },
            secondaryButton: {
              value: '允许',
              action: async () => {
                const granted = await this.requestOsPermissions([
                  'ohos.permission.APPROXIMATELY_LOCATION',
                  'ohos.permission.LOCATION',
                ]);
                event.geolocation.invoke(event.origin, granted, false);
              }
            },
            cancel: () => event.geolocation.invoke(event.origin, false, false)
          });
        })
        .onPermissionRequest((event) => {
          if (!event) {
            return;
          }
          const resources = event.request.getAccessibleResource();
          const permissions: Permissions[] = [];
          if (resources.indexOf('TYPE_VIDEO_CAPTURE') >= 0) {
            permissions.push('ohos.permission.CAMERA');
          }
          if (resources.indexOf('TYPE_AUDIO_CAPTURE') >= 0) {
            permissions.push('ohos.permission.MICROPHONE');
          }

          // 传感器权限属于普通权限，已在 module.json5 声明；摄像头/麦克风由系统弹窗动态授权。
          this.requestOsPermissions(permissions).then((granted: boolean) => {
            if (granted) {
              event.request.grant(resources);
            } else {
              event.request.deny();
            }
          });
        })
        .onHttpAuthRequest((event) => {
          if (!event) {
            return false;
          }
          this.openHttpAuth(
            event.host,
            event.realm,
            (user: string, password: string) => {
              event.handler.confirm(user, password);
            },
            () => event.handler.cancel(),
          );
          return true;
        })
        .onSslErrorEvent((event) => {
          if (!event) {
            return;
          }
          AlertDialog.show({
            title: '网站证书异常',
            message: '此网站的 HTTPS 证书存在问题。继续访问可能有安全风险。',
            primaryButton: {
              value: '返回安全页面',
              action: () => event.handler.handleCancel(true)
            },
            secondaryButton: {
              value: '仍然继续',
              action: () => event.handler.handleConfirm()
            },
            cancel: () => event.handler.handleCancel(true)
          });
        })
        .onFullScreenEnter(() => {
          this.webFullscreen = true;
        })
        .onFullScreenExit(() => {
          this.webFullscreen = false;
        })
        // H5 <input type="file">：返回 false，交给 ArkWeb 默认文件选择弹窗处理。
        // SillyTavern 的角色卡、预设、世界书等导入入口可直接调用系统选择器。
        .onShowFileSelector(() => false)
        // SillyTavern 插件常使用 window.open() / target="_blank" 打开设置页或独立面板。
        // ArkWeb 不能只开启 multiWindowAccess；收到新窗口请求后还必须创建并绑定新的 WebviewController。
        .onWindowNew((event) => {
          if (!event) {
            return;
          }
          this.popupController = new webview.WebviewController();
          event.handler.setWebController(this.popupController);
          this.popupVisible = true;
        })
        .javaScriptProxy({
          object: this.bridge,
          name: AppConfig.BRIDGE_NAME,
          methodList: ['generationStarted', 'generationFinished', 'generationStopped'],
          controller: this.controller,
        })
        .onControllerAttached(() => {
          this.initNativeServices();
        })
        .onProgressChange((event) => {
          this.loadingProgress = event?.newProgress ?? 0;
        })
        .onPageEnd(() => {
          this.injectSillyTavernHook();
        })
        .onRenderExited(() => {
          // ArkWeb 渲染进程异常退出时自动恢复首页。
          setTimeout(() => this.controller.loadUrl(AppConfig.HOME_URL), 300);
        })

      if (this.popupVisible) {
        Column() {
          Row() {
            Text('插件窗口')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .layoutWeight(1)

            Button('关闭')
              .height(36)
              .buttonStyle(ButtonStyleMode.TEXTUAL)
              .onClick(() => {
                this.popupVisible = false;
              })
          }
          .width('100%')
          .height(48)
          .padding({ left: 12, right: 8 })
          .backgroundColor('#FFF7F7F7')

          Web({ src: '', controller: this.popupController })
            .width('100%')
            .layoutWeight(1)
            .javaScriptAccess(true)
            .domStorageAccess(true)
            .fileAccess(true)
            .zoomAccess(true)
            .multiWindowAccess(false)
            .allowWindowOpenMethod(true)
            .mixedMode(MixedMode.All)
            // H5 JavaScript alert()/confirm()：ArkWeb 不会自动显示浏览器原生弹窗，
            // 必须由应用侧接管并把用户选择通过 JsResult 回传给网页。
            .onAlert((event) => {
              if (!event) {
                return false;
              }
              AlertDialog.show({
                title: '网页提示',
                message: event.message,
                primaryButton: {
                  value: '确定',
                  action: () => {
                    event.result.handleConfirm();
                  }
                },
                cancel: () => {
                  // alert 没有“取消”语义；用户用返回键/点外部关闭时也按确认处理，避免 JS 一直挂起。
                  event.result.handleConfirm();
                }
              });
              return true;
            })
            .onConfirm((event) => {
              if (!event) {
                return false;
              }
              AlertDialog.show({
                title: '网页提示',
                message: event.message,
                primaryButton: {
                  value: '取消',
                  action: () => {
                    event.result.handleCancel();
                  }
                },
                secondaryButton: {
                  value: '确定',
                  action: () => {
                    event.result.handleConfirm();
                  }
                },
                cancel: () => {
                  event.result.handleCancel();
                }
              });
              return true;
            })
            .onPrompt((event) => {
              if (!event) {
                return false;
              }
              this.openTextPrompt(
                event.message,
                event.value ?? '',
                (value: string) => event.result.handlePromptConfirm(value),
                () => event.result.handleCancel(),
              );
              return true;
            })
            .onBeforeUnload((event) => {
              if (!event) {
                return false;
              }
              AlertDialog.show({
                title: '离开此页面？',
                message: event.message || '系统可能不会保存您所做的更改。',
                primaryButton: {
                  value: '取消',
                  action: () => event.result.handleCancel()
                },
                secondaryButton: {
                  value: '离开',
                  action: () => event.result.handleConfirm()
                },
                cancel: () => event.result.handleCancel()
              });
              return true;
            })
            .geolocationAccess(true)
            .onGeolocationShow((event) => {
              if (!event) {
                return;
              }
              AlertDialog.show({
                title: '位置权限请求',
                message: `是否允许 ${event.origin} 获取您的位置信息？`,
                primaryButton: {
                  value: '拒绝',
                  action: () => event.geolocation.invoke(event.origin, false, false)
                },
                secondaryButton: {
                  value: '允许',
                  action: async () => {
                    const granted = await this.requestOsPermissions([
                      'ohos.permission.APPROXIMATELY_LOCATION',
                      'ohos.permission.LOCATION',
                    ]);
                    event.geolocation.invoke(event.origin, granted, false);
                  }
                },
                cancel: () => event.geolocation.invoke(event.origin, false, false)
              });
            })
            .onPermissionRequest((event) => {
              if (!event) {
                return;
              }
              const resources = event.request.getAccessibleResource();
              const permissions: Permissions[] = [];
              if (resources.indexOf('TYPE_VIDEO_CAPTURE') >= 0) {
                permissions.push('ohos.permission.CAMERA');
              }
              if (resources.indexOf('TYPE_AUDIO_CAPTURE') >= 0) {
                permissions.push('ohos.permission.MICROPHONE');
              }
              this.requestOsPermissions(permissions).then((granted: boolean) => {
                if (granted) {
                  event.request.grant(resources);
                } else {
                  event.request.deny();
                }
              });
            })
            .onHttpAuthRequest((event) => {
              if (!event) {
                return false;
              }
              this.openHttpAuth(
                event.host,
                event.realm,
                (user: string, password: string) => event.handler.confirm(user, password),
                () => event.handler.cancel(),
              );
              return true;
            })
            .onSslErrorEvent((event) => {
              if (!event) {
                return;
              }
              AlertDialog.show({
                title: '网站证书异常',
                message: '此网站的 HTTPS 证书存在问题。继续访问可能有安全风险。',
                primaryButton: {
                  value: '返回安全页面',
                  action: () => event.handler.handleCancel(true)
                },
                secondaryButton: {
                  value: '仍然继续',
                  action: () => event.handler.handleConfirm()
                },
                cancel: () => event.handler.handleCancel(true)
              });
            })
            .onFullScreenEnter(() => {
              this.webFullscreen = true;
            })
            .onFullScreenExit(() => {
              this.webFullscreen = false;
            })
            .onShowFileSelector(() => false)
            .onControllerAttached(() => {
              if (this.hostContext) {
                try {
                  this.popupDownloadService = new DownloadService(this.popupController, this.hostContext);
                  this.popupDownloadService.attach();
                } catch (err) {
                  const e = err as BusinessError;
                  console.warn(`attach popup download delegate failed: ${e.code} ${e.message}`);
                }
              }
            })
            .onWindowExit(() => {
              this.popupVisible = false;
            })
        }
        .width('100%')
        .height('100%')
        .backgroundColor(Color.White)
        .zIndex(300)
      }

      if (this.textPromptVisible) {
        Column({ space: 14 }) {
          Text('网页输入')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)

          Text(this.textPromptMessage)
            .fontSize(15)
            .width('100%')

          TextInput({ text: this.textPromptValue })
            .width('100%')
            .onChange((value: string) => {
              this.textPromptValue = value;
            })

          Row({ space: 12 }) {
            Button('取消')
              .layoutWeight(1)
              .onClick(() => this.closeTextPrompt(false))
            Button('确定')
              .layoutWeight(1)
              .onClick(() => this.closeTextPrompt(true))
          }
          .width('100%')
        }
        .width('86%')
        .padding(20)
        .borderRadius(22)
        .backgroundColor(Color.White)
        .shadow({ radius: 24, color: '#55000000', offsetX: 0, offsetY: 8 })
        .zIndex(600)
        .position({ x: '7%', y: '25%' })
      }

      if (this.httpAuthVisible) {
        Column({ space: 14 }) {
          Text('网站身份验证')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)

          Text(`${this.httpAuthHost}${this.httpAuthRealm ? ' · ' + this.httpAuthRealm : ''}`)
            .fontSize(13)
            .fontColor('#666666')
            .width('100%')

          TextInput({ placeholder: '用户名', text: this.httpAuthUser })
            .width('100%')
            .onChange((value: string) => {
              this.httpAuthUser = value;
            })

          TextInput({ placeholder: '密码', text: this.httpAuthPassword })
            .width('100%')
            .type(InputType.Password)
            .onChange((value: string) => {
              this.httpAuthPassword = value;
            })

          Row({ space: 12 }) {
            Button('取消')
              .layoutWeight(1)
              .onClick(() => this.closeHttpAuth(false))
            Button('登录')
              .layoutWeight(1)
              .onClick(() => this.closeHttpAuth(true))
          }
          .width('100%')
        }
        .width('86%')
        .padding(20)
        .borderRadius(22)
        .backgroundColor(Color.White)
        .shadow({ radius: 24, color: '#55000000', offsetX: 0, offsetY: 8 })
        .zIndex(610)
        .position({ x: '7%', y: '22%' })
      }

      if (this.loadingProgress > 0 && this.loadingProgress < 100) {
        Progress({ value: this.loadingProgress, total: 100, type: ProgressType.Linear })
          .width('100%')
          .height(2)
          .zIndex(20)
      }

    }
    .width('100%')
    .height('100%')
  }
}
