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
  prep: { title: '“Here’s the question the court must answer.”', copy: 'Assemble the question presented, key authorities, record locations, themes, vulnerable points, and the answer you want ready.' },
  podium: { title: '“Answer the question in front of you.”', copy: 'Keep the standard of review, record cite, and path to relief within reach without turning the bench sheet into a teleprompter.' },
  bench: { title: '“I know where to go next.”', copy: 'Surface the prepared response to a hard question, then return to the next unfinished obligation instead of rebuilding your place from memory.' },
  rebuttal: { title: '“These are the points that matter.”', copy: 'Mark the strongest responses to statements that were incorrect, incomplete, unsupported, or conceded, then bring them back to your affirmative argument.' },
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
