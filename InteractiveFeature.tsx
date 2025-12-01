import React, { useState } from 'react';
import { generatePersonalizedValue } from '../services/gemini';
import { Button } from './Button';
import { Sparkles, Youtube, Zap } from 'lucide-react';

export const InteractiveFeature: React.FC = () => {
  const [problem, setProblem] = useState('');
  const [response, setResponse] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const handleGenerate = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!problem.trim()) return;

    setLoading(true);
    setResponse(null);
    try {
      const text = await generatePersonalizedValue(problem);
      setResponse(text);
    } catch (err) {
      console.error(err);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="w-full max-w-2xl mx-auto mt-16 p-6 sm:p-10 rounded-3xl bg-white/60 backdrop-blur-xl border border-white/50 shadow-[0_8px_30px_rgb(0,0,0,0.04)] relative overflow-hidden transition-all duration-300 hover:shadow-[0_8px_30px_rgb(0,0,0,0.08)]">
      {/* Decorative background blur */}
      <div className="absolute -top-20 -right-20 w-64 h-64 bg-indigo-100 rounded-full mix-blend-multiply filter blur-3xl opacity-30 animate-blob"></div>
      <div className="absolute -bottom-20 -left-20 w-64 h-64 bg-sky-100 rounded-full mix-blend-multiply filter blur-3xl opacity-30 animate-blob animation-delay-2000"></div>

      <div className="relative z-10">
        <div className="flex items-center gap-2 mb-6 text-indigo-500 font-semibold text-xs uppercase tracking-widest">
          <Zap size={14} />
          <span>The Stira Promise</span>
        </div>
        
        <h3 className="text-3xl font-light text-slate-800 mb-3">
          Why do you need to <span className="font-semibold text-indigo-600">lock in</span>?
        </h3>
        <p className="text-slate-500 mb-8 leading-relaxed">
          Stira is a Chrome extension that filters YouTube to assist you in focusing on educational content without distractions. Tell us what problem you're facing or why you think Stira might help.
        </p>

        <form onSubmit={handleGenerate} className="relative flex items-center group">
          <div className="absolute left-4 text-slate-400">
             <Youtube size={20} />
          </div>
          <input
            type="text"
            value={problem}
            onChange={(e) => setProblem(e.target.value)}
            placeholder="e.g., I get distracted by Shorts when trying to study..."
            className="w-full pl-12 pr-32 py-5 bg-white border border-slate-200 rounded-2xl focus:outline-none focus:ring-4 focus:ring-indigo-500/10 focus:border-indigo-500 transition-all text-slate-800 placeholder-slate-400 shadow-sm"
          />
          <div className="absolute right-2.5">
            <Button 
              type="submit" 
              variant="primary" 
              isLoading={loading}
              className="!py-2.5 !px-5 !text-sm !rounded-xl"
              disabled={!problem}
            >
              Analyze
            </Button>
          </div>
        </form>

        {response && (
          <div className="mt-8 relative">
            <div className="absolute inset-0 bg-gradient-to-r from-indigo-50 to-white rounded-2xl -m-2"></div>
            <div className="relative p-6 border-l-4 border-indigo-500 bg-white/50 rounded-r-2xl animate-fade-in-up">
              <div className="flex items-start gap-3">
                <Sparkles className="text-indigo-500 mt-1 shrink-0" size={20} />
                <p className="text-xl text-slate-800 font-medium leading-relaxed">
                  "{response}"
                </p>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};