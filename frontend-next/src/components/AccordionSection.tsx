import { useState, useRef, useEffect } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Button } from '@/components/ui/Button';

interface AccordionItem {
  title: string;
  content: string;
}

const accordionItems: AccordionItem[] = [
  {
    title: "pick a goal",
    content: "choose from gym, study sessions, wake‑up alarms, screen time limits, or create custom habits. set your schedule and target—daily or weekly."
  },
  {
    title: "set your wager",
    content: "choose a dollar penalty ($5‑$20 hits hardest) that kicks in when you skip. real money on the line > pure willpower."
  },
  {
    title: "link your crew",
    content: "add friends so they see every check‑in, drop hype emojis, and roast you before you ghost your goals."
  },
  {
    title: "show proof",
    content: "snap a photo, start a timer, or track screen time. our ai verifies fast—no fake streaks, zero extra hassle."
  },
  {
    title: "keep (or lose) cash",
    content: "nail the habit, keep every dollar and flex the streak. miss a day, forfeit the cash, then reset and try again tomorrow."
  }
];

export default function AccordionSection() {
  const [activeIndex, setActiveIndex] = useState<number | null>(null);
  const [hoveredIndex, setHoveredIndex] = useState<number | null>(null);
  const accordionRefs = useRef<(HTMLButtonElement | null)[]>([]);

  const setRef = (el: HTMLButtonElement | null, index: number) => {
    accordionRefs.current[index] = el;
  };

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (activeIndex === null) return;

      switch (e.key) {
        case 'ArrowDown':
          e.preventDefault();
          setActiveIndex((prev) => (prev === null || prev >= accordionItems.length - 1) ? 0 : prev + 1);
          break;
        case 'ArrowUp':
          e.preventDefault();
          setActiveIndex((prev) => (prev === null || prev <= 0) ? accordionItems.length - 1 : prev - 1);
          break;
        case 'Enter':
        case ' ':
          e.preventDefault();
          accordionRefs.current[activeIndex]?.click();
          break;
      }
    };

    window.addEventListener('keydown', handleKeyDown);
    return () => window.removeEventListener('keydown', handleKeyDown);
  }, [activeIndex]);

  return (
    <div className="w-full max-w-6xl mx-auto px-4 py-24">
      <h2 className="text-5xl md:text-7xl font-thin mb-20 text-center uppercase tracking-[0.3em]">HOW IT WORKS</h2>
      <div className="space-y-0">
        {accordionItems.map((item, index) => (
          <div key={index} className="relative">
            <motion.button
              ref={(el) => setRef(el, index)}
              className={`w-full text-left px-8 py-10 transition-all duration-300 relative overflow-hidden
                ${activeIndex === index ? 'bg-white text-black' : 'bg-transparent text-white/80 hover:text-white'}
                border-t border-white/10 ${index === accordionItems.length - 1 ? 'border-b' : ''} focus:outline-none`}
              whileHover={{ x: hoveredIndex === index ? 10 : 0 }}
              transition={{ duration: 0.3 }}
              onClick={() => setActiveIndex(activeIndex === index ? null : index)}
              onMouseEnter={() => setHoveredIndex(index)}
              onMouseLeave={() => setHoveredIndex(null)}
              aria-expanded={activeIndex === index}
            >
              {/* Hover gradient */}
              <motion.div
                className="absolute inset-0 gradient-white-transparent"
                initial={{ opacity: 0 }}
                animate={{ opacity: hoveredIndex === index ? 0.05 : 0 }}
                transition={{ duration: 0.3 }}
              />
              <div className="flex items-center gap-8 relative z-10">
                <motion.div 
                  className="text-sm font-light opacity-40 uppercase tracking-widest"
                  animate={{ opacity: hoveredIndex === index || activeIndex === index ? 0.8 : 0.4 }}
                  transition={{ duration: 0.3 }}
                >
                  STEP {String(index + 1).padStart(2, '0')}
                </motion.div>
                <h3 className="text-2xl font-thin uppercase tracking-wider flex-1">{item.title}</h3>
                <motion.div
                  className="transition-transform duration-300"
                  animate={{ rotate: activeIndex === index ? 180 : 0 }}
                >
                  <svg className="w-5 h-5" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                    <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M19 9l-7 7-7-7" />
                  </svg>
                </motion.div>
              </div>
            </motion.button>
            <AnimatePresence>
              {activeIndex === index && (
                <motion.div
                  initial={{ height: 0, opacity: 0 }}
                  animate={{ height: "auto", opacity: 1 }}
                  exit={{ height: 0, opacity: 0 }}
                  transition={{ duration: 0.3 }}
                  className="overflow-hidden"
                >
                  <div className="px-8 pb-10 pt-6 border-t border-white/10">
                    <p className="text-lg leading-relaxed opacity-70 font-light max-w-3xl">{item.content}</p>
                    <Button className="mt-8 uppercase text-sm tracking-widest font-light group relative inline-flex items-center gap-3 bg-transparent border border-white/40 hover:bg-white hover:text-black transition-all duration-300 px-8 py-3">
                      GET STARTED
                      <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" strokeWidth={1.5} stroke="currentColor" className="w-4 h-4 transition-transform group-hover:translate-x-1">
                        <path strokeLinecap="round" strokeLinejoin="round" d="M4.5 12h15m0 0l-6.75-6.75M19.5 12l-6.75 6.75" />
                      </svg>
                    </Button>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        ))}
      </div>
    </div>
  );
} 