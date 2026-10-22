<script def>
{
  "navigationBarTitleText": "颈椎能量站",
  "description": "快速护颈游戏的首页和训练前安全确认页面。",
  "schema": {
    "data": {
      "type": "object",
      "properties": {}
    }
  }
}
</script>

<script setup>
import wx from 'wx';

export default {
  data: {
    screen: 'home',
    lastScore: '--',
    completedCount: 0,
    selectedIdx: 0
  },

  onShow() {
    let latest;
    let history = [];
    try {
      latest = wx.getStorageSync('neck_guard_latest');
      history = wx.getStorageSync('neck_guard_history') || [];
    } catch (error) {
      console.log('Local history unavailable:', error);
    }
    this.setData({
      screen: 'home',
      lastScore: latest && latest.score ? latest.score : '--',
      completedCount: history.length,
      selectedIdx: 0
    });
  },

  getActionItems() {
    if (this.data.screen === 'home') {
      return [
        { action: 'showSafetyCheck', label: '开始充能' },
        { action: 'viewReport', label: '上次报告' }
      ];
    } else if (this.data.screen === 'safety') {
      return [
        { action: 'confirmReady', label: '状态正常' },
        { action: 'reportDiscomfort', label: '我有不适' },
        { action: 'backHome', label: '返回' }
      ];
    } else {
      return [
        { action: 'backHome', label: '我知道了' }
      ];
    }
  },

  onKeyDown(event) {
    const code = event.code;
    const items = this.getActionItems();
    if (items.length === 0) return;
    if (code === 'ArrowUp') {
      const idx = this.data.selectedIdx > 0 ? this.data.selectedIdx - 1 : items.length - 1;
      this.setData({ selectedIdx: idx });
    } else if (code === 'ArrowDown') {
      const idx = this.data.selectedIdx < items.length - 1 ? this.data.selectedIdx + 1 : 0;
      this.setData({ selectedIdx: idx });
    } else if (code === 'Enter') {
      const item = items[this.data.selectedIdx];
      if (item && typeof this[item.action] === 'function') {
        this[item.action]();
      }
    }
  },

  showSafetyCheck() {
    this.setData({ screen: 'safety', selectedIdx: 0 });
  },

  confirmReady() {
    wx.navigateTo({ url: '/pages/game/game' });
  },

  reportDiscomfort() {
    this.setData({ screen: 'blocked', selectedIdx: 0 });
  },

  backHome() {
    this.setData({ screen: 'home', selectedIdx: 0 });
  },

  viewReport() {
    if (this.data.lastScore !== '--') {
      wx.navigateTo({ url: '/pages/report/report' });
    }
  }
};
</script>

