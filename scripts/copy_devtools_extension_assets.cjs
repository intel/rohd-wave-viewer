#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { fileURLToPath, pathToFileURL } = require('url');

const destination = process.argv[2];
if (!destination) {
  console.error('Usage: copy_devtools_extension_assets.cjs <destination>');
  process.exit(2);
}

const root = path.resolve(__dirname, '..');
const packageConfigPath = path.join(root, '.dart_tool', 'package_config.json');
if (!fs.existsSync(packageConfigPath)) {
  console.error(`Missing ${packageConfigPath}; run flutter pub get first.`);
  process.exit(1);
}

const packageConfig = JSON.parse(fs.readFileSync(packageConfigPath, 'utf8'));
const packageEntry = packageConfig.packages.find(
  entry => entry.name === 'rohd_devtools_widgets',
);
if (!packageEntry) {
  console.error('rohd_devtools_widgets is missing from package_config.json.');
  process.exit(1);
}

const packageRoot = fileURLToPath(
  new URL(packageEntry.rootUri, pathToFileURL(packageConfigPath)),
);
const source = path.join(packageRoot, 'assets', 'extension');
if (!fs.existsSync(source)) {
  console.error(`rohd_devtools_widgets has no extension assets at ${source}.`);
  process.exit(1);
}

const resolvedDestination = path.resolve(destination);
fs.mkdirSync(resolvedDestination, { recursive: true });
fs.cpSync(source, resolvedDestination, { recursive: true, force: true });
