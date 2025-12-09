// gemini.ts
// No API calls — just returns a random motivating message.

const messages = [
  "Stira blocks distractions so you can lock in and learn faster.",
  "Stay focused, stay sharp — Stira filters the noise.",
  "No sidebars. No comments. Just learning.",
  "Clear the clutter. Focus on what matters.",
  "Remove distractions, unlock deep study.",
  "Stira cuts the noise so your brain can focus.",
  "Turn YouTube into a classroom, not a circus."
];

export const generatePersonalizedValue = async (): Promise<string> => {
  const randomIndex = Math.floor(Math.random() * messages.length);
  return messages[randomIndex];
};
