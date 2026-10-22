<script def>
{
  "navigationBarTitleText": "训练报告",
  "description": "展示本次快速护颈训练的本地结构化健康管理报告。",
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

const EMPTY_RESULT = {
  score: 0,
  date: '--',
  durationSeconds: 0,
  mode: '快速护颈',
  summary: '暂无训练记录。',
  rhythmNote: '完成一次训练后查看节奏反馈',
  balanceNote: '完成左右转头后查看平衡反馈',
  dimensions: []
};

export default {
  data: {
    score: 0,
    scoreLabel: '待训练',
    date: '--',
    durationText: '0 秒',
    mode: '快速护颈',
    summary: EMPTY_RESULT.summary,
    rhythmNote: EMPTY_RESULT.rhythmNote,
    balanceNote: EMPTY_RESULT.balanceNote,
    dimensions: [],
    completedText: '暂无',
    skippedText: '无',
    selectedIdx: 0
  },

  onLoad() {
    let result = EMPTY_RESULT;
    try {
      result = wx.getStorageSync('neck_guard_latest') || EMPTY_RESULT;
    } catch (error) {
      console.log('Report unavailable:', error);
    }
    const dimensions = (result.dimensions || []).map((item) => ({
      name: item.name,
      value: item.score + ' / ' + item.max,
      percent: Math.round(item.score / item.max * 100)
    }));
    this.setData({
      score: result.score,
      scoreLabel: result.score >= 88 ? '非常稳定' : result.score >= 72 ? '完成良好' : result.score > 0 ? '温和起步' : '待训练',
      date: result.date,
      durationText: this.formatDuration(result.durationSeconds),
      mode: result.mode,
      summary: result.summary,
      rhythmNote: result.rhythmNote,
      balanceNote: result.balanceNote,
      dimensions,
      completedText: result.completed && result.completed.length ? result.completed.join('、') : '暂无',
      skippedText: result.skipped && result.skipped.length ? result.skipped.join('、') : '无',
      selectedIdx: 0
    });
  },

  formatDuration(seconds) {
    if (seconds < 60) {
      return seconds + ' 秒';
    }
    return Math.floor(seconds / 60) + ' 分 ' + seconds % 60 + ' 秒';
  },

  getActionItems() {
    return [
      { action: 'trainAgain', label: '再练一次' },
      { action: 'returnHome', label: '返回首页' }
    ];
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

  trainAgain() {
    wx.redirectTo({ url: '/pages/game/game' });
  },

  returnHome() {
    wx.redirectTo({ url: '/pages/index/index' });
  }
};
</script>

<page>
  <view class="page-shell">
    <view class="report-card">
      <view class="report-header">
        <view class="score-ring">
          <text class="score">{{score}}</text>
          <text class="score-unit">/ 100</text>
        </view>
        <view class="summary-block">
          <text class="eyebrow">LOCAL WELLNESS REPORT</text>
          <text class="score-label">{{scoreLabel}}</text>
          <text class="meta">{{date}} · {{mode}} · {{durationText}}</text>
        </view>
      </view>

      <text class="summary">{{summary}}</text>

      <view class="dimension-grid">
        <view ink:for="{{dimensions}}" ink:key="name" class="dimension-item">
          <view class="dimension-line">
            <text class="dimension-name">{{item.name}}</text>
            <text class="dimension-value">{{item.value}}</text>
          </view>
          <view class="mini-track">
            <view class="mini-fill" style="width: {{item.percent}}%;"></view>
          </view>
        </view>
      </view>

      <view class="notes-row">
        <view class="note-card">
          <text class="note-label">节奏</text>
          <text class="note-copy">{{rhythmNote}}</text>
        </view>
        <view class="note-card">
          <text class="note-label">平衡</text>
          <text class="note-copy">{{balanceNote}}</text>
        </view>
      </view>

      <view class="completion-line">
        <text>完成：{{completedText}}</text>
        <text>跳过：{{skippedText}}</text>
      </view>

      <view class="actions">
        <button class="primary-btn {{selectedIdx === 0 ? 'btn-selected' : ''}}" bindtap="trainAgain">
          <text>再练一次</text>
        </button>
        <button class="ghost-btn {{selectedIdx === 1 ? 'btn-selected' : ''}}" bindtap="returnHome">
          <text>返回首页</text>
        </button>
      </view>
      <text class="medical-note">仅供日常健康管理参考，不构成医学诊断</text>
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
  min-height: 380px;
  box-sizing: border-box;
  padding: 14px 20px;
  background-color: var(--color-background);
  color: var(--color-text-primary);
  font-family: Arial, sans-serif;
}

.report-card {
  padding: 10px 14px;
  border: 2px solid var(--border-color-muted);
  border-radius: 12px;
  background-color: var(--color-surface);
}

.report-header, .dimension-line, .notes-row, .completion-line, .actions {
  display: flex;
  align-items: center;
}

.score-ring {
  width: 62px;
  height: 62px;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  border: 3px solid var(--color-primary);
  border-radius: 40px;
  box-shadow: 0 0 14px var(--color-primary-40);
}

.score {
  color: var(--color-primary);
  font-size: 25px;
  line-height: 25px;
  font-weight: 700;
}

.score-unit {
  color: var(--color-text-secondary);
  font-size: 9px;
}

.summary-block {
  display: flex;
  flex-direction: column;
  margin-left: 13px;
}

.eyebrow {
  color: var(--color-primary);
  font-size: 9px;
  font-weight: 700;
}

.score-label {
  margin-top: 2px;
  font-size: 19px;
  font-weight: 700;
}

.meta {
  margin-top: 4px;
  color: var(--color-text-secondary);
  font-size: 10px;
}

.summary {
  display: block;
  margin-top: 8px;
  padding: 6px 9px;
  border: 1px solid var(--color-primary-40);
  border-radius: 4px;
  background-color: var(--color-surface-highlight);
  font-size: 10px;
  line-height: 14px;
}

.dimension-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 4px 13px;
  margin-top: 8px;
}

