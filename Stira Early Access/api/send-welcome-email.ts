import { Resend } from "resend";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const { email } = req.body;

  try {
    const resend = new Resend(process.env.RESEND_API_KEY);

    await resend.emails.send({
      from: "Stira <onboarding@resend.dev>",
      to: email,
      subject: "👋 Welcome to the Stira Waitlist",
      html: `
        <h2>🎉 You're On the List!</h2>
        <p>Thanks for joining Stira, your distraction-free learning experience!</p>
        <p>We’ll notify you when early access opens. Lock in. 🔒</p>
      `
    });

    return res.status(200).json({ ok: true });
  } catch (err) {
    console.error(err);
    return res.status(500).json({ ok: false, error: err.message });
  }
}
