import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

export default function teardown() {
  execFileSync('bash', [fileURLToPath(new URL('./local-apache.sh', import.meta.url)), 'stop'], { stdio: 'inherit' });
}
