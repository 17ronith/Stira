import { GoogleGenAI } from "@google/genai";

// Initialize the client. 
// Note: In a production environment, API calls should ideally be proxied through a backend 
// to protect the API key, but for this client-side demo, we use it directly as requested.
const ai = new GoogleGenAI({ apiKey: process.env.API_KEY });

export const generatePersonalizedValue = async (problem: string): Promise<string> => {
  try {
    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents: `User's distraction problem: "${problem}".`,
      config: {
        systemInstruction: "You are the intelligent advocate for 'Stira', a Chrome extension that filters YouTube educational content. Stira removes distractions (Shorts, comments, sidebars, unrelated recommendations) specifically to help users 'lock in' and focus purely on learning. The user will describe why they think Stira might help or what distraction problem they have. Write a single, punchy, motivating sentence (max 15 words) explaining how Stira specifically solves that problem by filtering the noise or enabling deep focus.",
        temperature: 0.7,
      },
    });

    return response.text || "Filter the noise and lock in on your education.";
  } catch (error) {
    console.error("Gemini API Error:", error);
    return "Lock in and focus purely on the content that matters.";
  }
};