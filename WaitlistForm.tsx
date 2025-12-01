import React, { useState } from 'react';
import { Button } from './Button';
import { CheckCircle, ArrowRight } from 'lucide-react';

// IMPORTANT: Replace this with your actual Google Apps Script Web App URL
const APPS_SCRIPT_URL = 'YOUR_APPS_SCRIPT_URL';

export const WaitlistForm: React.FC = () => {
  const [email, setEmail] = useState('');
  const [status, setStatus] = useState<'idle' | 'loading' | 'success' | 'error'>('idle');

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;
    
    setStatus('loading');
    
    // Check if the URL is still the placeholder.
    // If it is, we simulate a successful submission for demonstration purposes.
    if (APPS_SCRIPT_URL === 'YOUR_APPS_SCRIPT_URL') {
      setTimeout(() => {
        console.log("Simulating submission to: " + APPS_SCRIPT_URL);
        console.log("Payload:", { email, source: 'stira_landing_page' });
        setStatus('success');
        setEmail('');
      }, 1500);
      return;
    }

    try {
      const response = await fetch(APPS_SCRIPT_URL, {
        method: 'POST',
        // 'text/plain' is often more reliable for CORS in Apps Script simple triggers, 
        // but we'll use application/json as requested.
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ 
          email, 
          source: 'stira_landing_page',
          timestamp: new Date().toISOString()
        })
      });

      const data = await response.json();

      if (data.status === 'ok' || response.ok) {
        setStatus('success');
        setEmail('');
      } else {
        setStatus('error');
      }
    } catch (error) {
      console.error("Submission error:", error);
      // In many CORS no-cors scenarios with Apps Script, the fetch might fail or return opaque responses.
      // If you experience issues, try changing mode to 'no-cors' or Content-Type to 'text/plain'.
      setStatus('error');
    }
  };

  if (status === 'success') {
    return (
      <div className="flex flex-col items-center justify-center p-8 bg-green-50 border border-green-100 rounded-2xl animate-fade-in text-center max-w-md mx-auto">
        <div className="w-12 h-12 bg-green-100 rounded-full flex items-center justify-center mb-4 text-green-600">
          <CheckCircle size={24} />
        </div>
        <h3 className="text-xl font-semibold text-green-900 mb-2">You're on the list!</h3>
        <p className="text-green-700">We've reserved your spot to lock in. Keep an eye on your inbox.</p>
        <button 
          onClick={() => setStatus('idle')}
          className="mt-6 text-sm text-green-700 hover:text-green-900 font-medium underline"
        >
          Add another email
        </button>
      </div>
    );
  }

  return (
    <form id="waitlist-form" onSubmit={handleSubmit} className="flex flex-col sm:flex-row gap-3 w-full max-w-md mx-auto">
      <div className="relative flex-grow">
        <div className="absolute inset-y-0 left-0 pl-4 flex items-center pointer-events-none">
          <svg className="h-5 w-5 text-slate-400" viewBox="0 0 24 24" fill="none" stroke="currentColor">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth="2" d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z" />
          </svg>
        </div>
        <input
          id="email"
          type="email"
          required
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="enter@email.com"
          className="w-full pl-11 pr-4 py-4 bg-white border border-slate-200 rounded-full focus:outline-none focus:ring-2 focus:ring-slate-900/10 focus:border-slate-400 transition-all text-slate-800 placeholder-slate-400 shadow-sm hover:border-slate-300"
        />
      </div>
      <Button type="submit" isLoading={status === 'loading'} className="w-full sm:w-auto shrink-0">
        <span>Join Waitlist</span>
        <ArrowRight size={18} className="ml-2" />
      </Button>
      {status === 'error' && (
        <p className="text-red-500 text-xs text-center mt-2 w-full absolute -bottom-6">Something went wrong. Please try again.</p>
      )}
    </form>
  );
};