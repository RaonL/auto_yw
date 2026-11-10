'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

// Exercise the shipped script, without a browser dependency or real timers.
const template = fs.readFileSync(path.join(__dirname, '../assets/team-dashboard.html'), 'utf8');
const script = template.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
const start = '2026-11-09T13:00:00Z';
const finish = '2026-11-09T13:01:00Z';
function stage(overrides = {}) {
  return { number: 1, role: 'writer', kind: 'write', revision: 1, status: 'RUNNING',
    started_utc: start, finished_utc: '', artifact_path: 'writer/output/draft.md', ...overrides };
}
function state(overrides = {}) {
  return { task_id: 'fixture', status: 'RUNNING', revision: 1, started_utc: start,
    updated_utc: finish, message: 'Fixture report', stages: [stage()], ...overrides };
}
function render(value, hash = '') {
  const nodes = new Map(), elements = [], timers = new Map(), intervals = [];
  let timerId = 0, reloads = 0, now = Date.parse(finish);
  class Element {
    constructor(tag = 'div') {
      this.tagName = tag; this.children = []; this.dataset = {}; this.attributes = {};
      this.listeners = {}; this.className = ''; this.hidden = false; this.textContent = '';
      elements.push(this);
    }
    append(...children) { this.children.push(...children); }
    setAttribute(name, value) { this.attributes[name] = value; }
    addEventListener(name, listener) { this.listeners[name] = listener; }
    set innerHTML(_) { throw new Error('Untrusted data reached innerHTML'); }
    set outerHTML(_) { throw new Error('Untrusted data reached outerHTML'); }
    insertAdjacentHTML() { throw new Error('Untrusted data reached insertAdjacentHTML'); }
  }
  const document = {
    getElementById(id) { if (!nodes.has(id)) nodes.set(id, new Element()); return nodes.get(id); },
    createElement(tag) { return new Element(tag); },
    querySelectorAll(selector) {
      assert.equal(selector, '.duration');
      return elements.filter(element => element.className === 'duration');
    }
  };
  document.getElementById('team-state').textContent = JSON.stringify(value);
  const location = { hash, pathname: '/C:/team/runs/fixture/dashboard.html', search: '', reload() { reloads++; } };
  const history = { replaceState(_state, _title, url) { location.hash = url.startsWith('#') ? url : ''; } };
  class Clock extends Date { static now() { return now; } }
  vm.runInNewContext(script, {
    document, location, history, Date: Clock, Intl,
    setInterval(callback) { intervals.push(callback); return intervals.length; },
    setTimeout(callback, delay) { const id = ++timerId; timers.set(id, { callback, delay }); return id; },
    clearTimeout(id) { timers.delete(id); }
  });
  return { nodes, elements, timers, location,
    role(name) { return nodes.get('roles').children.find(card => card.dataset.role === name); },
    tick(seconds) { now += seconds * 1000; intervals.forEach(callback => callback()); },
    clickRefresh() { nodes.get('refresh-toggle').listeners.click(); },
    reloadCount() { return reloads; }
  };
}

test('RUNNING highlights only the current role and schedules one reload', () => {
  const ui = render(state());
  assert.equal(ui.role('writer').className, 'role is-active');
  assert.equal(ui.role('writer').children[0].children[1].textContent, '진행 중');
  assert.equal(ui.nodes.get('records').children[0].className, 'current');
  assert.equal(ui.timers.size, 1);
  const timer = [...ui.timers.values()][0];
  assert.equal(timer.delay, 3000);
  timer.callback();
  assert.equal(ui.reloadCount(), 1);
});

test('CANCELLED has no active role or current row after stage normalization', () => {
  const ui = render(state({ status: 'CANCELLED', stages: [stage({ status: 'CANCELLED', finished_utc: finish })] }));
  assert.equal(ui.nodes.get('overall-status').textContent, '중단');
  assert.equal(ui.role('writer').children[0].children[1].textContent, '중단');
  assert.ok(ui.nodes.get('roles').children.every(card => !card.className.includes('is-active')));
  assert.ok(ui.nodes.get('records').children.every(row => row.className !== 'current'));
  assert.equal(ui.timers.size, 0);
});

test('a terminal snapshot never highlights a role even if its last stage was not normalized', () => {
  const ui = render(state({ status: 'CANCELLED' }));
  assert.ok(ui.nodes.get('roles').children.every(card => !card.className.includes('is-active')));
  assert.equal(ui.nodes.get('current-phase').textContent, '중단');
  assert.equal(ui.timers.size, 0);
});

