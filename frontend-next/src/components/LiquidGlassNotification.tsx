'use client';

import { useState, useEffect } from 'react';

interface LiquidGlassNotificationProps {
  message?: string;
  amount?: string;
  timestamp?: string;
  isVisible?: boolean;
  onClose?: () => void;
  autoHideDelay?: number;
  position?: 'top' | 'bottom' | 'center';
  variant?: 'penalty' | 'reward' | 'reminder';
}

export default function LiquidGlassNotification({
  message = "💸 ur wallet lazy f*ck",
  amount = "-$1.00",
  timestamp = "now",
  isVisible = true,
  onClose,
  autoHideDelay = 5000,
  position = 'top',
  variant = 'penalty'
}: LiquidGlassNotificationProps) {
  const [show, setShow] = useState(isVisible);
  const [isAnimatingOut, setIsAnimatingOut] = useState(false);

  useEffect(() => {
    setShow(isVisible);
  }, [isVisible]);

  useEffect(() => {
    if (show && autoHideDelay > 0) {
      const timer = setTimeout(() => {
        handleClose();
      }, autoHideDelay);

      return () => clearTimeout(timer);
    }
  }, [show, autoHideDelay]);

  const handleClose = () => {
    setIsAnimatingOut(true);
    setTimeout(() => {
      setShow(false);
      setIsAnimatingOut(false);
      onClose?.();
    }, 300);
  };

  const getPositionClasses = () => {
    switch (position) {
      case 'top':
        return 'top-6';
      case 'bottom':
        return 'bottom-6';
      case 'center':
        return 'top-1/2 transform -translate-y-1/2';
      default:
        return 'top-6';
    }
  };

  const getVariantColors = () => {
    switch (variant) {
      case 'penalty':
        return {
          text: 'text-red-400',
          glow: 'shadow-red-500/20'
        };
      case 'reward':
        return {
          text: 'text-green-400',
          glow: 'shadow-green-500/20'
        };
      case 'reminder':
        return {
          text: 'text-blue-400',
          glow: 'shadow-blue-500/20'
        };
      default:
        return {
          text: 'text-green-400',
          glow: 'shadow-green-500/20'
        };
    }
  };

  const colors = getVariantColors();

  if (!show) return null;

  return (
    <div className={`absolute ${getPositionClasses()} left-1/2 transform -translate-x-1/2 z-50 w-80`}>
      <div 
        className={`
          relative overflow-hidden
          bg-white/50 backdrop-blur-2xl border border-white/20
          rounded-2xl p-4 shadow-lg
          transition-all duration-500 ease-out
          ${isAnimatingOut ? 'opacity-0 scale-95 translate-y-[-10px]' : 'opacity-100 scale-100 translate-y-0'}
          ${show ? 'animate-slide-down' : 'translate-y-[-20px] opacity-0'}
        `}
        style={{
          background: 'rgba(255, 255, 255, 0.4)',
          boxShadow: '0 8px 32px rgba(0, 0, 0, 0.08), inset 0 1px 0 rgba(255, 255, 255, 0.4)'
        }}
      >


        <div className="relative flex items-center justify-between">
          {/* Left side - App icon and content */}
          <div className="flex items-center space-x-1.5 flex-1">
            {/* Tally app icon */}
            <div className="relative">
              <div 
                className="w-8 h-8 bg-black rounded-xl flex items-center justify-center shadow-sm"
                style={{
                  background: 'linear-gradient(135deg, #000000 0%, #1a1a1a 100%)',
                  boxShadow: '0 1px 4px rgba(0, 0, 0, 0.3), inset 0 1px 0 rgba(255, 255, 255, 0.1)'
                }}
              >
                <span 
                  className="text-white font-normal text-xs"
                  style={{ fontFamily: 'var(--font-eb-garamond), serif' }}
                >
                  tally.
                </span>
              </div>
            </div>

            {/* Notification content */}
            <div className="flex-1 min-w-0">
              <div 
                className="text-white text-sm font-normal leading-tight"
                style={{ fontFamily: 'var(--font-sf-pro), -apple-system, BlinkMacSystemFont, sans-serif' }}
              >
                {message}{' '}
                <span className={`font-semibold ${colors.text}`}>
                  {amount}
                </span>
              </div>
            </div>
          </div>

          {/* Right side - Timestamp */}
          <div className="flex items-center space-x-2 ml-3">
            <span 
              className="text-white/70 text-xs font-normal"
              style={{ fontFamily: 'var(--font-sf-pro), -apple-system, BlinkMacSystemFont, sans-serif' }}
            >
              {timestamp}
            </span>
            
            {/* Close button (optional) */}
            {onClose && (
              <button
                onClick={handleClose}
                className="w-5 h-5 flex items-center justify-center text-white/50 hover:text-white/80 transition-colors"
              >
                <svg className="w-3 h-3" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
                </svg>
              </button>
            )}
          </div>
        </div>


      </div>
    </div>
  );
}