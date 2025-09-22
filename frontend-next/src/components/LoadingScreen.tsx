'use client';

import { useState, useEffect, useRef } from 'react';

interface LoadingScreenProps {
  onComplete: () => void;
}

export default function LoadingScreen({ onComplete }: LoadingScreenProps) {
  const [showContent, setShowContent] = useState(false);
  const [videoLoaded, setVideoLoaded] = useState(false);
  const [canSkip, setCanSkip] = useState(false);
  const videoRef = useRef<HTMLVideoElement>(null);

  useEffect(() => {
    // Show content after initial delay
    const contentTimer = setTimeout(() => {
      setShowContent(true);
    }, 800);

    // Allow skip after 2 seconds
    const skipTimer = setTimeout(() => {
      setCanSkip(true);
    }, 2000);

    return () => {
      clearTimeout(contentTimer);
      clearTimeout(skipTimer);
    };
  }, []);

  const handleVideoLoaded = () => {
    setVideoLoaded(true);
    if (videoRef.current) {
      videoRef.current.play().catch(() => {
        // Auto-play failed, that's okay
      });
    }
  };

  const handleVideoEnded = () => {
    // Auto-complete when video ends
    setTimeout(() => {
      onComplete();
    }, 1000);
  };

  const handleSkip = () => {
    onComplete();
  };

  return (
    <div className="fixed inset-0 z-50 bg-black overflow-hidden">
      {/* Video Background */}
      <div className="absolute inset-0 flex items-center justify-center">
        <video
          ref={videoRef}
          className="w-full h-full object-cover"
          poster="/vid poster img.png"
          onLoadedData={handleVideoLoaded}
          onEnded={handleVideoEnded}
          playsInline
          muted
          preload="auto"
        >
          <source src="/tallycom_finalcut.mp4" type="video/mp4" />
          Your browser does not support the video tag.
        </video>
      </div>

      {/* Overlay Content */}
      <div className="absolute inset-0 bg-black/20 flex flex-col items-center justify-center">

        {/* Loading Indicator (when video is loading) */}
        {!videoLoaded && (
          <div className="absolute bottom-32 left-1/2 transform -translate-x-1/2">
            <div className="flex flex-col items-center space-y-4">
              <div className="w-8 h-8 border-2 border-white/30 border-t-white rounded-full animate-spin"></div>
              <p 
                className="text-white/80 text-sm"
                style={{ fontFamily: 'var(--font-eb-garamond), serif' }}
              >
                loading experience...
              </p>
            </div>
          </div>
        )}

        {/* Skip Button */}
        {canSkip && (
          <div className={`absolute top-8 right-8 transition-all duration-500 ${showContent ? 'opacity-100' : 'opacity-0'}`}>
            <button
              onClick={handleSkip}
              className="group flex items-center space-x-2 bg-white/10 hover:bg-white/20 backdrop-blur-sm border border-white/20 hover:border-white/40 px-4 py-2 rounded-full transition-all duration-300"
            >
              <span 
                className="text-white/80 group-hover:text-white text-sm"
                style={{ fontFamily: 'var(--font-eb-garamond), serif' }}
              >
                skip
              </span>
              <svg 
                className="w-4 h-4 text-white/60 group-hover:text-white/80 transition-colors" 
                fill="none" 
                stroke="currentColor" 
                viewBox="0 0 24 24"
              >
                <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M13 7l5 5m0 0l-5 5m5-5H6" />
              </svg>
            </button>
          </div>
        )}

        {/* Bottom tagline */}
        {videoLoaded && (
          <div className={`absolute bottom-12 left-1/2 transform -translate-x-1/2 transition-all duration-1000 delay-500 ${showContent ? 'opacity-100 translate-y-0' : 'opacity-0 translate-y-4'}`}>
            <p 
              className="text-white/70 text-lg text-center italic"
              style={{ 
                fontFamily: 'var(--font-eb-garamond), serif',
                textShadow: '0 2px 8px rgba(0, 0, 0, 0.8)'
              }}
            >
              bet on yourself.
            </p>
          </div>
        )}
      </div>

      {/* Video Controls Overlay */}
      {videoLoaded && (
        <div className="absolute bottom-8 left-8">
          <button
            onClick={() => {
              if (videoRef.current) {
                if (videoRef.current.paused) {
                  videoRef.current.play();
                } else {
                  videoRef.current.pause();
                }
              }
            }}
            className="bg-white/10 hover:bg-white/20 backdrop-blur-sm border border-white/20 p-2 rounded-full transition-all duration-300"
          >
            <svg className="w-6 h-6 text-white" fill="currentColor" viewBox="0 0 24 24">
              <path d="M8 5v14l11-7z"/>
            </svg>
          </button>
        </div>
      )}
    </div>
  );
} 