.dimension-item {
  min-height: 20px;
}

.dimension-line {
  justify-content: space-between;
}

.dimension-name, .dimension-value {
  font-size: 9px;
}

.dimension-value {
  color: var(--color-text-secondary);
}

.mini-track {
  height: 3px;
  margin-top: 4px;
  border-radius: 2px;
  background-color: var(--color-primary-40);
}

.mini-fill {
  height: 3px;
  border-radius: 2px;
  background-color: var(--color-primary);
}

.notes-row {
  gap: 8px;
  margin-top: 7px;
}

.note-card {
  flex-grow: 1;
  flex-basis: 0;
  padding: 5px 7px;
  border: 1px solid var(--border-color-muted);
  border-radius: 8px;
}

.note-label {
  display: block;
  color: var(--color-primary);
  font-size: 9px;
  font-weight: 700;
}

.note-copy {
  display: block;
  margin-top: 3px;
  color: var(--color-text-secondary);
  font-size: 8px;
}

.completion-line {
  justify-content: space-between;
  margin-top: 5px;
  color: var(--color-text-secondary);
  font-size: 9px;
}

.actions {
  gap: 9px;
  margin-top: 7px;
}

.primary-btn, .ghost-btn {
  min-height: 32px;
  border-radius: 9px;
  font-size: 12px;
  font-weight: 700;
}

.btn-selected {
  border: 3px solid var(--color-primary);
  background-color: rgba(64, 255, 94, 0.18);
  box-shadow: 0 0 10px rgba(64, 255, 94, 0.48);
}

.primary-btn {
  flex-grow: 1;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  gap: 6px;
  border: 2px solid var(--color-primary);
  color: var(--color-background);
  background-color: var(--color-primary);
}

.ghost-btn {
  min-width: 120px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  gap: 6px;
  border: 2px solid var(--border-color-default);
  color: var(--color-text-primary);
  background-color: transparent;
}

.medical-note {
  display: block;
  margin-top: 5px;
  color: var(--color-text-secondary);
  font-size: 8px;
  text-align: center;
}
</style>

