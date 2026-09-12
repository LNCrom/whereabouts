import { invitationLinks } from './invitation.mjs';

const status = document.querySelector('#status');
try {
  const links = invitationLinks(location.hash);
  const open = document.querySelector('#open');
  const copy = document.querySelector('#copy');
  open.href = links.native;
  open.hidden = false;
  copy.hidden = false;
  status.textContent = 'Ready to review in Whereabouts. If the app is not installed, install it first, then return to this invitation.';
  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(links.share);
      status.textContent = 'Copied. In Whereabouts, open People, then Join with invitation.';
    } catch {
      status.textContent = 'Clipboard access was not available. Use Open in Whereabouts instead.';
    }
  });
} catch {
  status.textContent = 'This invitation is incomplete or invalid. Ask the sender for a new Whereabouts invitation.';
}