<page>
  <view class="page-shell">
    <view class="topline">
      <view class="brand-mark"></view>
      <text class="eyebrow">NECK ENERGY LAB</text>
      <text class="version">MVP 0.1</text>
    </view>

    <view ink:if="{{screen === 'home'}}" class="home-panel">
      <view class="hero-row">
        <view class="hero-copy">
          <text class="title">颈椎能量站</text>
          <text class="subtitle">用一分钟，慢慢找回肩颈的舒展感</text>
        </view>
        <view class="energy-orbit">
          <view class="energy-core"></view>
        </view>
      </view>

      <view class="stat-strip">
        <view class="stat-item">
          <text class="stat-value">{{completedCount}}</text>
          <text class="stat-label">本机练习</text>
        </view>
        <view class="stat-divider"></view>
        <view class="stat-item">
          <text class="stat-value">{{lastScore}}</text>
          <text class="stat-label">最近评分</text>
        </view>
        <view class="stat-divider"></view>
        <view class="stat-item wide-stat">
          <text class="mode-value">快速护颈</text>
          <text class="stat-label">4 个温和步骤</text>
        </view>
      </view>

      <view class="action-row">
        <button class="primary-btn {{selectedIdx === 0 ? 'btn-selected' : ''}}" bindtap="showSafetyCheck">
          <text>开始充能</text>
        </button>
        <button class="ghost-btn {{selectedIdx === 1 ? 'btn-selected' : ''}}" bindtap="viewReport">
          <text>上次报告</text>
        </button>
      </view>
      <text class="privacy-note">姿态数据仅用于本次互动，不保存原始传感器数据</text>
    </view>

    <view ink:elif="{{screen === 'safety'}}" class="safety-panel">
      <view class="step-tag">训练前确认</view>
      <text class="panel-title">此刻身体感觉正常吗？</text>
      <text class="panel-copy">全程只做到舒适幅度。不要后仰、绕颈或追求更大角度。</text>
      <view class="warning-line">
        <view class="warning-dot"></view>
        <text>疼痛、眩晕或手麻时，请不要开始</text>
      </view>
      <view class="action-row">
        <button class="primary-btn {{selectedIdx === 0 ? 'btn-selected' : ''}}" bindtap="confirmReady">
          <text>状态正常</text>
        </button>
        <button class="danger-btn {{selectedIdx === 1 ? 'btn-selected' : ''}}" bindtap="reportDiscomfort">
          <text>我有不适</text>
        </button>
      </view>
      <button class="text-btn {{selectedIdx === 2 ? 'btn-selected' : ''}}" bindtap="backHome">
        <text>返回</text>
      </button>
    </view>

    <view ink:else class="safety-panel blocked-panel">
      <view class="stop-icon">!</view>
      <text class="panel-title">今天先停止颈部训练</text>
      <text class="panel-copy">请保持自然坐姿并休息。若症状持续或加重，请咨询专业医生。</text>
      <button class="primary-btn full-btn {{selectedIdx === 0 ? 'btn-selected' : ''}}" bindtap="backHome">
        <text>我知道了</text>
      </button>
      <text class="medical-note">本应用不提供医学诊断</text>
    </view>
  </view>
</page>

<style>
:root {
  --color-background: #000000;
  --color-surface: rgba(64, 255, 94, 0.06);
  --color-surface-highlight: rgba(64, 255, 94, 0.06);
  --color-text-primary: rgba(64, 255, 94, 0.72);
  --color-text-secondary: rgba(64, 255, 94, 0.48);
  --color-primary: #40ff5e;
  --color-primary-40: rgba(64, 255, 94, 0.24);
  --border-color-muted: rgba(64, 255, 94, 0.12);
  --border-color-default: rgba(64, 255, 94, 0.24);
  --border-color-warning: rgba(64, 255, 94, 0.48);
  --border-color-danger: rgba(64, 255, 94, 0.48);
  --border-color-accent: rgba(64, 255, 94, 0.24);
}

.page-shell {
  width: 480px;
  min-height: 360px;
  box-sizing: border-box;
  padding: 18px 20px;
  background-color: var(--color-background);
  color: var(--color-text-primary);
  font-family: Arial, sans-serif;
}

.topline, .hero-row, .stat-strip, .action-row, .warning-line {
  display: flex;
  align-items: center;
}

.topline {
  height: 24px;
}

.brand-mark {
  width: 8px;
  height: 8px;
  border-radius: 4px;
  background-color: var(--color-primary);
  box-shadow: 0 0 12px var(--color-primary);
}

.eyebrow {
  margin-left: 8px;
  color: var(--color-primary);
  font-size: 11px;
  font-weight: 700;
}

.version {
  margin-left: auto;
  color: var(--color-text-secondary);
  font-size: 10px;
}

.home-panel, .safety-panel {
  margin-top: 12px;
  padding: 18px;
  border: 2px solid var(--border-color-muted);
  border-radius: 12px;
  background-color: var(--color-surface);
  box-sizing: border-box;
}

.hero-row {
  justify-content: space-between;
}

.hero-copy {
  display: flex;
  flex-direction: column;
  max-width: 305px;
}

