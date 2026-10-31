import { expect, test } from 'bun:test';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../modules/play-provenance-repair/webroot/index.html', import.meta.url), 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];

function harness(exec) {
  const elements = new Map();
  const document = {
    getElementById(id) {
      if (!elements.has(id)) elements.set(id, {
        textContent: '', style: {}, classList: { add() {}, remove() {} },
      });
      return elements.get(id);
    },
  };
  const context = vm.createContext({ document, window: {}, confirm: () => true,
    setInterval: () => 1, clearInterval() {}, Date, console });
  const end = script.indexOf('  let searchTimer;');
  vm.runInContext(script.slice(0, end) + `
    globalThis.api = { runLongBackend, repairSelected, statusFor,
      configure(mock) { exec = mock; sleep = async () => {}; allowPaint = async () => {};
        selected = { pkg: 'com.example.app', info: {} }; }
    };
  })();`, context);
  context.api.configure(exec);
  return { api: context.api, element: id => document.getElementById(id) };
}

const reply = (stdout = '', errno = 0) => ({ stdout, errno, stderr: '' });

for (const invalid of ['', 'garbage', '-1', '0junk']) {
  test(`missing or invalid result ${JSON.stringify(invalid)} cannot report success`, async () => {
    let reads = 0;
    const { api } = harness(async command => {
      if (command.includes('& echo $!')) return reply('123');
      if (command.includes('alive=1')) return reply('rc=pending\nalive=0\n');
      if (command.startsWith('if [ -f')) return reply(invalid);
      if (command.startsWith('cat ')) { reads++; return reply('partial transcript'); }
      return reply();
    });
    await expect(api.runLongBackend('repair', 'com.example.app')).rejects.toThrow('without returning a result');
    expect(reads).toBe(1);
  });
}

test('valid late result is accepted and transcript preserved', async () => {
  const { api } = harness(async command => {
    if (command.includes('& echo $!')) return reply('123');
    if (command.includes('alive=1')) return reply('rc=pending\nalive=0\n');
    if (command.startsWith('if [ -f')) return reply('0\n');
    if (command.startsWith('cat ')) return reply('SUCCESS\n');
    return reply();
  });
  const result = await api.runLongBackend('repair', 'com.example.app');
  expect(result.errno).toBe(0);
  expect(result.stdout).toBe('SUCCESS\n');
});

for (const [errno, transcript, expected] of [
  [0, 'SUCCESS\n', 'Repair succeeded; refresh failed'],
  [3, 'reinstallCompleted=true\n', 'Reinstall succeeded; verification failed'],
  [2, 'reinstallCompleted=true\n', 'Reinstall succeeded; verification failed'],
  [1, 'ERROR: install failed\n', 'Repair failed'],
]) {
  test(`repair outcome ${errno} shows ${expected}`, async () => {
    const { api, element } = harness(async command => {
      if (command.includes('& echo $!')) return reply('123');
      if (command.includes('alive=1')) return reply(`rc=${errno}\nalive=0\n`);
      if (command.startsWith('cat ')) return reply(transcript);
      if (command.includes(' inspect ')) return reply('metadata unavailable', 1);
      return reply();
    });
    await api.repairSelected();
    expect(element('status').textContent).toBe(expected);
    expect(element('progressTitle').textContent).toBe(expected);
    expect(element('output').textContent).toContain(transcript.trim());
    expect(element('repairBtn').disabled).toBe(false);
  });
}

test('missing provenance is unknown; explicit null is known unattributed', () => {
  const { api } = harness(async () => reply());
  expect(api.statusFor({})[0]).toBe('Metadata unavailable');
  expect(api.statusFor({ installerPackageName: 'null', initiatingPackageName: 'null' })[0])
    .toBe('Not Play-attributed');
});
