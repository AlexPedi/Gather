'use strict';
const search = document.getElementById('demo-search');
const cards = [...document.querySelectorAll('.sample-card')];
const filters = [...document.querySelectorAll('[data-filter]')];
let selected = 'all';
function renderExamples() {
  const query = search.value.trim().toLowerCase();
  let count = 0;
  for (const card of cards) {
    const matches = (selected === 'all' || card.dataset.category === selected) && (!query || card.dataset.search.includes(query) || card.textContent.toLowerCase().includes(query));
    card.hidden = !matches;
    count += Number(matches);
  }
  document.getElementById('demo-empty').hidden = count !== 0;
  document.getElementById('demo-count').textContent = `${count} sample screenshot${count === 1 ? '' : 's'} · Your library will use your own content.`;
  for (const filter of filters) {
    const active = filter.dataset.filter === selected;
    filter.classList.toggle('active', active);
    filter.setAttribute('aria-pressed', String(active));
  }
}
filters.forEach(button => button.addEventListener('click', () => { selected = button.dataset.filter; renderExamples(); }));
search.addEventListener('input', renderExamples);
document.getElementById('demo-reset').addEventListener('click', () => { selected = 'all'; search.value = ''; renderExamples(); search.focus(); });
// Open the release note when linked directly, including from the download disclosures.
function revealLinkedDisclosure() {
  if (location.hash === '#release-note') document.getElementById('release-note').open = true;
}
window.addEventListener('hashchange', revealLinkedDisclosure);
revealLinkedDisclosure();

const walkSteps = [...document.querySelectorAll('[data-walk]')];
const walkthroughCopy = {
  capture: ['Your next weekend away', '⌘ ⇧ 4', 'Same shortcut. Same habit.', 'Choose what to capture. Gather handles what comes next.'],
  organize: ['Gather · Just added', '✓', 'Added to your library. Ready to revisit.', 'Suggestions come from screenshot text. You can edit them anytime.'],
  find: ['Gather · Search', '⌕', 'Found by what’s inside, not what it’s called.', 'Search recognized text across your own screenshot library.']
};
walkSteps.forEach(button => button.addEventListener('click', () => {
  const stage = button.dataset.walk;
  document.getElementById('walk-scene').dataset.stage = stage;
  walkSteps.forEach(step => {
    step.classList.toggle('active', step === button);
    step.setAttribute('aria-pressed', String(step === button));
  });
  document.getElementById('walk-metadata').hidden = stage !== 'organize';
  document.getElementById('walk-search').hidden = stage !== 'find';
  document.getElementById('walk-result').hidden = stage !== 'find';
  const [title, icon, status, note] = walkthroughCopy[stage];
  document.getElementById('walk-window-title').textContent = title;
  const statusLine = document.getElementById('walk-status');
  statusLine.replaceChildren();
  const badge = document.createElement('span'); badge.setAttribute('aria-hidden', 'true'); badge.textContent = icon;
  statusLine.append(badge, document.createTextNode(status));
  document.getElementById('walk-bottom-note').textContent = note;
}));
