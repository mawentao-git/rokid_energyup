<script def>
{
  "navigationBarTitleText": "快速护颈",
  "description": "使用头部姿态传感器完成温和护颈动作的互动游戏页面。",
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

const STAGES = [
  {
    name: '姿态校准',
    shortName: '校准',
    type: 'center',
    instruction: '目视前方，下巴微收，肩膀放松',
    targetText: '稳定保持 5 秒'
  },
  {
    name: '晨雾点头',
    shortName: '点头',
    type: 'nod',
    instruction: '缓慢低头，再缓慢回正，不要后仰',
    targetText: '沿纵向光轨往返'
  },
  {
    name: '左右信号塔',
    shortName: '转头',
    type: 'turn',
    instruction: '缓慢向左、回正，再向右、回正',
    targetText: '点亮两侧信号塔'
  },
  {
    name: '呼吸稳定',
    shortName: '呼吸',
    type: 'breathe',
    instruction: '肩膀放松，跟随光环完成 3 轮呼吸',
    targetText: '吸气 3 秒，呼气 3 秒'
  }
];

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function toDegrees(radians) {
  return radians * 180 / Math.PI;
}

function normalizeQuaternion(q) {
  const length = Math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]) || 1;
  return [q[0] / length, q[1] / length, q[2] / length, q[3] / length];
}

function relativeQuaternion(reference, current) {
  const a = normalizeQuaternion(reference);
  const b = normalizeQuaternion(current);
  const inverse = [-a[0], -a[1], -a[2], a[3]];
  return [
    inverse[3] * b[0] + inverse[0] * b[3] + inverse[1] * b[2] - inverse[2] * b[1],
    inverse[3] * b[1] - inverse[0] * b[2] + inverse[1] * b[3] + inverse[2] * b[0],
    inverse[3] * b[2] + inverse[0] * b[1] - inverse[1] * b[0] + inverse[2] * b[3],
    inverse[3] * b[3] - inverse[0] * b[0] - inverse[1] * b[1] - inverse[2] * b[2]
  ];
}

function quaternionToAngles(q) {
  const x = q[0];
  const y = q[1];
  const z = q[2];
  const w = q[3];
  const pitch = Math.atan2(2 * (w * x + y * z), 1 - 2 * (x * x + y * y));
  const yawInput = clamp(2 * (w * y - z * x), -1, 1);
  const yaw = Math.asin(yawInput);
  const roll = Math.atan2(2 * (w * z + x * y), 1 - 2 * (y * y + z * z));
  return {
    pitch: toDegrees(pitch),
    yaw: toDegrees(yaw),
    roll: toDegrees(roll)
  };
}

