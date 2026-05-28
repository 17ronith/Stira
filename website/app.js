const root = document.documentElement;
const cursor = document.querySelector(".cursor-light");

window.addEventListener("pointermove", (event) => {
  if (!cursor) return;
  root.style.setProperty("--mouse-x", `${event.clientX}px`);
  root.style.setProperty("--mouse-y", `${event.clientY}px`);
});

const observer = new IntersectionObserver(
  (entries) => {
    entries.forEach((entry) => {
      if (entry.isIntersecting) {
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      }
    });
  },
  { threshold: 0.16 }
);

document.querySelectorAll("[data-reveal]").forEach((element, index) => {
  element.style.transitionDelay = `${Math.min(index * 55, 330)}ms`;
  observer.observe(element);
});

const form = document.querySelector(".signup");

form?.addEventListener("submit", (event) => {
  event.preventDefault();
  const button = form.querySelector("button");
  const input = form.querySelector("input");

  if (!button || !input) return;

  const email = input.value.trim();
  const originalText = button.textContent;
  const subject = encodeURIComponent("Stira early access waitlist");
  const body = encodeURIComponent(
    `Please add me to the Stira early access waitlist.\n\nEmail: ${email}`
  );

  window.location.href = `mailto:?subject=${subject}&body=${body}`;
  button.textContent = "Email opened";
  button.disabled = true;
  input.setAttribute("aria-invalid", "false");

  window.setTimeout(() => {
    button.textContent = originalText;
    button.disabled = false;
    input.value = "";
  }, 2200);
});
