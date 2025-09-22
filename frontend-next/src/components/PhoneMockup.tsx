import React, { useState, useEffect, useRef, useCallback } from 'react';
import LiquidGlassNotification from './LiquidGlassNotification';

const PhoneMockup = React.memo(function PhoneMockup() {
  const [visibleMessages, setVisibleMessages] = useState<number[]>([]);
  const [typingMessages, setTypingMessages] = useState<number[]>([]);
  const [animatingMessages, setAnimatingMessages] = useState<number[]>([]);
  const [hasAnimated, setHasAnimated] = useState(false);
  const [showNotification, setShowNotification] = useState(false);
  const containerRef = useRef<HTMLDivElement>(null);

  // Calculate scale factor based on viewport width
  // Base size is 480px (lg breakpoint) - this is our reference size
  const getScaleFactor = () => {
    if (typeof window === 'undefined') return 1;
    const viewportWidth = window.innerWidth;
    
    // For medium screens and up, use full size (lg phone)
    if (viewportWidth >= 768) {
      return 1;
    }
    
    // For small screens, scale down proportionally
    const scaleFactor = Math.min(viewportWidth / 1200, 1);
    return Math.max(scaleFactor, 0.6); // Minimum scale of 0.6
  };

  const [scaleFactor, setScaleFactor] = useState(getScaleFactor());
  const [isSmallScreen, setIsSmallScreen] = useState(typeof window !== 'undefined' && window.innerWidth < 768);

  useEffect(() => {
    const handleResize = () => {
      setScaleFactor(getScaleFactor());
      setIsSmallScreen(window.innerWidth < 768);
    };

    window.addEventListener('resize', handleResize);
    return () => window.removeEventListener('resize', handleResize);
  }, []);

  const animateMessages = useCallback(() => {
    // Reset all animation states
    setVisibleMessages([]);
    setTypingMessages([]);
    setAnimatingMessages([]);

    // Simplified message sequence with cumulative timing
    const messages = [
      { isIncoming: true, typingDuration: 1000, delay: 500 },    // Message 0: incoming with typing
      { isIncoming: false, typingDuration: 0, delay: 600 },      // Message 1: outgoing response
      { isIncoming: true, typingDuration: 800, delay: 800 },     // Message 2: incoming with typing
      { isIncoming: false, typingDuration: 0, delay: 1000 },     // Message 3: outgoing response (increased delay)
      { isIncoming: true, typingDuration: 600, delay: 1200 },    // Message 4: incoming with typing (increased delay)
      { isIncoming: false, typingDuration: 0, delay: 600 },      // Message 5: outgoing response (increased delay)
      { isIncoming: false, typingDuration: 0, delay: 1200 }      // Message 7: final outgoing (increased delay)
    ];

    let cumulativeDelay = 0;

    messages.forEach((message, i) => {
      cumulativeDelay += message.delay;
      const currentDelay = cumulativeDelay;

      setTimeout(() => {
        if (message.isIncoming && message.typingDuration > 0) {
          // Add 1 second delay before showing typing bubble
          setTimeout(() => {
            setTypingMessages(prev => [...prev, i]);
            
            // After typing duration, show actual message
            setTimeout(() => {
              setTypingMessages(prev => prev.filter(idx => idx !== i));
              setVisibleMessages(prev => [...prev, i]);
              setAnimatingMessages(prev => [...prev, i]);
            }, message.typingDuration);
          }, 1000 + (i === 2 ? 500 : 0)); // 1 second delay before typing bubble, plus extra 500ms for message 3
        } else {
          // Add 500ms delay before showing outgoing messages for more natural timing
          setTimeout(() => {
            setVisibleMessages(prev => [...prev, i]);
            setTimeout(() => {
              setAnimatingMessages(prev => [...prev, i]);
            }, 50);
          }, 750); // 750ms delay before blue messages appear
        }
      }, currentDelay);

      // Add typing duration and 1-second delay to cumulative delay for next message
      if (message.isIncoming && message.typingDuration > 0) {
        cumulativeDelay += message.typingDuration + 1000; // Add typing duration + 1s delay
      }
    });

    // Animation complete - keep final state (no reset)
  }, []);

  useEffect(() => {
    // Start animations immediately when component mounts
    if (!hasAnimated) {
      setTimeout(() => {
        animateMessages();
        setHasAnimated(true);
      }, 500); // Small delay to ensure component is fully rendered
    }
  }, [hasAnimated, animateMessages]);

  useEffect(() => {
    // Show notification after imsg 5 ("check tally") and before imsg 6 ("oh shit")
    // Only trigger if animations have started
    if (hasAnimated) {
      const notificationTimer = setTimeout(() => {
        setShowNotification(true);
      }, 5000); // Show after 5 seconds to appear after imsg 5

      return () => clearTimeout(notificationTimer);
    }
  }, [hasAnimated]);

  const messageSvgs = [
    '/iphone_visual/imsg1.svg',
    '/iphone_visual/imsg2.svg',
    '/iphone_visual/imsg3.svg',
    '/iphone_visual/imsg4.svg',
    '/iphone_visual/imsg5.svg',
    '/iphone_visual/imsg6.svg',
    '/iphone_visual/imsg7.svg'
  ];

  // Message alignment derived from messages array
  const messageAlignment = [false, true, false, true, false, true, true]; // false = incoming (left), true = outgoing (right)

  // Calculate scaled dimensions
  const phoneWidth = 480 * scaleFactor;
  const phoneHeight = phoneWidth * (852 / 393); // iPhone 16 Pro aspect ratio
  
  // Scale all positioning values proportionally
  const scaledMarginTop = -60 * scaleFactor;
  const scaledMarginLeft = 20 * scaleFactor;
  const scaledMarginRight = 20 * scaleFactor;
  const scaledMarginBottom = 50 * scaleFactor;
  const scaledPaddingTop = 60 * scaleFactor;
  const scaledNotificationMarginTop = 30 * scaleFactor;

  return (
    <div ref={containerRef} className="relative flex items-center justify-center min-h-[300px] sm:min-h-[400px] md:min-h-[450px] w-full overflow-visible py-4 px-4 sm:px-0" style={{ 
      paddingTop: '20px',
      // Shift container down on small screens
      marginTop: isSmallScreen ? '40px' : '0px'
    }}>
      <div className="relative z-10 mx-auto" style={{ transform: `scale(${scaleFactor})`, transformOrigin: 'center center' }}>
        {/* iPhone SVG */}
        <div className="relative">
          {/* Notification overlay on iPhone */}
          <div className="absolute top-0 left-1/2 transform -translate-x-1/2 z-20" style={{ 
            marginTop: `${scaledNotificationMarginTop}px`,
            transform: 'perspective(1000px) rotateX(38deg)',
            transformOrigin: 'center bottom'
          }}>
            <LiquidGlassNotification
              message="💸 ur wallet lazy f*ck"
              amount="-$1.00"
              variant="penalty"
              isVisible={showNotification}
              onClose={() => setShowNotification(false)}
              autoHideDelay={0}
              position="top"
            />
          </div>
          
          {/* Main iPhone SVG with iOS elements included */}
          <img 
            src="/iphone_visual/iphone16pro_mockup.svg" 
            alt="iPhone 16 Pro Mockup"
            style={{ 
              width: `${phoneWidth}px`,
              height: 'auto'
            }}
          />
          
          {/* iMessage Bubbles Overlay */}
          <div className="absolute inset-0 pointer-events-none" style={{
            transform: 'perspective(1000px) rotateX(20deg)',
            transformOrigin: 'center bottom',
            marginTop: `${scaledMarginTop}px`,
            marginLeft: `${scaledMarginLeft}px`,
            marginRight: `${scaledMarginRight}px`,
            marginBottom: `${scaledMarginBottom}px`
          }}>
            <div className="relative w-full h-full">
              {/* Message bubbles positioned over the chat area */}
              <div className="absolute inset-0 flex flex-col justify-start pt-16 px-4" style={{ 
                paddingTop: `${scaledPaddingTop}px`
              }}>
                {messageSvgs.map((svgPath, index) => {
                  const isIncoming = !messageAlignment[index];
                  const isTyping = typingMessages.includes(index);
                  const isVisible = visibleMessages.includes(index);
                  const isAnimating = animatingMessages.includes(index);
                  
                  // Scale margin bottom values proportionally
                  const getScaledMarginBottom = () => {
                    let baseMargin: number;
                    switch (index) {
                      case 0: baseMargin = 4; break;
                      case 2: baseMargin = 20; break;
                      case 5: baseMargin = -21; break;
                      default: baseMargin = -9; break;
                    }
                    return baseMargin * scaleFactor;
                  };
                  
                  return (
                    <div 
                      key={index}
                      className="relative"
                      style={{ 
                        display: (isVisible || isTyping) ? 'flex' : 'none',
                        marginBottom: `${getScaledMarginBottom()}px`
                      }}
                    >
                      <div className={`flex ${messageAlignment[index] ? 'justify-end' : 'justify-start'} w-full`}>
                        <div className={`${messageAlignment[index] ? 'ml-auto' : 'mr-auto'}`} style={{ maxWidth: '75%' }}>
                          
                          {/* Typing Bubble (for incoming messages) */}
                          {isTyping && isIncoming && (
                            <div 
                              className="animate-typing-bubble"
                              style={{ 
                                transform: index === 0 ? 'translateX(0)' : (index === 2 ? 'translateX(0)' : (index === 4 ? 'translateX(8px)' : 'translateX(0)')),
                                opacity: isVisible ? 0 : 1,
                                transition: 'opacity 0.3s ease-in-out'
                              }}
                            >
                              <img 
                                src="/iphone_visual/typing_bubble.svg" 
                                alt="Typing..."
                                className="h-auto"
                                style={{ 
                                  width: 'auto',
                                  minWidth: `${80 * scaleFactor}px`,
                                  maxWidth: `${100 * scaleFactor}px`,
                                  height: `${48 * scaleFactor}px`
                                }}
                              />
                            </div>
                          )}

                          {/* Actual Message */}
                          {isVisible && (
                            <div 
                              className={`relative message-hover ${
                                isIncoming 
                                  ? 'animate-message-appear' 
                                  : isAnimating 
                                    ? 'animate-message-send' 
                                    : 'opacity-0 animate-message-send'
                              }`}
                              style={{ 
                                width: 'auto', 
                                height: 'auto',
                                textAlign: messageAlignment[index] ? 'right' : 'left'
                              }}
                            >
                              <img 
                                src={svgPath} 
                                alt={`Message ${index + 1}`}
                                className="h-auto"
                                style={{ 
                                  width: 'auto',
                                  minWidth: (() => {
                                    if (index === 2 || index === 4 || index === 6) return `${200 * scaleFactor}px`;
                                    if (index === 3) return `${140 * scaleFactor}px`;
                                    return `${160 * scaleFactor}px`;
                                  })(),
                                  maxWidth: (() => {
                                    if (index === 2 || index === 4 || index === 6) return `${400 * scaleFactor}px`;
                                    if (index === 3) return `${300 * scaleFactor}px`;
                                    return `${320 * scaleFactor}px`;
                                  })(),
                                  height: (() => {
                                    if (index === 2 || index === 4 || index === 6) return `${65 * scaleFactor}px`;
                                    if (index === 3) return `${44 * scaleFactor}px`;
                                    return `${48 * scaleFactor}px`;
                                  })(),
                                  transform: (() => {
                                    let baseTransform: number;
                                    switch (index) {
                                      case 1: baseTransform = -1; break;
                                      case 3: baseTransform = 10; break;
                                      case 4: baseTransform = -24; break;
                                      case 5: baseTransform = 24; break;
                                      case 6: baseTransform = 24; break;
                                      case 7: baseTransform = 9; break;
                                      default: baseTransform = 0; break;
                                    }
                                    return `translateX(${baseTransform * scaleFactor}px)`;
                                  })()
                                }}
                              />
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  );
                })}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
});

export default PhoneMockup; 