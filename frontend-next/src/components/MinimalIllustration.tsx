'use client';

import { useEffect, useRef } from 'react';

interface MinimalIllustrationProps {
  type: 'mirror' | 'growth' | 'balance' | 'journey';
  className?: string;
}

export default function MinimalIllustration({ type, className = '' }: MinimalIllustrationProps) {
  const pathRef = useRef<SVGPathElement>(null);

  useEffect(() => {
    const path = pathRef.current;
    if (path) {
      const length = path.getTotalLength();
      path.style.strokeDasharray = length.toString();
      path.style.strokeDashoffset = length.toString();
      
      // Animate the path
      setTimeout(() => {
        path.style.transition = 'stroke-dashoffset 2s ease-in-out';
        path.style.strokeDashoffset = '0';
      }, 500);
    }
  }, []);

  const illustrations = {
    mirror: (
      <svg viewBox="0 0 200 200" className={`w-full h-full ${className}`}>
        {/* Person looking in mirror */}
        <g className="illustration-minimal">
          {/* Mirror frame */}
          <rect x="120" y="40" width="60" height="80" rx="4" className="illustration-minimal" />
          
          {/* Person body */}
          <path
            ref={pathRef}
            d="M40 180 L40 120 Q40 100 50 100 L70 100 Q80 100 80 120 L80 180"
            className="illustration-minimal"
          />
          
          {/* Person head */}
          <circle cx="60" cy="85" r="15" className="illustration-minimal" />
          
          {/* Person arm pointing to mirror */}
          <path d="M80 130 L110 120" className="illustration-minimal" />
          
          {/* Reflection in mirror */}
          <circle cx="150" cy="85" r="12" className="illustration-minimal opacity-60" />
          <path d="M150 97 L150 110" className="illustration-minimal opacity-60" />
          
          {/* Inspiration lines from mirror */}
          <path d="M130 60 L120 50" className="illustration-minimal opacity-40" />
          <path d="M150 50 L140 40" className="illustration-minimal opacity-40" />
          <path d="M170 60 L180 50" className="illustration-minimal opacity-40" />
        </g>
      </svg>
    ),
    
    growth: (
      <svg viewBox="0 0 200 200" className={`w-full h-full ${className}`}>
        {/* Growth chart/plant */}
        <g className="illustration-minimal">
          {/* Plant stem */}
          <path
            ref={pathRef}
            d="M100 180 Q100 160 105 140 Q110 120 115 100 Q120 80 125 60"
            className="illustration-minimal"
          />
          
          {/* Leaves */}
          <path d="M105 140 Q95 135 90 140 Q95 145 105 140" className="illustration-minimal" />
          <path d="M115 100 Q125 95 130 100 Q125 105 115 100" className="illustration-minimal" />
          <path d="M125 60 Q135 55 140 60 Q135 65 125 60" className="illustration-minimal" />
          
          {/* Growth indicators */}
          <circle cx="80" cy="160" r="2" className="illustration-minimal opacity-60" />
          <circle cx="75" cy="120" r="2" className="illustration-minimal opacity-60" />
          <circle cx="85" cy="80" r="2" className="illustration-minimal opacity-60" />
          
          {/* Base/ground */}
          <path d="M70 180 L130 180" className="illustration-minimal" />
        </g>
      </svg>
    ),
    
    balance: (
      <svg viewBox="0 0 200 200" className={`w-full h-full ${className}`}>
        {/* Balance/scale */}
        <g className="illustration-minimal">
          {/* Scale base */}
          <path d="M100 180 L100 100" className="illustration-minimal" />
          
          {/* Scale bar */}
          <path
            ref={pathRef}
            d="M60 100 L140 100"
            className="illustration-minimal"
          />
          
          {/* Left scale */}
          <path d="M60 100 L50 120 L70 120 Z" className="illustration-minimal" />
          
          {/* Right scale */}
          <path d="M140 100 L130 120 L150 120 Z" className="illustration-minimal" />
          
          {/* Balance elements */}
          <circle cx="60" cy="115" r="3" className="illustration-minimal" />
          <circle cx="140" cy="115" r="3" className="illustration-minimal" />
          
          {/* Fulcrum */}
          <path d="M95 100 L105 100 L100 110 Z" className="illustration-minimal" />
        </g>
      </svg>
    ),
    
    journey: (
      <svg viewBox="0 0 200 200" className={`w-full h-full ${className}`}>
        {/* Journey path */}
        <g className="illustration-minimal">
          {/* Winding path */}
          <path
            ref={pathRef}
            d="M20 180 Q50 160 80 140 Q110 120 140 100 Q170 80 180 60"
            className="illustration-minimal"
          />
          
          {/* Milestones */}
          <circle cx="50" cy="165" r="3" className="illustration-minimal" />
          <circle cx="100" cy="130" r="3" className="illustration-minimal" />
          <circle cx="150" cy="95" r="3" className="illustration-minimal" />
          
          {/* Start point */}
          <circle cx="20" cy="180" r="4" className="illustration-minimal" />
          
          {/* End point (goal) */}
          <circle cx="180" cy="60" r="4" className="illustration-minimal" />
          <path d="M175 55 L185 55 L180 65 Z" className="illustration-minimal" />
          
          {/* Progress indicators */}
          <path d="M45 170 L50 160" className="illustration-minimal opacity-40" />
          <path d="M95 135 L100 125" className="illustration-minimal opacity-40" />
          <path d="M145 100 L150 90" className="illustration-minimal opacity-40" />
        </g>
      </svg>
    )
  };

  return (
    <div className={`flex items-center justify-center ${className}`}>
      {illustrations[type]}
    </div>
  );
} 