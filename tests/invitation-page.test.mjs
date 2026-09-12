import { test } from 'node:test';
import assert from 'node:assert/strict';
import { invitationLinks } from '../docs/join/invitation.mjs';

test('opens only Whereabouts while preserving the iCloud invitation', () => {
  const share = 'https://www.icloud.com/share/test-family-invitation';
  const links = invitationLinks('#' + new URLSearchParams({ invite: share }));
  const native = new URL(links.native);
  assert.equal(native.protocol, 'whereabouts:');
  assert.equal(native.hostname, 'join');
  assert.equal(native.searchParams.get('invite'), share);
});

test('fails closed for malicious, missing, or ambiguous payloads', () => {
  const bad = ['', '#invite=', '#invite=https://evil.test/share/a',
    '#invite=javascript:alert(1)', '#invite=https://www.icloud.com.evil.test/share/a',
    '#invite=https://www.icloud.com@evil.test/share/a', '#invite=http://www.icloud.com/share/a',
    '#invite=https://www.icloud.com/share/a&invite=https://www.icloud.com/share/b',
    '#invite=https://apps.apple.com/app/id123', '#invite=https://www.icloud.com/share/a%3Fredirect=evil',
    '#invite=https://www.icloud.com/share/a&extra=1', '#invite=' + 'x'.repeat(8192)];
  for (const fragment of bad) assert.throws(() => invitationLinks(fragment), fragment);
});
