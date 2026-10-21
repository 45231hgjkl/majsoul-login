使用[GitHub Action](https://github.com/features/actions)+[Selenium](https://selenium.dev)实现雀魂每日5:00自动登录，完成“良好市民”成就

![image](https://github.com/QuanQuan-CHO/Majsoul-Login/assets/90035785/9b7fac02-79cb-4e5c-b98d-7f1788d5996d)

或者自动完成某些活动任务：
<img width="1999" height="1038" alt="image" src="https://github.com/user-attachments/assets/250c1e21-7092-4265-b75e-88eb99001c0d" />


浏览器F12抓包太麻烦，所以干脆用了Selenium

[GitHub Action的Ubuntu内置了Chrome浏览器](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2204-Readme.md#browsers-and-drivers)，无需手动安装，由于没有桌面环境，需要[使用headless模式启动Chrome](https://selenium.dev/blog/2023/headless-is-going-away)

其他参考：
- [Selenium Mouse API](https://selenium.dev/documentation/webdriver/actions_api/mouse)
- https://tecadmin.net/setup-selenium-with-python-on-ubuntu-debian
- https://zhuanlan.zhihu.com/p/632399597
<br>

## 使用方法
1. Fork本仓库
2. 点击Settings->Secrets and variables->Actions->New repository secret，依次配置`EMAIL`、`PASSWD`
    - EMAIL 是雀魂的邮箱账号，如有多个账户用空格分隔，例如`example@gmail.com example@qq.com`
    - PASSWD 是雀魂的密码，如有多个账户用空格分隔，与邮箱依次对应，例如`grc28r7g3 pdtaw3fwag`
3. 先在Actions页面将GitHub Action启用，再选择对应的workflow，将scheduled workflow启用
   ![enable-schedule-workflow](https://user-images.githubusercontent.com/90035785/224888848-be15ba52-1892-4a2b-9cef-b321b9a25165.jpg)
4. Enjoy it!

## 关于「60 天没变动导致计划任务自动关闭」

GitHub 有一条规则：**公开仓库连续 60 天没有任何活动（commit/push），所有 `schedule` 触发的 workflow 会被自动停用**，需要去 Actions 页面手动重新启用。这样每日自动登录会在无感知的情况下失效。

本项目已内置保活机制（`.github/scripts/keepalive.sh`，在登录 workflow 的末尾以 `if: always()` 执行）：

- 距离上次保活提交超过 **25 天**时，自动更新 `.github/keepalive` 并推送一个带 `[skip ci]` 的提交，重置 60 天计时器（不用每天提交，不会刷爆 commit 历史）。
- 顺带检查 `login.yml` 是否已被停用，如果是则调用 GitHub API 自动重新启用。
- 登录步骤失败不会阻断保活步骤；最后仍会以失败状态结束，方便你收到通知。

所需权限已在 workflow 里声明（`contents: write`、`actions: write`），默认使用 `GITHUB_TOKEN`，开箱即用。

> 若你的仓库 Fork 后默认 workflow 权限被限制为只读（Settings → Actions → General → Workflow permissions 里选成 *Read repository contents permission*），请改成 *Read and write permissions*。
>
> 如果想用个人令牌更保险：新建一个带 `repo` + `workflow` 权限的 PAT，命名为 `KEEPALIVE_TOKEN` 存进 Secrets 即可，workflow 会自动优先使用它。

手动应急：如果已经超过 60 天且计划任务被停用，在 Actions 页面手动 `Run workflow` 跑一次 `Majsoul-Login`，保活步骤会把它重新启用。
