const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const http = require('node:http');
const os = require('node:os');
const path = require('node:path');
const { execFileSync, spawn } = require('node:child_process');

const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'dcc-runtime-'));
const packages = {};
const tarballs = {};
const requests = [];
const old = new Date(Date.now() - 40 * 86400000).toISOString();
const recent = new Date(Date.now() - 86400000).toISOString();
const server = http.createServer((req, res) => {
    requests.push(req.url);
    const body = tarballs[req.url] || (packages[req.url] && JSON.stringify(packages[req.url]));
    res.writeHead(body ? 200 : 404, { 'Content-Type': tarballs[req.url] ? 'application/octet-stream' : 'application/json' });
    res.end(body || '{"error":"not found"}');
});
const run = (exe, args, cwd = dir) => new Promise((resolve, reject) => {
    const child = spawn(exe, args, { cwd, env: process.env });
    let output = '';
    child.stdout.on('data', data => { output += data; });
    child.stderr.on('data', data => { output += data; });
    child.on('error', reject);
    child.on('close', status => resolve({ status, output }));
});
async function main() {
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    const registry = `http://127.0.0.1:${server.address().port}/`;
    const pack = (name, version, time, extra = {}) => {
        const packageDir = path.join(dir, `${name}-${version}`, 'package');
        fs.mkdirSync(packageDir, { recursive: true });
        const manifest = { name, version, ...extra };
        fs.writeFileSync(path.join(packageDir, 'package.json'), JSON.stringify(manifest));
        fs.writeFileSync(path.join(packageDir, 'index.js'), `module.exports=${JSON.stringify(version)};\n`);
        if (extra.bin) {
            fs.writeFileSync(path.join(packageDir, 'cli.js'),
                '#!/usr/bin/env node\nconsole.log("fixture CLI "+require("dcc-fixture-dep"));\n');
            fs.chmodSync(path.join(packageDir, 'cli.js'), 0o755);
        }
        const archive = execFileSync('tar', ['czf', '-', '-C', path.dirname(packageDir), 'package']);
        const url = `/${name}/-/${name}-${version}.tgz`;
        tarballs[url] = archive;
        const metadata = packages[`/${name}`] ||= { name, 'dist-tags': {}, versions: {}, time: {} };
        metadata['dist-tags'].latest = version;
        metadata.time[version] = time;
        metadata.versions[version] = { ...manifest, dist: { tarball: registry.slice(0, -1) + url,
            integrity: `sha512-${crypto.createHash('sha512').update(archive).digest('base64')}` } };
    };
    pack('dcc-fixture-dep', '1.0.0', old);
    pack('dcc-fixture-dep', '1.0.1', recent);
    pack('dcc-fixture-cli', '1.0.0', old, {
        dependencies: { 'dcc-fixture-dep': '^1.0.0' },
        bin: { 'dcc-fixture-cli': 'cli.js' },
        scripts: { postinstall: `node -e "require('fs').writeFileSync('${dir}/SCRIPT-RAN','bad')"` }
    });
    pack('dcc-fixture-recent', '1.0.0', recent);
    pack('dcc-fixture-missing-time', '1.0.0', undefined);
    const config = await run('pnpm', ['config', 'get', 'minimumReleaseAge', '--global']);
    assert.equal(config.status, 0, config.output);
    assert.equal(config.output.trim(), '20160');
    const global = await run('pnpm', ['add', '-g', `--config.registry=${registry}`, 'dcc-fixture-cli']);
    assert.equal(global.status, 0, global.output);
    const cli = await run('dcc-fixture-cli', []);
    assert.equal(cli.status, 0, cli.output);
    assert.match(cli.output, /fixture CLI 1.0.0/);
    assert.equal(fs.existsSync(path.join(dir, 'SCRIPT-RAN')), false);
    assert.equal(requests.some(url => url.endsWith('dcc-fixture-dep-1.0.1.tgz')), false);

    const ui = path.join(dir, 'ui');
    fs.mkdirSync(ui);
    fs.writeFileSync(path.join(ui, 'package.json'), '{"name":"fixture-ui","version":"1.0.0"}');
    fs.writeFileSync(path.join(ui, '.npmrc'), `registry=${registry}\n`);
    const local = await run('pnpm', ['add', 'dcc-fixture-cli'], ui);
    assert.equal(local.status, 0, local.output);
    const localCli = await run('pnpm', ['exec', 'dcc-fixture-cli'], ui);
    assert.equal(localCli.status, 0, localCli.output);
    assert.match(localCli.output, /fixture CLI 1.0.0/);
    assert.equal(fs.existsSync(path.join(dir, 'SCRIPT-RAN')), false);
    for (const name of ['dcc-fixture-recent', 'dcc-fixture-missing-time']) {
        const failure = await run('pnpm', ['add', '-g', `--config.registry=${registry}`, name]);
        assert.notEqual(failure.status, 0, failure.output);
    }
    console.log('runtime assertions passed');
}
main().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => {
    server.close();
    fs.rmSync(dir, { recursive: true, force: true });
});
