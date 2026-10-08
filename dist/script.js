const header = document.querySelector('[data-header]');
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
  work: { title: '“Here’s what I’m seeing...”', copy: 'Start with the observation you can stand behind. The rest gets easier once the ground is solid.' },
  home: { title: '“This is what I need to feel okay.”', copy: 'A boundary is information, not a punishment. Get specific about the condition that helps you stay in the relationship.' },
  self: { title: '“The honest answer is probably...”', copy: 'Make the private argument visible. Naming the tradeoff is often the first step toward choosing it.' },
  debate: { title: '“I can hold both of these things.”', copy: 'A nuanced point is still a point. Give it a structure strong enough to carry the complexity.' },
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

const form = document.querySelector('[data-access-form]');
const success = document.querySelector('[data-form-success]');
form?.addEventListener('submit', (event) => {
  event.preventDefault();
  const email = new FormData(form).get('email');
  if (!email) return;
  form.querySelector('input').setAttribute('aria-invalid', 'false');
  form.querySelector('.form-row').hidden = true;
  form.querySelector('.form-note').hidden = true;
  success.hidden = false;
});

let lastScroll = 0;
window.addEventListener('scroll', () => {
  const currentScroll = window.scrollY;
  header?.classList.toggle('is-scrolled', currentScroll > 18);
  lastScroll = currentScroll;
}, { passive: true });