test('revision two leaves research complete and only reviewer awaiting another version', () => {
  const ui = render(state({ revision: 2, stages: [
    stage({ role: 'researcher', kind: 'research', status: 'DONE', finished_utc: finish }),
    stage({ role: 'reviewer', kind: 'review', status: 'NEEDS_CHANGES', finished_utc: finish }),
    stage({ number: 3, revision: 2 })
  ] }));
  assert.equal(ui.role('researcher').children[0].children[1].textContent, '단계 완료');
  assert.equal(ui.role('researcher').children[1].textContent, '자료 조사·근거 정리');
  assert.equal(ui.role('reviewer').children[0].children[1].textContent, '다음 버전 대기');
  assert.equal(ui.role('writer').children[0].children[1].textContent, '진행 중');
});

test('terminal statuses stop refresh and freeze elapsed time', () => {
  for (const status of ['COMPLETED', 'BLOCKED', 'FAILED', 'NEEDS_APPROVAL', 'NEEDS_CHANGES']) {
    const ui = render(state({ status, stages: [stage({ status: status === 'COMPLETED' ? 'DONE' : status, finished_utc: finish })] }));
    assert.equal(ui.timers.size, 0, status);
    assert.equal(ui.nodes.get('refresh-toggle').hidden, true, status);
    assert.equal(ui.nodes.get('elapsed').textContent, '1분 00초', status);
    ui.tick(60);
    assert.equal(ui.nodes.get('elapsed').textContent, '1분 00초', status);
  }
});

test('pause clears refresh and resume schedules it while preserving pause in the URL', () => {
  const ui = render(state());
  ui.clickRefresh();
  assert.equal(ui.timers.size, 0);
  assert.equal(ui.location.hash, '#paused');
  assert.equal(ui.nodes.get('refresh-toggle').attributes['aria-pressed'], 'false');
  ui.clickRefresh();
  assert.equal(ui.timers.size, 1);
  assert.equal(ui.location.hash, '');
  assert.equal(ui.nodes.get('refresh-toggle').attributes['aria-pressed'], 'true');
  assert.equal(render(state(), '#paused').timers.size, 0);
});

test('model-controlled strings remain literal text and unsafe paths produce no link', () => {
  const payload = '</script><img src=x onerror=alert(1)>';
  const ui = render(state({ task_preview: payload, message: payload, error: payload,
    stages: [stage({ status: 'DONE', finished_utc: finish, artifact_path: 'javascript:alert(1)' })] }));
  for (const id of ['task-preview', 'last-report', 'run-error']) assert.equal(ui.nodes.get(id).textContent, payload);
  assert.equal(ui.nodes.get('records').children[0].children[3].children.length, 0);
  assert.ok(!ui.elements.some(element => ['img', 'script'].includes(element.tagName)));
});

test('artifact paths encode filename punctuation and reject traversal', () => {
  const filename = '한글 #?.md';
  const ui = render(state({ status: 'COMPLETED', final_path: 'leader/output/' + filename,
    stages: [stage({ status: 'DONE', finished_utc: finish, artifact_path: 'writer/output/../draft.md' })] }));
  assert.equal(ui.nodes.get('final-link').children[0].href, '../../leader/output/' + encodeURIComponent(filename));
  assert.equal(ui.nodes.get('records').children[0].children[3].children.length, 0);
});

test('review handoff shows the recorded owner and reason; light summaries show no independent review', () => {
  const ui = render(state({ stages: [stage({ kind: 'review', role: 'reviewer', status: 'NEEDS_CHANGES', next_owner: 'researcher', reason: '지원 기간 불일치' })] }));
  assert.match(ui.nodes.get('handoff').textContent, /대리.*지원 기간 불일치/);
  assert.match(ui.nodes.get('review-status').textContent, /수정 요청/);
  const light = render(state({ mode: 'Light', status: 'COMPLETED', stages: [stage({ kind: 'light_write', status: 'DONE' })] }));
  assert.match(light.nodes.get('review-status').textContent, /독립 검수 생략/);
});

test('heartbeat becomes stale after fifteen seconds and UTC time renders in Korea', () => {
  const ui = render(state());
  assert.equal(ui.nodes.get('last-update').textContent, '22:01:00');
  assert.equal(ui.nodes.get('stale').hidden, true);
  ui.tick(16);
  assert.equal(ui.nodes.get('stale').hidden, false);
  assert.match(ui.nodes.get('stale').textContent, /16초/);
  assert.equal(ui.nodes.get('elapsed').textContent, '1분 16초');
});