.title {
  font-size: 27px;
  line-height: 34px;
  font-weight: 700;
}

.subtitle, .panel-copy, .privacy-note, .medical-note {
  color: var(--color-text-secondary);
}

.subtitle {
  margin-top: 5px;
  font-size: 13px;
}

.energy-orbit {
  width: 58px;
  height: 58px;
  display: flex;
  align-items: center;
  justify-content: center;
  border: 2px solid var(--color-primary-40);
  border-radius: 30px;
  box-shadow: 0 0 16px var(--color-primary-40);
}

.energy-core {
  width: 22px;
  height: 22px;
  border-radius: 12px;
  background-color: var(--color-primary);
}

.stat-strip {
  margin-top: 17px;
  padding: 11px 0;
  border: 1px solid var(--border-color-muted);
  border-radius: 4px;
}

.stat-item {
  min-width: 86px;
  display: flex;
  flex-direction: column;
  align-items: center;
}

.wide-stat {
  flex-grow: 1;
}

.stat-value {
  font-size: 21px;
  font-weight: 700;
  color: var(--color-primary);
}

.mode-value {
  font-size: 15px;
  font-weight: 700;
}

.stat-label {
  margin-top: 3px;
  font-size: 10px;
  color: var(--color-text-secondary);
}

.stat-divider {
  width: 1px;
  height: 28px;
  background-color: var(--border-color-muted);
}

.action-row {
  gap: 10px;
  margin-top: 16px;
}

.primary-btn, .ghost-btn, .danger-btn, .text-btn {
  min-height: 40px;
  border-radius: 10px;
  font-size: 14px;
  font-weight: 700;
}

.primary-btn {
  flex-grow: 1;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  gap: 6px;
  color: var(--color-background);
  background-color: var(--color-primary);
  border: 2px solid var(--color-primary);
}

.ghost-btn {
  min-width: 118px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  gap: 6px;
  color: var(--color-text-primary);
  background-color: transparent;
  border: 2px solid var(--border-color-default);
}

.danger-btn {
  flex-grow: 1;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  gap: 6px;
  color: var(--color-text-primary);
  background-color: transparent;
  border: 2px solid var(--border-color-danger);
}

.btn-selected {
  border: 3px solid var(--color-primary);
  background-color: rgba(64, 255, 94, 0.18);
  box-shadow: 0 0 12px rgba(64, 255, 94, 0.48);
}

.privacy-note, .medical-note {
  display: block;
  margin-top: 10px;
  font-size: 10px;
  text-align: center;
}

.step-tag {
  color: var(--color-primary);
  font-size: 11px;
  font-weight: 700;
}

.panel-title {
  display: block;
  margin-top: 8px;
  font-size: 23px;
  line-height: 30px;
  font-weight: 700;
}

.panel-copy {
  display: block;
  margin-top: 8px;
  font-size: 13px;
  line-height: 20px;
}

.warning-line {
  margin-top: 14px;
  padding: 10px 12px;
  border: 1px solid var(--border-color-warning);
  border-radius: 8px;
  color: var(--color-text-primary);
  font-size: 12px;
}

.warning-dot {
  width: 6px;
  height: 6px;
  margin-right: 8px;
  border-radius: 3px;
  background-color: var(--border-color-warning);
}

.text-btn {
  width: 100%;
  margin-top: 8px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  gap: 6px;
  color: var(--color-text-secondary);
  background-color: transparent;
  border: 2px solid transparent;
}

.blocked-panel {
  text-align: center;
}

.stop-icon {
  width: 38px;
  height: 38px;
  margin: 0 auto;
  border: 2px solid var(--border-color-warning);
  border-radius: 20px;
  color: var(--border-color-warning);
  font-size: 25px;
  line-height: 38px;
  text-align: center;
}

.full-btn {
  width: 100%;
  margin-top: 18px;
}
</style>

