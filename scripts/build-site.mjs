import { cp, mkdir, readFile, readdir, rm, stat } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'site');
const destination = path.join(root, 'dist');
async function inventory(directory) {
  const paths = [];
  for (const item of await readdir(directory, { withFileTypes: true })) {
    if (['node_modules', '.git', '.cache'].includes(item.name) || item.name.endsWith('.tgz')) throw new Error(`Unwanted export entry: ${item.name}`);
    const full = path.join(directory, item.name);
    if (item.isSymbolicLink()) throw new Error(`Symlink in export: ${full}`);
    if (item.isDirectory()) paths.push(...await inventory(full)); else paths.push(full);
  }
  return paths;
}
const files = await inventory(source);
for (const filename of files.filter(file => file.endsWith('.html'))) {
  const html = await readFile(filename, 'utf8');
  for (const match of html.matchAll(/(?:href|src)="(\.\/?[^"#]+)"/g)) {
    const asset = path.resolve(path.dirname(filename), match[1].split('#')[0]);
    await stat(asset);
  }
  for (const required of ['<title>', 'name="description"', 'rel="icon"', 'property="og:title"', 'property="og:image"']) {
    if (!html.includes(required)) throw new Error(`${filename} missing ${required}`);
  }
}
await rm(destination, { recursive: true, force: true });
await mkdir(destination, { recursive: true });
await cp(source, destination, { recursive: true });
let bytes = 0;
for (const file of await inventory(destination)) bytes += (await stat(file)).size;
console.log(`Production export: ${files.length} files, ${bytes.toLocaleString('en-US')} bytes. Source copied byte-for-byte; no bundler or runtime dependencies.`);
