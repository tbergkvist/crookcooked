const blob = document.querySelector('.blob');
const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
let timer;

function scheduleGlance() {
  timer = setTimeout(glance, 900 + Math.random() * 1700);
}

function glance() {
  if (reducedMotion.matches || document.hidden) return;
  if (Math.random() < 0.3) {
    blob.classList.add('blink');
    timer = setTimeout(() => {
      blob.classList.remove('blink');
      scheduleGlance();
    }, 110);
  } else {
    const reach = blob.clientWidth * 0.07;
    blob.style.setProperty('--gaze-x', `${(Math.random() * 2 - 1) * reach}px`);
    blob.style.setProperty('--gaze-y', `${(Math.random() - 0.5) * reach}px`);
    scheduleGlance();
  }
}

function resetAnimation() {
  clearTimeout(timer);
  blob.classList.remove('blink');
  blob.style.setProperty('--gaze-x', '0px');
  blob.style.setProperty('--gaze-y', '0px');
  if (!reducedMotion.matches && !document.hidden) scheduleGlance();
}

reducedMotion.addEventListener('change', resetAnimation);
document.addEventListener('visibilitychange', resetAnimation);
resetAnimation();
