const fs = require('node:fs');
const path = require('node:path');
const { execFileSync } = require('node:child_process');

const [name, requested, policyFile] = process.argv.slice(2);
if (!['npm', 'pnpm'].includes(name) || !/^\d+(\.\d+\.\d+)?$/.test(requested || '')) {
    throw new Error('Expected package manager (npm or pnpm), major or exact stable version, and policy file');
}
const policy = JSON.parse(fs.readFileSync(policyFile, 'utf8'));
const npm = (...args) => execFileSync('npm', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] });
const root = npm('root', '--global').trim();
const semver = require(path.join(root, 'npm/node_modules/semver'));
const metadata = JSON.parse(npm('view', name, 'time', 'versions', '--json'));
const cutoff = Date.now() - policy.minimumReleaseAge * 60_000;
const eligible = (metadata.versions || []).filter(version =>
    /^\d+\.\d+\.\d+$/.test(version)
    && (requested.includes('.') ? version === requested : semver.major(version) === Number(requested))
    && Number.isFinite(Date.parse(metadata.time?.[version]))
    && Date.parse(metadata.time[version]) <= cutoff
).sort(semver.rcompare);
if (!eligible.length) {
    throw new Error(`No ${name}@${requested} release satisfies the ${policy.minimumReleaseAge / 1440}-day policy`);
}
const version = eligible[0];
if (name === 'npm' && semver.lt(version, '11.10.0')) {
    throw new Error('npm >=11.10.0 is required to enforce min-release-age');
}
if (name === 'pnpm' && semver.major(version) !== 12) {
    throw new Error('This generator supports pnpm 12 configuration; choose major 12 or an exact 12.x release');
}
const engines = JSON.parse(npm('view', `${name}@${version}`, 'engines', '--json') || '{}');
if (engines.node && !semver.satisfies(process.version, engines.node)) {
    throw new Error(`${name}@${version} requires Node ${engines.node}; found ${process.version}`);
}
console.error(`Selected ${name}@${version} (published ${metadata.time[version]})`);
// pnpm 12 needs install.js to link its platform executable. This exception is
// confined to bootstrap; runtime installs retain the corporate script policy.
execFileSync('npm', ['install', '--global', '--engine-strict',
    `--ignore-scripts=${name === 'pnpm' ? 'false' : 'true'}`,
    ...(name === 'pnpm' ? ['--allow-scripts=pnpm'] : []), `${name}@${version}`],
{ stdio: 'inherit' });
const recordFile = '/usr/local/share/devcontainer/package-managers.json';
fs.mkdirSync(path.dirname(recordFile), { recursive: true });
const record = fs.existsSync(recordFile) ? JSON.parse(fs.readFileSync(recordFile, 'utf8')) : {};
record[name] = { version, published: metadata.time[version] };
fs.writeFileSync(recordFile, `${JSON.stringify(record, null, 2)}\n`);
