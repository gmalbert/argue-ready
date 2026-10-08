const menuToggle = document.querySelector('.menu-toggle');
const mobileMenu = document.querySelector('#mobile-menu');

menuToggle?.addEventListener('click', () => {
  const isOpen = menuToggle.getAttribute('aria-expanded') === 'true';
  menuToggle.setAttribute('aria-expanded', String(!isOpen));
  menuToggle.setAttribute('aria-label', isOpen ? 'Open menu' : 'Close menu');
  mobileMenu.hidden = isOpen;
});

mobileMenu?.querySelectorAll('a').forEach((link) => link.addEventListener('click', () => {
  menuToggle.setAttribute('aria-expanded', 'false');
  menuToggle.setAttribute('aria-label', 'Open menu');
  mobileMenu.hidden = true;
}));

const revealObserver = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (entry.isIntersecting) {
      entry.target.classList.add('is-visible');
      revealObserver.unobserve(entry.target);
    }
  });
}, { threshold: 0.12 });
document.querySelectorAll('.reveal').forEach((element) => revealObserver.observe(element));

const caseDetails = {
  prep: { title: '“Here’s the obligation I can’t miss.”', copy: 'Start with the proposition the court must understand. Then give the argument a structure that can survive interruption.' },
  podium: { title: '“I can see what is covered.”', copy: 'Keep the issue tree, standard of review, authorities, and requested relief visible without turning the screen into a teleprompter.' },
  bench: { title: '“Answer the question. Keep the thread.”', copy: 'Surface the prepared response, then return to the next unfinished obligation instead of rebuilding your place from memory.' },
  rebuttal: { title: '“Protect the time that remains.”', copy: 'Keep the reserved rebuttal clock and the strongest prepared responses close enough to use when it matters.' },
};
const detail = document.querySelector('[data-case-detail]');
const detailTitle = document.querySelector('[data-detail-title]');
const detailCopy = document.querySelector('[data-detail-copy]');
document.querySelectorAll('[data-case]').forEach((card) => card.addEventListener('click', () => {
  const content = caseDetails[card.dataset.case];
  document.querySelectorAll('[data-case]').forEach((item) => item.classList.remove('case-card-active'));
  card.classList.add('case-card-active');
  detailTitle.textContent = content.title;
  detailCopy.textContent = content.copy;
  detail.classList.add('is-visible');
}));
document.querySelector('.detail-close')?.addEventListener('click', () => detail.classList.remove('is-visible'));
