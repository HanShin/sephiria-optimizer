#!/usr/bin/env node

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const versionFile = path.join(root, 'VERSION');
const packageFile = path.join(root, 'windows', 'package.json');
const packageLockFile = path.join(root, 'windows', 'package-lock.json');
const infoPlistFile = path.join(root, 'Info.plist');
const semverPattern = /^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;

function fail(message) {
  console.error(message);
  process.exit(1);
}

function validate(version) {
  const match = semverPattern.exec(version);
  if (!match) fail(`올바른 버전이 아닙니다: ${version} (예: 0.2.1)`);
  return match.slice(1).map(Number);
}

function currentVersion() {
  return fs.readFileSync(versionFile, 'utf8').trim();
}

function resolveVersion(request) {
  if (semverPattern.test(request)) return request;
  const parts = validate(currentVersion());
  if (request === 'major') return `${parts[0] + 1}.0.0`;
  if (request === 'minor') return `${parts[0]}.${parts[1] + 1}.0`;
  if (request === 'patch') return `${parts[0]}.${parts[1]}.${parts[2] + 1}`;
  fail(`버전 또는 증가 단위를 입력하세요: patch, minor, major, 0.2.1`);
}

function plistVersion(plist, key) {
  const pattern = new RegExp(`<key>${key}</key>\\s*<string>([^<]+)</string>`);
  return pattern.exec(plist)?.[1] ?? null;
}

function replacePlistVersion(plist, key, version) {
  const pattern = new RegExp(`(<key>${key}</key>\\s*<string>)[^<]+(</string>)`);
  if (!pattern.test(plist)) fail(`Info.plist에서 ${key}을(를) 찾지 못했습니다.`);
  return plist.replace(pattern, `$1${version}$2`);
}

function readVersions() {
  const packageJson = JSON.parse(fs.readFileSync(packageFile, 'utf8'));
  const packageLock = JSON.parse(fs.readFileSync(packageLockFile, 'utf8'));
  const plist = fs.readFileSync(infoPlistFile, 'utf8');
  return {
    VERSION: currentVersion(),
    'windows/package.json': packageJson.version,
    'windows/package-lock.json': packageLock.version,
    'windows/package-lock.json root': packageLock.packages?.['']?.version,
    'Info.plist short version': plistVersion(plist, 'CFBundleShortVersionString'),
    'Info.plist bundle version': plistVersion(plist, 'CFBundleVersion')
  };
}

function check() {
  const expected = currentVersion();
  validate(expected);
  const versions = readVersions();
  const mismatches = Object.entries(versions).filter(([, value]) => value !== expected);
  if (mismatches.length) {
    for (const [location, value] of mismatches) {
      console.error(`${location}: ${value ?? '(없음)'} (기준: ${expected})`);
    }
    process.exit(1);
  }
  console.log(`버전 동기화 확인: ${expected}`);
}

function setVersion(request) {
  const version = resolveVersion(request);
  validate(version);
  const packageJson = JSON.parse(fs.readFileSync(packageFile, 'utf8'));
  const packageLock = JSON.parse(fs.readFileSync(packageLockFile, 'utf8'));
  let plist = fs.readFileSync(infoPlistFile, 'utf8');

  packageJson.version = version;
  packageLock.version = version;
  if (packageLock.packages?.['']) packageLock.packages[''].version = version;
  plist = replacePlistVersion(plist, 'CFBundleShortVersionString', version);
  plist = replacePlistVersion(plist, 'CFBundleVersion', version);

  fs.writeFileSync(versionFile, `${version}\n`);
  fs.writeFileSync(packageFile, `${JSON.stringify(packageJson, null, 2)}\n`);
  fs.writeFileSync(packageLockFile, `${JSON.stringify(packageLock, null, 2)}\n`);
  fs.writeFileSync(infoPlistFile, plist);
  console.log(version);
}

const [command, argument] = process.argv.slice(2);
if (command === 'check') check();
else if (command === 'resolve' && argument) console.log(resolveVersion(argument));
else if (command === 'set' && argument) setVersion(argument);
else fail('사용법: node scripts/version.mjs <check|resolve|set> [patch|minor|major|버전]');
