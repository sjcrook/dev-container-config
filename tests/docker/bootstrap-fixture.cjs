const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync, execFileSync } = require('node:child_process');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dcc-bootstrap-'));
try {
    const npmRoot = execFileSync('npm', ['root', '-g'], { encoding: 'utf8' }).trim();
    fs.writeFileSync(path.join(dir, 'policy.json'), JSON.stringify({ minimumReleaseAge: 20160 }));
    fs.writeFileSync(path.join(dir, 'npm'), `#!/usr/bin/env node
const a=process.argv.slice(2);
if(a[0]==='root') console.log(${JSON.stringify(npmRoot)});
else if(a.includes('engines')) console.log(JSON.stringify({node:process.env.TEST_ENGINE || '>=18'}));
else if(a[0]==='view') console.log(process.env.TEST_METADATA);
else if(a[0]==='install') console.log('INSTALL '+a.join(' '));
else process.exit(99);
`);
    fs.chmodSync(path.join(dir, 'npm'), 0o755);
    const old = new Date(Date.now() - 40 * 86400000).toISOString();
    const recent = new Date(Date.now() - 86400000).toISOString();
    const run = (versions, time, requested = '12', engine = '>=18', name = 'pnpm') => spawnSync(
        process.execPath, ['/installer.cjs', name, requested, path.join(dir, 'policy.json')],
        { encoding: 'utf8', env: { ...process.env, PATH: `${dir}:${process.env.PATH}`,
            TEST_METADATA: JSON.stringify({ versions, time }), TEST_ENGINE: engine } });
    const success = run(['12.1.0', '12.2.0', '13.0.0'], { '12.1.0': old, '12.2.0': recent, '13.0.0': old });
    assert.equal(success.status, 0, success.stderr);
    assert.match(success.stderr, /Selected pnpm@12.1.0/);
    assert.match(success.stdout, /--allow-scripts=pnpm pnpm@12.1.0/);
    const exact = run(['12.1.0'], { '12.1.0': old }, '12.1.0');
    assert.equal(exact.status, 0, exact.stderr);
    for (const [result, error] of [
        [run(['12.2.0'], { '12.2.0': recent }), /No pnpm@12 release satisfies/],
        [run(['12.1.0'], {}), /No pnpm@12 release satisfies/],
        [run(['12.1.0'], { '12.1.0': old }, '12.1.0', '>=999'), /requires Node >=999/],
        [run(['12.2.0'], { '12.2.0': recent }, '12.2.0'), /No pnpm@12.2.0 release satisfies/],
        [run(['11.9.0'], { '11.9.0': old }, '11', '>=18', 'npm'), /npm >=11.10.0 is required/]
    ]) {
        assert.notEqual(result.status, 0, 'invalid selection must fail');
        assert.match(result.stderr, error);
    }
    console.log('bootstrap assertions passed');
} finally {
    fs.rmSync(dir, { recursive: true, force: true });
}
