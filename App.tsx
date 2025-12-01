import React from 'react';
import { Logo } from './components/Logo';
import { WaitlistForm } from './components/WaitlistForm';
import { InteractiveFeature } from './components/InteractiveFeature';
import { Shield, Zap, Eye, MonitorPlay } from 'lucide-react';

const App: React.FC = () => {
  return (
    <div className="min-h-screen relative overflow-hidden bg-[#fafafa] selection:bg-indigo-100 selection:text-indigo-900">
      {/* Background Decorative Elements - Lighter and Cleaner */}
      <div className="absolute top-0 left-0 w-full h-full overflow-hidden pointer-events-none z-0">
        <div className="absolute -top-[10%] left-[20%] w-[60%] h-[60%] rounded-full bg-indigo-50/60 blur-[100px] opacity-60"></div>
        <div className="absolute top-[10%] right-[10%] w-[40%] h-[40%] rounded-full bg-sky-50/60 blur-[100px] opacity-60"></div>
      </div>

      <nav className="relative z-10 max-w-7xl mx-auto px-6 py-8 flex justify-between items-center">
        <div className="flex items-center gap-3">
          <div className="text-indigo-600">
            <Logo className="w-9 h-9" />
          </div>
          <span className="text-xl font-bold tracking-tight text-slate-900">Stira</span>
        </div>
        <div className="hidden sm:block">
          <a href="#" className="text-sm font-medium text-slate-500 hover:text-indigo-600 transition-colors">Contact</a>
        </div>
      </nav>

      <main className="relative z-10 flex flex-col items-center justify-center px-6 pt-16 pb-32 lg:pt-28">
        <div className="max-w-4xl mx-auto text-center">
          <div className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full bg-white border border-indigo-100 shadow-sm text-indigo-600 text-[11px] font-bold uppercase tracking-widest mb-10 animate-fade-in-down">
            <span className="relative flex h-2 w-2">
              <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-indigo-400 opacity-75"></span>
              <span className="relative inline-flex rounded-full h-2 w-2 bg-indigo-500"></span>
            </span>
            Chrome Extension Beta
          </div>

          <h1 className="text-5xl sm:text-7xl font-bold text-slate-900 tracking-tight mb-8 leading-[1.15]">
            Filter the noise. <br/>
            <span className="text-transparent bg-clip-text bg-gradient-to-r from-indigo-600 to-sky-500">Lock in on Learning.</span>
          </h1>
          
          <p className="text-lg sm:text-xl text-slate-600 mb-12 max-w-2xl mx-auto leading-relaxed font-light">
            Stira is a Chrome extension that filters YouTube educational content to assist you in locking in. We remove distractions—sidebars, comments, and shorts—so you can focus purely on the video.
          </p>

          <WaitlistForm />

          {/* Social Proof / Trust Badges */}
          <div className="mt-16 flex items-center justify-center gap-8 sm:gap-12 text-slate-400">
             <div className="flex flex-col items-center gap-2 group hover:text-indigo-500 transition-colors duration-300">
               <div className="p-3 bg-white rounded-2xl shadow-sm border border-slate-100 group-hover:border-indigo-100 transition-colors">
                 <Shield size={20} />
               </div>
               <span className="font-medium text-xs">Distraction Free</span>
             </div>
             <div className="flex flex-col items-center gap-2 group hover:text-indigo-500 transition-colors duration-300">
                <div className="p-3 bg-white rounded-2xl shadow-sm border border-slate-100 group-hover:border-indigo-100 transition-colors">
                  <MonitorPlay size={20} />
                </div>
               <span className="font-medium text-xs">Educational Only</span>
             </div>
             <div className="flex flex-col items-center gap-2 group hover:text-indigo-500 transition-colors duration-300">
                <div className="p-3 bg-white rounded-2xl shadow-sm border border-slate-100 group-hover:border-indigo-100 transition-colors">
                  <Eye size={20} />
                </div>
               <span className="font-medium text-xs">Deep Focus</span>
             </div>
          </div>
        </div>

        {/* AI Demo Section */}
        <InteractiveFeature />
        
      </main>

      <footer className="relative z-10 border-t border-slate-100 bg-white/40 backdrop-blur-sm">
        <div className="max-w-7xl mx-auto px-6 py-12 flex flex-col md:flex-row justify-between items-center gap-6">
          <p className="text-slate-400 text-sm font-medium">
            &copy; {new Date().getFullYear()} Stira. Lock in.
          </p>
          <div className="flex gap-8">
             <a href="#" className="text-slate-400 hover:text-indigo-600 text-sm font-medium transition-colors">Twitter</a>
             <a href="#" className="text-slate-400 hover:text-indigo-600 text-sm font-medium transition-colors">Chrome Store</a>
             <a href="#" className="text-slate-400 hover:text-indigo-600 text-sm font-medium transition-colors">Privacy</a>
          </div>
        </div>
      </footer>
    </div>
  );
};

export default App;