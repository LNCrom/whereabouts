export function invitationLinks(fragment) {
  if (fragment.length > 8192) throw new Error('Invalid invitation');
  const values = [...new URLSearchParams(fragment.replace(/^#/, '')).entries()];
  if (values.length !== 1 || values[0][0] !== 'invite') throw new Error('Missing invitation');
  const share = new URL(values[0][1]);
  if (share.protocol !== 'https:' || !['www.icloud.com', 'icloud.com'].includes(share.hostname) ||
      share.username || share.password || share.port || share.search || share.hash ||
      !/^\/share\/[A-Za-z0-9_-]{1,128}$/.test(share.pathname)) throw new Error('Invalid invitation');
  const native = new URL('whereabouts://join');
  native.searchParams.set('invite', share.href);
  return { share: share.href, native: native.href };
}