export default {
  data: {
    phase: 'playing',
    stageIndex: 0,
    stageNumber: 1,
    stageName: STAGES[0].name,
    instruction: STAGES[0].instruction,
    targetText: STAGES[0].targetText,
    statusText: '正在连接姿态传感器',
    sensorLabel: '连接中',
    actionText: '保持自然姿态',
    energyProgress: 0,
    stageProgress: 0,
    paused: false,
    pauseLabel: '暂停',
    canDemo: false,
    fastWarning: false,
    breathLabel: '',
    breathRound: 0,
    selectedIdx: 0
  },

  onLoad() {
    this.orientation = null;
    this.referenceQuaternion = null;
    this.latestAngles = { pitch: 0, yaw: 0, roll: 0 };
    this.lastAngles = { pitch: 0, yaw: 0, roll: 0 };
    this.lastReadingAt = 0;
    this.lastProgressAt = Date.now();
    this.stageState = {};
    this.completedStages = [];
    this.skippedStages = [];
    this.fastWarnings = 0;
    this.balanceValues = [];
    this.motionSamples = 0;
    this.stableMotionSamples = 0;
    this.startedAt = Date.now();
    this.stageTimer = null;
    this.sensorTimeout = null;
    this.nextStageTimer = null;
    this.initialized = false;
  },

  onShow() {
    if (!this.initialized) {
      this.initialized = true;
      this.drawGame(this.latestAngles);
      this.startStage(0);
      this.startSensor();
    }
  },

  onHide() {
    this.cleanup();
  },

  onUnload() {
    this.cleanup();
  },

  getControlItems() {
    if (this.data.phase === 'stopped') {
      return [{ action: 'returnHome', label: '返回首页' }];
    }
    const items = [
      { action: 'togglePause', label: this.data.pauseLabel },
      { action: 'skipStage', label: '跳过本关' }
    ];
    if (this.data.canDemo) {
      items.push({ action: 'completeDemoStep', label: '体验完成' });
    }
    items.push({ action: 'stopForSafety', label: '不适，停止' });
    return items;
  },

  onKeyDown(event) {
    const code = event.code;
    const items = this.getControlItems();
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

  startSensor() {
    try {
      this.orientation = new AbsoluteOrientationSensor({ frequency: 30 });
      this.orientation.addEventListener('reading', (event) => {
        const quaternion = event.quaternion || this.orientation.quaternion;
        if (quaternion) {
          const timestamp = event.timestamp !== undefined && event.timestamp !== null ? event.timestamp : Date.now();
          this.handleReading(quaternion, timestamp);
        }
      });
      this.orientation.addEventListener('error', () => {
        this.enableDemoMode('此设备暂未提供姿态数据');
      });
      this.orientation.start();
      this.sensorTimeout = setTimeout(() => {
        if (!this.referenceQuaternion) {
          this.enableDemoMode('未收到姿态数据');
        }
      }, 3500);
    } catch (error) {
      console.log('Orientation sensor unavailable:', error);
      this.enableDemoMode('姿态传感器不可用');
    }
  },

  enableDemoMode(message) {
    this.setData({
      canDemo: true,
      sensorLabel: '体验模式',
      statusText: message + '，可手动体验流程',
      selectedIdx: 0
    });
  },

  handleReading(quaternion, timestamp) {
    if (this.data.paused || this.data.phase !== 'playing') {
      return;
    }
    if (this.sensorTimeout) {
      clearTimeout(this.sensorTimeout);
      this.sensorTimeout = null;
    }
    if (!this.referenceQuaternion) {
      this.referenceQuaternion = Array.from(quaternion);
      this.lastReadingAt = timestamp;
      this.setData({
        sensorLabel: '姿态已连接',
        statusText: '很好，保持轻松和稳定'
      });
      return;
    }

    const relative = relativeQuaternion(this.referenceQuaternion, Array.from(quaternion));
    const angles = quaternionToAngles(relative);
    const deltaMs = clamp(timestamp - this.lastReadingAt, 0, 100);
    const elapsedSeconds = deltaMs > 0 ? deltaMs / 1000 : 0.033;
    const angularDelta = Math.max(
      Math.abs(angles.pitch - this.lastAngles.pitch),
      Math.abs(angles.yaw - this.lastAngles.yaw),
      Math.abs(angles.roll - this.lastAngles.roll)
    );
    const speed = angularDelta / elapsedSeconds;

    this.lastReadingAt = timestamp;
    this.lastAngles = angles;
    this.latestAngles = angles;
    const stage = STAGES[this.data.stageIndex];
    if (stage && (stage.type === 'nod' || stage.type === 'turn') && angularDelta > 0.15) {
      this.motionSamples += 1;
      if (speed <= 45) {
        this.stableMotionSamples += 1;
      }
    }
    this.checkMovementSpeed(speed);
    this.updateStage(angles, deltaMs || 33);
    this.drawGame(angles);
  },

  checkMovementSpeed(speed) {
    if (speed > 65 && !this.stageState.speedLocked) {
      this.stageState.speedLocked = true;
      this.fastWarnings += 1;
      this.setData({
        fastWarning: true,
        statusText: '慢一点更有效，请回到舒适节奏'
      });
      setTimeout(() => {
        this.stageState.speedLocked = false;
        if (this.data.phase === 'playing') {
          this.setData({ fastWarning: false });
        }
      }, 1200);
    }
  },

  startStage(index) {
    if (index >= STAGES.length) {
      this.finishTraining();
      return;
    }
    const stage = STAGES[index];
    this.stageState = {
      holdMs: 0,
      step: stage.type === 'turn' ? 'firstOut' : 'out',
      firstSign: 0,
      firstAmplitude: 0,
      secondAmplitude: 0,
      speedLocked: false,
      breathElapsed: 0
    };
    if (stage.type === 'center' && this.orientation && this.orientation.quaternion) {
      this.referenceQuaternion = Array.from(this.orientation.quaternion);
    }
    this.lastProgressAt = Date.now();
    this.setData({
      phase: 'playing',
      stageIndex: index,
      stageNumber: index + 1,
      stageName: stage.name,
      instruction: stage.instruction,
      targetText: stage.targetText,
      actionText: stage.type === 'turn' ? '先缓慢向左' : stage.type === 'nod' ? '缓慢低头' : stage.type === 'breathe' ? '准备呼吸' : '保持自然姿态',
      stageProgress: 0,
      energyProgress: Math.round(index / STAGES.length * 100),
      breathLabel: '',
      breathRound: 0,
      fastWarning: false,
      selectedIdx: 0
    });
    this.clearStageTimer();
    if (stage.type === 'breathe') {
      this.startBreathing();
    }
    this.drawGame(this.latestAngles);
  },

  updateStage(angles, deltaMs) {
    const stage = STAGES[this.data.stageIndex];
    if (!stage || stage.type === 'breathe' || this.data.fastWarning) {
      return;
    }
    if (Math.abs(angles.pitch) > 24 || Math.abs(angles.yaw) > 28 || Math.abs(angles.roll) > 20) {
      this.setData({ statusText: '已经足够，请缓慢回到中间' });
      return;
    }

    if (stage.type === 'center') {
      const stable = Math.abs(angles.pitch) < 4 && Math.abs(angles.yaw) < 4 && Math.abs(angles.roll) < 4;
      this.stageState.holdMs = stable ? this.stageState.holdMs + deltaMs : Math.max(0, this.stageState.holdMs - deltaMs);
      const progress = clamp(Math.round(this.stageState.holdMs / 5000 * 100), 0, 100);
      this.setData({
        stageProgress: progress,
        actionText: stable ? '稳定保持 ' + Math.ceil((5000 - this.stageState.holdMs) / 1000) + ' 秒' : '回到中心光圈'
      });
      if (progress >= 100) {
        this.completeStage();
      }
      return;
    }

    if (stage.type === 'nod') {
      if (this.stageState.step === 'out' && Math.abs(angles.pitch) >= 8) {
        this.stageState.step = 'return';
        this.setData({ stageProgress: 55, actionText: '很好，缓慢回正', statusText: '幅度已经足够' });
      } else if (this.stageState.step === 'return' && Math.abs(angles.pitch) <= 3.5) {
        this.setData({ stageProgress: 100 });
        this.completeStage();
      } else {
        const progress = this.stageState.step === 'out' ? clamp(Math.round(Math.abs(angles.pitch) / 8 * 50), 0, 50) : 55;
        this.setData({ stageProgress: progress });
      }
      return;
    }

    if (stage.type === 'turn') {
      this.updateTurnStage(angles.yaw);
    }
  },

  updateTurnStage(yaw) {
    const absoluteYaw = Math.abs(yaw);
    if (this.stageState.step === 'firstOut') {
      this.setData({ stageProgress: clamp(Math.round(absoluteYaw / 10 * 22), 0, 22) });
      if (absoluteYaw >= 10) {
        this.stageState.firstSign = yaw >= 0 ? 1 : -1;
        this.stageState.firstAmplitude = absoluteYaw;
        this.stageState.step = 'firstReturn';
        this.setData({ stageProgress: 25, actionText: '缓慢回到中间', statusText: '左侧信号已捕获' });
      }
      return;
    }
    if (this.stageState.step === 'firstReturn' && absoluteYaw <= 3.5) {
      this.stageState.step = 'secondOut';
      this.setData({ stageProgress: 50, actionText: '现在缓慢向右', statusText: '回正很稳，继续另一侧' });
      return;
    }
    if (this.stageState.step === 'secondOut') {
      const isOpposite = yaw * this.stageState.firstSign < 0;
      const progress = isOpposite ? 50 + clamp(Math.round(absoluteYaw / 10 * 22), 0, 22) : 50;
      this.setData({ stageProgress: progress });
      if (isOpposite && absoluteYaw >= 10) {
        this.stageState.secondAmplitude = absoluteYaw;
        this.stageState.step = 'secondReturn';
        this.balanceValues = [this.stageState.firstAmplitude, this.stageState.secondAmplitude];
        this.setData({ stageProgress: 75, actionText: '最后缓慢回正', statusText: '两侧信号都已点亮' });
      }
      return;
    }
    if (this.stageState.step === 'secondReturn' && absoluteYaw <= 3.5) {
      this.setData({ stageProgress: 100 });
      this.completeStage();
    }
  },

  startBreathing() {
    this.stageState.breathElapsed = 0;
    this.stageTimer = setInterval(() => {
      if (this.data.paused || this.data.phase !== 'playing') {
        return;
      }
      this.stageState.breathElapsed += 100;
      const total = 18000;
      const cycle = this.stageState.breathElapsed % 6000;
      const round = Math.min(3, Math.floor(this.stageState.breathElapsed / 6000) + 1);
      const inhale = cycle < 3000;
      const progress = clamp(Math.round(this.stageState.breathElapsed / total * 100), 0, 100);
      this.setData({
        stageProgress: progress,
        breathRound: round,
        breathLabel: inhale ? '缓慢吸气' : '缓慢呼气',
        actionText: (inhale ? '吸气' : '呼气') + ' · 第 ' + round + ' / 3 轮',
        statusText: '肩膀放松，不要屏住呼吸'
      });
      this.drawGame({ pitch: 0, yaw: 0, roll: 0 }, cycle / 6000);
      if (this.stageState.breathElapsed >= total) {
        this.clearStageTimer();
        this.completeStage();
      }
    }, 100);
  },

  completeStage() {
    if (this.stageState.completed || this.data.phase !== 'playing') {
      return;
    }
    this.stageState.completed = true;
    this.completedStages.push(STAGES[this.data.stageIndex].shortName);
    this.setData({
      phase: 'complete',
      stageProgress: 100,
      energyProgress: Math.round((this.data.stageIndex + 1) / STAGES.length * 100),
      statusText: '本关完成，节奏很舒服',
      actionText: '能量已收集'
    });
    this.drawGame(this.latestAngles);
    this.nextStageTimer = setTimeout(() => {
      this.startStage(this.data.stageIndex + 1);
    }, 900);
  },

  completeDemoStep() {
    if (this.data.canDemo && this.data.phase === 'playing') {
      if (STAGES[this.data.stageIndex].type === 'turn') {
        this.balanceValues = [12, 11];
      }
      this.completeStage();
    }
  },

  togglePause() {
    if (this.data.phase === 'stopped') {
      return;
    }
    const paused = !this.data.paused;
    this.setData({
      paused,
      pauseLabel: paused ? '继续' : '暂停',
      statusText: paused ? '训练已暂停，保持自然姿态' : '已继续，动作保持缓慢'
    });
  },

  skipStage() {
    if (this.data.phase !== 'playing' && this.data.phase !== 'complete') {
      return;
    }
    this.skippedStages.push(STAGES[this.data.stageIndex].shortName);
    this.clearStageTimer();
    if (this.nextStageTimer) {
      clearTimeout(this.nextStageTimer);
      this.nextStageTimer = null;
    }
    this.startStage(this.data.stageIndex + 1);
  },

  stopForSafety() {
    this.cleanup();
    this.setData({
      phase: 'stopped',
      statusText: '训练已立即停止',
      actionText: '请休息并观察身体感受',
      selectedIdx: 0
    });
  },

  returnHome() {
    wx.redirectTo({ url: '/pages/index/index' });
  },

  finishTraining() {
    this.cleanup();
    const totalStages = STAGES.length;
    const completionRatio = this.completedStages.length / totalStages;
    const completionScore = Math.round(completionRatio * 30);
    const stableRatio = this.motionSamples > 0 ? this.stableMotionSamples / this.motionSamples : 0.8;
    const stabilityScore = this.completedStages.length > 0
      ? clamp(Math.round(12 + stableRatio * 13) - this.fastWarnings * 2, 8, 25)
      : 5;
    let balanceScore = this.skippedStages.indexOf('转头') >= 0 ? 8 : 14;
    if (this.balanceValues.length === 2) {
      const difference = Math.abs(this.balanceValues[0] - this.balanceValues[1]);
      balanceScore = clamp(Math.round(20 - difference * 0.8), 10, 20);
    }
    const safetyScore = this.completedStages.length > 0 ? clamp(15 - this.fastWarnings * 2, 7, 15) : 8;
    let history = [];
    try {
      history = wx.getStorageSync('neck_guard_history') || [];
    } catch (error) {
      console.log('History read failed:', error);
    }
    const habitScore = clamp(5 + history.length, 5, 10);
    const score = completionScore + stabilityScore + balanceScore + safetyScore + habitScore;
    const durationSeconds = Math.max(1, Math.round((Date.now() - this.startedAt) / 1000));
    const balanceNote = balanceScore >= 18 ? '左右动作接近，保持舒适即可' : '两侧略有差异，弱侧不要强拉';
    const rhythmNote = this.fastWarnings === 0 ? '整体节奏平稳' : '有 ' + this.fastWarnings + ' 次动作偏快提醒';
    const result = {
      score,
      date: new Date().toLocaleDateString(),
      durationSeconds,
      mode: '快速护颈',
      completed: this.completedStages,
      skipped: this.skippedStages,
      fastWarnings: this.fastWarnings,
      dimensions: [
        { name: '完成度', score: completionScore, max: 30 },
        { name: '节奏稳定', score: stabilityScore, max: 25 },
        { name: '左右平衡', score: balanceScore, max: 20 },
        { name: '安全控制', score: safetyScore, max: 15 },
        { name: '坚持习惯', score: habitScore, max: 10 }
      ],
      summary: score >= 88 ? '本次动作完成得很稳，能量站顺利启动。' : score >= 72 ? '本次训练完成良好，继续保持轻柔节奏。' : '今天完成了适量活动，下次可以更慢、更放松。',
      rhythmNote,
      balanceNote
    };
    history.unshift(result);
    history = history.slice(0, 7);
    try {
      wx.setStorageSync('neck_guard_latest', result);
      wx.setStorageSync('neck_guard_history', history);
    } catch (error) {
      console.log('Result storage failed:', error);
    }
    wx.redirectTo({ url: '/pages/report/report' });
  },

  drawGame(angles, breathPhase) {
    const ctx = wx.createCanvasContext('gameCanvas');
    if (!ctx) {
      return;
    }
    const width = 436;
    const height = 130;
    const stage = STAGES[this.data.stageIndex] || STAGES[0];
    ctx.clearRect(0, 0, width, height);
    ctx.fillStyle = '#07100c';
    ctx.fillRect(0, 0, width, height);

    ctx.strokeStyle = '#274536';
    ctx.lineWidth = 2;
    ctx.setLineDash([6, 7]);
    ctx.beginPath();
    ctx.moveTo(40, 65);
    ctx.lineTo(396, 65);
    ctx.stroke();
    ctx.setLineDash([]);

    if (stage.type === 'center') {
      this.drawCenterGame(ctx, angles);
    } else if (stage.type === 'nod') {
      this.drawNodGame(ctx, angles);
    } else if (stage.type === 'turn') {
      this.drawTurnGame(ctx, angles);
    } else {
      this.drawBreathGame(ctx, breathPhase || 0);
    }
    ctx.flush();
  },

  drawCenterGame(ctx, angles) {
    ctx.strokeStyle = '#40ff5e';
    ctx.globalAlpha = 0.45;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.arc(218, 65, 27, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;
    const x = clamp(218 + angles.yaw * 4, 70, 366);
    const y = clamp(65 + angles.pitch * 3, 22, 108);
    this.drawEnergyBall(ctx, x, y);
  },

  drawNodGame(ctx, angles) {
    ctx.strokeStyle = '#40ff5e';
    ctx.globalAlpha = 0.6;
    ctx.lineWidth = 5;
    ctx.lineCap = 'round';
    ctx.beginPath();
    ctx.moveTo(218, 28);
    ctx.lineTo(218, 102);
    ctx.stroke();
    ctx.globalAlpha = 1;
    ctx.fillStyle = '#163b25';
    ctx.beginPath();
    ctx.arc(218, 102, 10, 0, Math.PI * 2);
    ctx.fill();
    const y = clamp(46 + Math.abs(angles.pitch) * 6, 42, 104);
    this.drawEnergyBall(ctx, 218, y);
  },

  drawTurnGame(ctx, angles) {
    ctx.strokeStyle = '#40ff5e';
    ctx.globalAlpha = 0.55;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(218, 87, 112, Math.PI * 1.12, Math.PI * 1.88);
    ctx.stroke();
    ctx.globalAlpha = 1;
    this.drawTower(ctx, 106, 64, this.stageState.firstAmplitude > 0);
    this.drawTower(ctx, 330, 64, this.stageState.secondAmplitude > 0);
    const x = clamp(218 + angles.yaw * 7, 110, 326);
    const y = 78 - Math.abs(angles.yaw) * 1.5;
    this.drawEnergyBall(ctx, x, y);
  },

  drawTower(ctx, x, y, active) {
    ctx.fillStyle = active ? '#40ff5e' : '#163b25';
    ctx.fillRect(x - 7, y - 22, 14, 44);
    ctx.beginPath();
    ctx.arc(x, y - 27, 7, 0, Math.PI * 2);
    ctx.fill();
  },

  drawBreathGame(ctx, phase) {
    const expansion = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
    const radius = 24 + expansion * 28;
    ctx.strokeStyle = '#40ff5e';
    ctx.globalAlpha = 0.22;
    ctx.lineWidth = 12;
    ctx.beginPath();
    ctx.arc(218, 65, radius + 9, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 0.9;
    ctx.lineWidth = 4;
    ctx.beginPath();
    ctx.arc(218, 65, radius, 0, Math.PI * 2);
    ctx.stroke();
    ctx.globalAlpha = 1;
    this.drawEnergyBall(ctx, 218, 65);
  },

  drawEnergyBall(ctx, x, y) {
    ctx.shadowColor = '#40ff5e';
    ctx.shadowBlur = 14;
    ctx.fillStyle = '#40ff5e';
    ctx.beginPath();
    ctx.arc(x, y, 8, 0, Math.PI * 2);
    ctx.fill();
    ctx.shadowBlur = 0;
  },

  clearStageTimer() {
    if (this.stageTimer) {
      clearInterval(this.stageTimer);
      this.stageTimer = null;
    }
  },

  cleanup() {
    this.clearStageTimer();
    if (this.sensorTimeout) {
      clearTimeout(this.sensorTimeout);
      this.sensorTimeout = null;
    }
    if (this.nextStageTimer) {
      clearTimeout(this.nextStageTimer);
      this.nextStageTimer = null;
    }
    if (this.orientation) {
      this.orientation.stop();
    }
  }
};
</script>

<page>
  <view class="page-shell">
    <view class="game-header">
      <view>
        <text class="stage-kicker">STEP {{stageNumber}} / 4</text>
        <text class="stage-name">{{stageName}}</text>
      </view>
      <view class="sensor-pill {{fastWarning ? 'warning-pill' : ''}}">
        <view class="sensor-dot"></view>
        <text>{{sensorLabel}}</text>
      </view>
    </view>

    <view ink:if="{{phase !== 'stopped'}}" class="game-body">
      <view class="instruction-row">
        <view class="instruction-copy">
          <text class="instruction">{{instruction}}</text>
          <text class="target-text">{{targetText}}</text>
        </view>
        <view class="progress-number">{{stageProgress}}%</view>
      </view>

      <view class="canvas-frame">
        <canvas id="gameCanvas" class="game-canvas" width="436" height="130"></canvas>
        <view ink:if="{{paused}}" class="pause-overlay">
          <text class="pause-title">已暂停</text>
          <text class="pause-copy">保持自然姿态</text>
        </view>
      </view>

      <view class="feedback-row">
        <text class="action-text">{{actionText}}</text>
        <text class="status-text {{fastWarning ? 'warning-text' : ''}}">{{statusText}}</text>
      </view>

      <view class="energy-track">
        <view class="energy-fill" style="width: {{energyProgress}}%;"></view>
      </view>

      <view class="controls">
        <button class="control-btn {{selectedIdx === 0 ? 'btn-selected' : ''}}" bindtap="togglePause">
          <text>{{pauseLabel}}</text>
        </button>
        <button class="control-btn {{selectedIdx === 1 ? 'btn-selected' : ''}}" bindtap="skipStage">
          <text>跳过本关</text>
        </button>
        <button ink:if="{{canDemo}}" class="demo-btn {{selectedIdx === 2 ? 'btn-selected' : ''}}" bindtap="completeDemoStep">
          <text>体验完成</text>
        </button>
        <button class="stop-btn {{selectedIdx === (canDemo ? 3 : 2) ? 'btn-selected' : ''}}" bindtap="stopForSafety">
          <text>不适，停止</text>
        </button>
      </view>
    </view>

    <view ink:else class="stopped-card">
      <view class="stop-icon">!</view>
      <text class="stopped-title">训练已停止</text>
      <text class="stopped-copy">出现疼痛、眩晕或手麻时不要继续。必要时请咨询专业医生。</text>
      <button class="primary-btn {{selectedIdx === 0 ? 'btn-selected' : ''}}" bindtap="returnHome">
        <text>返回首页</text>
      </button>
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

.game-header, .instruction-row, .feedback-row, .controls {
  display: flex;
  align-items: center;
}

.game-header {
  justify-content: space-between;
}

.stage-kicker {
  display: block;
  color: var(--color-primary);
  font-size: 10px;
  font-weight: 700;
}

.stage-name {
  display: block;
  margin-top: 2px;
  font-size: 21px;
  font-weight: 700;
}

.sensor-pill {
  display: flex;
  align-items: center;
  padding: 7px 10px;
  border: 1px solid var(--border-color-muted);
  border-radius: 12px;
  color: var(--color-text-secondary);
  font-size: 10px;
}

.warning-pill {
  border-color: var(--border-color-warning);
}

.sensor-dot {
  width: 6px;
  height: 6px;
  margin-right: 6px;
  border-radius: 3px;
  background-color: var(--color-primary);
}

.game-body {
  margin-top: 10px;
}

.instruction-row {
  min-height: 42px;
  justify-content: space-between;
}

.instruction-copy {
  display: flex;
  flex-direction: column;
}

.instruction {
  font-size: 13px;
  font-weight: 700;
}

.target-text {
  margin-top: 3px;
  color: var(--color-text-secondary);
  font-size: 10px;
}

.progress-number {
  color: var(--color-primary);
  font-size: 20px;
  font-weight: 700;
}

.canvas-frame {
  position: relative;
  width: 436px;
  height: 130px;
  margin-top: 7px;
  overflow: hidden;
  border: 2px solid var(--border-color-muted);
  border-radius: 12px;
  background-color: var(--color-surface);
}

.game-canvas {
  width: 436px;
  height: 130px;
}

.pause-overlay {
  position: absolute;
  inset: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  background-color: rgba(0, 0, 0, 0.88);
}

.pause-title {
  font-size: 19px;
  font-weight: 700;
}

.pause-copy {
  margin-top: 4px;
  color: var(--color-text-secondary);
  font-size: 11px;
}

.feedback-row {
  height: 27px;
  justify-content: space-between;
}

.action-text {
  color: var(--color-primary);
  font-size: 11px;
  font-weight: 700;
}

.status-text {
  color: var(--color-text-secondary);
  font-size: 10px;
}

.warning-text {
  color: var(--border-color-warning);
}

.energy-track {
  width: 100%;
  height: 4px;
  overflow: hidden;
  border-radius: 2px;
  background-color: var(--color-primary-40);
}

.energy-fill {
  height: 4px;
  border-radius: 2px;
  background-color: var(--color-primary);
  transition: width 0.4s ease;
}

.controls {
  margin-top: 10px;
  gap: 7px;
}

.control-btn, .demo-btn, .stop-btn {
  min-height: 34px;
  padding: 0 11px;
  border-radius: 8px;
  background-color: transparent;
  font-size: 11px;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  gap: 5px;
}

.btn-selected {
  border: 3px solid var(--color-primary);
  background-color: rgba(64, 255, 94, 0.18);
  box-shadow: 0 0 10px rgba(64, 255, 94, 0.48);
}

.control-btn {
  color: var(--color-text-primary);
  border: 1px solid var(--border-color-default);
}

.demo-btn {
  color: var(--color-primary);
  border: 1px solid var(--border-color-accent);
}

.stop-btn {
  margin-left: auto;
  color: var(--color-text-secondary);
  border: 1px solid var(--border-color-warning);
}

.stopped-card {
  margin-top: 36px;
  padding: 24px;
  border: 2px solid var(--border-color-warning);
  border-radius: 12px;
  background-color: var(--color-surface);
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
}

.stopped-title {
  display: block;
  margin-top: 10px;
  font-size: 22px;
  font-weight: 700;
}

.stopped-copy {
  display: block;
  margin-top: 8px;
  color: var(--color-text-secondary);
  font-size: 12px;
  line-height: 18px;
}

.primary-btn {
  width: 100%;
  min-height: 40px;
  margin-top: 16px;
  border: 2px solid var(--color-primary);
  border-radius: 10px;
  color: var(--color-background);
  background-color: var(--color-primary);
  font-size: 13px;
  font-weight: 700;
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: center;
  gap: 6px;
}

.medical-note {
  display: block;
  margin-top: 9px;
  color: var(--color-text-secondary);
  font-size: 9px;
}
</style>

