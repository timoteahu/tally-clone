"use client";

import { useState, useEffect } from "react";
import Link from "next/link";
import MinimalIllustration from "@/components/MinimalIllustration";
import LiquidGlassNotification from "@/components/LiquidGlassNotification";

import PhoneMockup from "@/components/PhoneMockup";

export default function Home() {
  const [navbarVisible, setNavbarVisible] = useState(true);
  const [isAtTop, setIsAtTop] = useState(true);
  const [lastScrollY, setLastScrollY] = useState(0);
  const [currentTestimonial, setCurrentTestimonial] = useState(0);
  const [expandedFAQ, setExpandedFAQ] = useState<string | null>(null);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);

  // Notification states
  const [showNotification, setShowNotification] = useState(false);
  const [notificationProps, setNotificationProps] = useState({
    message: "she texted him... here's",
    amount: "50¢",
    variant: "reward" as "penalty" | "reward" | "reminder",
  });

  // Animation states
  const [visibleCheckmarks, setVisibleCheckmarks] = useState<number[]>([]);

  const testimonials = [
    {
      quote: "my friends think i'm crazy. my habits think i'm consistent.",
      author: "zoe, 21",
    },
    {
      quote:
        "finally, an app that gets me. losing money hurts more than losing streaks.",
      author: "alex, 19",
    },
    {
      quote: "tally made me realize i'd rather be broke than broken habits.",
      author: "maya, 22",
    },
  ];

  useEffect(() => {
    const testimonialTimer = setInterval(() => {
      setCurrentTestimonial((prev) => (prev + 1) % testimonials.length);
    }, 8000);

    return () => clearInterval(testimonialTimer);
  }, [testimonials.length]);

  // Intersection Observer for checkmark animations
  useEffect(() => {
    const checkmarkObserver = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            const checkmarkIndex = parseInt(
              entry.target.getAttribute("data-checkmark-index") || "0",
            );
            setVisibleCheckmarks((prev) =>
              Array.from(new Set([...prev, checkmarkIndex])),
            );
          }
        });
      },
      {
        threshold: 0.5,
        rootMargin: "0px",
      },
    );

    // Observe all checkmark elements
    const checkmarkElements = document.querySelectorAll(
      "[data-checkmark-index]",
    );
    checkmarkElements.forEach((element) => {
      checkmarkObserver.observe(element);
    });

    return () => {
      checkmarkElements.forEach((element) => {
        checkmarkObserver.unobserve(element);
      });
    };
  }, []);

  useEffect(() => {
    let ticking = false;
    let currentScrollY = 0;

    const handleScroll = () => {
      currentScrollY = window.scrollY;

      if (!ticking) {
        window.requestAnimationFrame(() => {
          // Track if we're at the top of the page
          setIsAtTop(currentScrollY <= 50);

          // Determine if navbar should be visible based on scroll direction and position
          if (currentScrollY <= 50) {
            // At top of page - show navbar
            setNavbarVisible(true);
          } else if (currentScrollY > lastScrollY && currentScrollY > 80) {
            // Scrolling down - hide navbar
            setNavbarVisible(false);
          } else if (currentScrollY < lastScrollY - 5) {
            // Scrolling up - show navbar (with small threshold for responsiveness)
            setNavbarVisible(true);
          }

          setLastScrollY(currentScrollY);
          ticking = false;
        });

        ticking = true;
      }
    };

    window.addEventListener("scroll", handleScroll, { passive: true });
    return () => {
      window.removeEventListener("scroll", handleScroll);
    };
  }, [lastScrollY]);

  const scrollToSection = (sectionId: string) => {
    const element = document.getElementById(sectionId);
    if (element) {
      element.scrollIntoView({ behavior: "smooth" });
    }
  };

  const triggerNotification = (type: "penalty" | "reward" | "reminder") => {
    const notifications = {
      penalty: {
        message: "oops... here's your",
        amount: "$2.50",
        variant: "penalty" as const,
      },
      reward: {
        message: "she texted him... here's",
        amount: "50¢",
        variant: "reward" as const,
      },
      reminder: {
        message: "don't forget your habit check-in",
        amount: "",
        variant: "reminder" as const,
      },
    };

    setNotificationProps(notifications[type]);
    setShowNotification(true);
  };

  const faqItem = (question: string, answer: string | React.ReactNode) => {
    const isExpanded = expandedFAQ === question;

    return (
      <div
        key={question}
        className="group bg-white/8 backdrop-blur-md border border-white/15 overflow-hidden transition-all duration-400 ease-in-out hover:bg-white/12 hover:border-white/25"
        style={{ borderRadius: "20px" }}
      >
        <button
          onClick={() => setExpandedFAQ(isExpanded ? null : question)}
          className="w-full px-4 sm:px-6 md:px-8 py-4 sm:py-6 md:py-7 text-left flex items-center justify-between transition-all duration-300 ease-in-out"
        >
          <span
            className="text-sm sm:text-base md:text-lg text-white font-normal group-hover:text-white/90 transition-colors duration-300"
            style={{ fontFamily: "var(--font-eb-garamond), serif" }}
          >
            {question}
          </span>
          <svg
            className={`w-4 h-4 sm:w-5 sm:h-5 md:w-6 md:h-6 text-white/50 group-hover:text-white/70 transition-all duration-500 ease-in-out ${isExpanded ? "rotate-180" : ""}`}
            fill="none"
            stroke="currentColor"
            viewBox="0 0 24 24"
            strokeWidth={1.5}
          >
            <path
              strokeLinecap="round"
              strokeLinejoin="round"
              d="M19 9l-7 7-7-7"
            />
          </svg>
        </button>

        <div
          className={`transition-all duration-500 ease-in-out ${isExpanded ? "max-h-96 opacity-100" : "max-h-0 opacity-0"} overflow-hidden`}
        >
          <div className="px-4 sm:px-6 md:px-8 pb-4 sm:pb-6 md:pb-8 pt-0">
            <div className="border-t border-white/10 pt-4 sm:pt-6">
              {typeof answer === "string" ? (
                <p
                  className="text-sm sm:text-base text-white/75 leading-relaxed"
                  style={{ fontFamily: "var(--font-eb-garamond), serif" }}
                >
                  {answer}
                </p>
              ) : (
                answer
              )}
            </div>
          </div>
        </div>
      </div>
    );
  };

  return (
    <div className="min-h-screen bg-[#01050B] relative overflow-hidden">
      {/* Radial gradient background */}
      <div
        className="absolute inset-0"
        style={{
          background:
            "radial-gradient(ellipse 80% 30% at 50% 12%, #161C29 6%, #0B0F16 40%, #01050B 80%, transparent 100%)",
        }}
      ></div>
      {/* Header */}
      <header
        className={`fixed top-0 left-0 right-0 z-40 transition-all duration-500 ease-in-out ${
          navbarVisible
            ? "translate-y-0 opacity-100"
            : "-translate-y-full opacity-0"
        }`}
      >
        {/* Desktop Navigation */}
        <div
          className={`${isAtTop && navbarVisible ? "bg-white/0 border-white/0" : "bg-white/10 border-white/20"} backdrop-blur-md border rounded-full mt-4 mx-auto px-3 sm:px-6 py-2 sm:py-3 transition-all duration-300 ease-in-out max-w-6xl hidden md:block`}
        >
          <div className="relative flex items-center">
            {/* Logo - positioned absolutely on the left */}
            <div className="absolute left-0">
              <button
                onClick={() => scrollToSection("hero")}
                className="text-lg sm:text-xl md:text-2xl font-normal text-white transition-colors hover:text-white/80 whitespace-nowrap"
                style={{ fontFamily: "var(--font-eb-garamond), serif" }}
              >
                tally.
              </button>
            </div>

            {/* Centered Navigation - absolutely centered */}
            <div className="absolute left-1/2 transform -translate-x-1/2">
              <nav className="flex items-center space-x-2 sm:space-x-4 md:space-x-8">
                <button
                  onClick={() => scrollToSection("about")}
                  className="text-white/80 hover:text-white transition-all duration-300 ease-in-out text-xs sm:text-sm whitespace-nowrap hover:transform hover:translateY(-1px)"
                >
                  about
                </button>
                <button
                  onClick={() => scrollToSection("features")}
                  className="text-white/80 hover:text-white transition-all duration-300 ease-in-out text-xs sm:text-sm whitespace-nowrap hover:transform hover:translateY(-1px)"
                >
                  features
                </button>
                <button
                  onClick={() => scrollToSection("faq")}
                  className="text-white/80 hover:text-white transition-all duration-300 ease-in-out text-xs sm:text-sm whitespace-nowrap hover:transform hover:translateY(-1px)"
                >
                  faqs
                </button>
                <Link
                  href="/payment"
                  className="text-white/80 hover:text-white transition-all duration-300 ease-in-out text-xs sm:text-sm whitespace-nowrap hover:transform hover:translateY(-1px)"
                >
                  payment
                </Link>
              </nav>
            </div>

            {/* Login/Download - positioned absolutely on the right */}
            <div className="absolute right-0 flex items-center space-x-2 sm:space-x-4">
              <Link
                href="/auth"
                className="text-white/70 hover:text-white transition-all duration-300 ease-in-out text-xs sm:text-sm whitespace-nowrap hover:transform hover:translateY(-1px)"
              >
                log in
              </Link>
              <Link
                href="https://jointally.app.link/"
                className="btn-primary-small text-xs sm:text-sm px-2 sm:px-3 py-1 sm:py-2"
              >
                download
                <svg
                  className="w-2 h-2 sm:w-3 sm:h-3 ml-1 sm:ml-1.5"
                  fill="none"
                  stroke="currentColor"
                  viewBox="0 0 24 24"
                >
                  <path
                    strokeLinecap="round"
                    strokeLinejoin="round"
                    strokeWidth={2}
                    d="M17 8l4 4m0 0l-4 4m4-4H3"
                  />
                </svg>
              </Link>
            </div>

            {/* Invisible spacer to maintain proper height */}
            <div className="w-full h-6 sm:h-8"></div>
          </div>
        </div>

        {/* Mobile Navigation */}
        <div
          className={`${isAtTop && navbarVisible ? "bg-white/0" : "bg-white/10"} backdrop-blur-md mx-0 transition-all duration-300 ease-in-out md:hidden`}
        >
          <div className="flex items-center justify-between px-4 py-3">
            {/* Logo */}
            <button
              onClick={() => scrollToSection("hero")}
              className="text-lg font-normal text-white transition-colors hover:text-white/80"
              style={{ fontFamily: "var(--font-eb-garamond), serif" }}
            >
              tally.
            </button>

            {/* Hamburger Menu */}
            <button
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
              className="text-white hover:text-white/80 transition-colors"
            >
              <svg
                className="w-6 h-6"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  strokeLinecap="round"
                  strokeLinejoin="round"
                  strokeWidth={2}
                  d="M4 6h16M4 12h16M4 18h16"
                />
              </svg>
            </button>
          </div>

          {/* Mobile Menu Overlay */}
          {mobileMenuOpen && (
            <div className="absolute top-full left-0 right-0 bg-white/10 backdrop-blur-md border-t border-white/10">
              <div className="px-4 py-6 space-y-4">
                <button
                  onClick={() => {
                    scrollToSection("about");
                    setMobileMenuOpen(false);
                  }}
                  className="block w-full text-left text-white font-medium py-2 hover:text-white/80 transition-colors"
                >
                  about
                </button>
                <button
                  onClick={() => {
                    scrollToSection("features");
                    setMobileMenuOpen(false);
                  }}
                  className="block w-full text-left text-white font-medium py-2 hover:text-white/80 transition-colors"
                >
                  features
                </button>
                <button
                  onClick={() => {
                    scrollToSection("faq");
                    setMobileMenuOpen(false);
                  }}
                  className="block w-full text-left text-white font-medium py-2 hover:text-white/80 transition-colors"
                >
                  faqs
                </button>
                <Link
                  href="/payment"
                  onClick={() => setMobileMenuOpen(false)}
                  className="block w-full text-left text-white font-medium py-2 hover:text-white/80 transition-colors"
                >
                  payment
                </Link>
                <div className="border-t border-white/20 pt-4 mt-4">
                  <Link
                    href="/auth"
                    onClick={() => setMobileMenuOpen(false)}
                    className="block w-full text-left text-white font-medium py-2 hover:text-white/80 transition-colors"
                  >
                    log in
                  </Link>
                  <Link
                    href="https://jointally.app.link/"
                    onClick={() => setMobileMenuOpen(false)}
                    className="block w-full text-left text-white font-medium py-2 hover:text-white/80 transition-colors"
                  >
                    download
                  </Link>
                </div>
              </div>
            </div>
          )}
        </div>
      </header>

      {/* Hero Section */}
      <section
        id="hero"
        className="relative overflow-hidden z-10"
        style={{ minHeight: "100vh", paddingTop: "0px" }}
      >
        <div className="max-w-7xl mx-auto px-0">
          <div
            className="flex flex-col items-center justify-center text-center"
            style={{
              minHeight: "100vh",
              marginTop: "-20px",
              paddingTop: "250px",
            }}
          >
            {/* "Bet on yourself" Info Blurb */}
            <div
              className="space-y-3 sm:space-y-5 mb-6 sm:mb-10 px-4 sm:px-0"
              style={{ marginTop: "10px" }}
            >
              <h1
                className="text-3xl sm:text-4xl md:text-5xl lg:text-6xl xl:text-7xl font-normal text-white leading-tight fade-in-up"
                style={{
                  fontFamily: "var(--font-eb-garamond), serif",
                }}
              >
                bet on <span className="italic">yourself.</span>
              </h1>

              <p
                className="text-base sm:text-lg md:text-xl lg:text-2xl text-white/80 leading-relaxed fade-in-up max-w-lg mx-auto"
                style={{
                  animationDelay: "0.2s",
                  fontFamily: "var(--font-eb-garamond), serif",
                }}
              >
                welcome to tally.
              </p>
            </div>

            {/* Download Button */}
            <div
              className="fade-in-up mb-6 sm:mb-8 px-4 sm:px-0"
              style={{ animationDelay: "0.3s" }}
            >
              <Link
                href="https://jointally.app.link/"
                className="inline-flex items-center justify-center px-4 sm:px-6 py-2.5 sm:py-3 bg-white text-black font-semibold hover:bg-gray-100 transition-all duration-300 text-sm sm:text-base"
                style={{
                  borderRadius: "50px",
                  animation: "buttonGlowPulse 3s ease-in-out infinite",
                  willChange: "box-shadow",
                  backfaceVisibility: "hidden",
                  transform: "translateZ(0)",
                }}
              >
                <svg
                  className="w-4 h-4 sm:w-5 sm:h-5 mr-2"
                  viewBox="0 0 24 24"
                  fill="currentColor"
                >
                  <path d="M18.71 19.5c-.83 1.24-1.71 2.45-3.05 2.47-1.34.03-1.77-.79-3.29-.79-1.53 0-2 .77-3.27.82-1.31.05-2.3-1.32-3.14-2.53C4.25 17 2.94 12.45 4.7 9.39c.87-1.52 2.43-2.48 4.12-2.51 1.28-.02 2.5.87 3.29.87.78 0 2.26-1.07 3.81-.91.65.03 2.47.26 3.64 1.98-.09.06-2.17 1.28-2.15 3.81.03 3.02 2.65 4.03 2.68 4.04-.03.07-.42 1.44-1.38 2.83M13 3.5c.73-.83 1.94-1.46 2.94-1.5.13 1.17-.34 2.35-1.04 3.19-.69.85-1.83 1.51-2.95 1.42-.15-1.15.41-2.35 1.05-3.11z" />
                </svg>
                download now
              </Link>
            </div>

            {/* Cycling Quotes */}
            <div className="max-w-4xl mx-auto px-4 sm:px-6 text-center py-6 sm:py-8">
              <div
                className="mb-6 sm:mb-8 fade-in-up flex flex-col items-center justify-center"
                style={{ animationDelay: "0.6s", minHeight: "100px" }}
              >
                <blockquote
                  className="text-white/80 italic text-sm sm:text-base md:text-lg mb-2 max-w-lg mx-auto transition-opacity duration-700 ease-in-out px-2"
                  style={{ fontFamily: "var(--font-eb-garamond), serif" }}
                >
                  "{testimonials[currentTestimonial].quote}"
                </blockquote>
                <cite
                  className="text-white/60 text-xs sm:text-sm transition-opacity duration-700 ease-in-out"
                  style={{ fontFamily: "var(--font-eb-garamond), serif" }}
                >
                  - {testimonials[currentTestimonial].author}
                </cite>
              </div>

              {/* Pagination Dots */}
              <div
                className="flex justify-center space-x-2 fade-in-up"
                style={{ animationDelay: "0.7s" }}
              >
                {testimonials.map((_, index) => (
                  <button
                    key={index}
                    onClick={() => setCurrentTestimonial(index)}
                    className={`w-1.5 h-1.5 sm:w-2 sm:h-2 rounded-full transition-all duration-300 ${
                      index === currentTestimonial
                        ? "bg-white"
                        : "bg-white/40 hover:bg-white/60"
                    }`}
                  />
                ))}
              </div>
            </div>

            {/* Phone Mockup - Centered */}
            <div
              className="flex justify-center fade-in-up"
              style={{ animationDelay: "0.3s" }}
            >
              <PhoneMockup />
            </div>

            {/* Scroll Indicator */}
            <div
              className="flex justify-center mt-16 mb-8 fade-in-up"
              style={{ animationDelay: "0.8s" }}
            >
              <div className="flex flex-col items-center space-y-2">
                <span
                  className="text-white/60 text-sm"
                  style={{ fontFamily: "var(--font-eb-garamond), serif" }}
                >
                  scroll to explore
                </span>
                <div
                  className="animate-bounce"
                  style={{ animationDuration: "2s" }}
                >
                  <svg
                    className="w-6 h-6 text-white/60"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      strokeLinecap="round"
                      strokeLinejoin="round"
                      strokeWidth={2}
                      d="M19 14l-7 7m0 0l-7-7m7 7V3"
                    />
                  </svg>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* About Section */}
      <section
        id="about"
        className="section section-spacing relative z-10"
        style={{ paddingTop: "80px" }}
      >
        <div className="container-minimal">
          <div className="text-center mb-16">
            <h2 className="heading-medium text-white mb-4">about tally</h2>
            <p className="text-body text-white/80 max-w-2xl mx-auto">
              gen z's most unhinged habitual growth experiment — featuring
              liquid glass notifications that actually make penalties hurt.
            </p>
          </div>

          <div className="grid grid-cols-1 md:grid-cols-3 gap-6 sm:gap-8">
            <div className="card-minimal text-center">
              <div className="w-16 h-16 sm:w-20 sm:h-20 md:w-24 md:h-24 mx-auto mb-4 sm:mb-6 opacity-60">
                <MinimalIllustration type="balance" />
              </div>
              <h3 className="heading-small text-white mb-3 sm:mb-4">
                financial accountability
              </h3>
              <p className="text-body text-white/80">
                put your money where your mouth is. 50 cent minimum.
              </p>
            </div>

            <div className="card-minimal text-center">
              <div className="w-16 h-16 sm:w-20 sm:h-20 md:w-24 md:h-24 mx-auto mb-4 sm:mb-6 opacity-60">
                <MinimalIllustration type="growth" />
              </div>
              <h3 className="heading-small text-white mb-3 sm:mb-4">
                social accountability
              </h3>
              <p className="text-body text-white/80">
                photo verified habits are posted for all to see. don't be
                stupid.
              </p>
            </div>

            <div className="card-minimal text-center">
              <div className="w-16 h-16 sm:w-20 sm:h-20 md:w-24 md:h-24 mx-auto mb-4 sm:mb-6 opacity-60">
                <MinimalIllustration type="journey" />
              </div>
              <h3 className="heading-small text-white mb-3 sm:mb-4">
                progress over perfection
              </h3>
              <p className="text-body text-white/80">
                celebrate consistency. profit off your friends' lack of
                discipline.
              </p>
            </div>
          </div>

          {/* See it in action */}
          <div className="mt-16 sm:mt-20 md:mt-24">
            <h3 className="heading-small text-white mb-4 sm:mb-6 text-center">
              see it in action
            </h3>
            <div className="max-w-4xl mx-auto px-4 sm:px-0">
              <div className="relative rounded-[20px] sm:rounded-[25px] overflow-hidden bg-white/5 backdrop-blur-sm">
                <video
                  className="w-full h-auto"
                  poster="/vid poster img.png"
                  controls
                  playsInline
                  preload="metadata"
                >
                  <source src="/tallycom_finalcut.mp4" type="video/mp4" />
                  Your browser does not support the video tag.
                </video>
              </div>
            </div>
          </div>

          {/* Habits Verification & Integrations */}
          <div className="mt-32">
            <div className="text-center mb-12">
              <h2 className="heading-medium text-white mb-4">
                your habits, verified & validated
              </h2>
              <p className="text-body text-white/80">
                ai-powered verification meets seamless integrations
              </p>
            </div>

            <div className="grid grid-cols-1 lg:grid-cols-2 gap-6 sm:gap-8 max-w-6xl mx-auto">
              {/* Photo Verification System */}
              <div className="bg-white/5 backdrop-blur-sm p-4 sm:p-6 md:p-8 rounded-[20px] sm:rounded-[25px]">
                <h3 className="heading-small text-white mb-4 sm:mb-6">
                  photo verification system
                </h3>
                <p className="text-body text-white/70 mb-4 sm:mb-6">
                  our ai analyzes your photos to verify habit completion. no
                  more cheating, no more excuses.
                </p>
                <div className="space-y-3 sm:space-y-4">
                  <div
                    className="flex items-start space-x-2 sm:space-x-3"
                    data-checkmark-index="0"
                  >
                    <svg
                      className="w-4 h-4 sm:w-5 sm:h-5 text-white/80 mt-0.5 flex-shrink-0"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M5 13l4 4L19 7"
                        style={{
                          strokeDasharray: 1000,
                          strokeDashoffset: 1000,
                          animation: visibleCheckmarks.includes(0)
                            ? "drawLine 1s ease-out 0.2s forwards"
                            : "none",
                        }}
                      />
                    </svg>
                    <span className="text-white/80 text-body">
                      our own proprietary models
                    </span>
                  </div>
                  <div
                    className="flex items-start space-x-2 sm:space-x-3"
                    data-checkmark-index="1"
                  >
                    <svg
                      className="w-4 h-4 sm:w-5 sm:h-5 text-white/80 mt-0.5 flex-shrink-0"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M5 13l4 4L19 7"
                        style={{
                          strokeDasharray: 1000,
                          strokeDashoffset: 1000,
                          animation: visibleCheckmarks.includes(1)
                            ? "drawLine 1s ease-out 0.4s forwards"
                            : "none",
                        }}
                      />
                    </svg>
                    <span className="text-white/80 text-body">
                      face detection for selfies
                    </span>
                  </div>
                  <div
                    className="flex items-start space-x-2 sm:space-x-3"
                    data-checkmark-index="2"
                  >
                    <svg
                      className="w-4 h-4 sm:w-5 sm:h-5 text-white/80 mt-0.5 flex-shrink-0"
                      fill="none"
                      stroke="currentColor"
                      viewBox="0 0 24 24"
                    >
                      <path
                        strokeLinecap="round"
                        strokeLinejoin="round"
                        strokeWidth={2}
                        d="M5 13l4 4L19 7"
                        style={{
                          strokeDasharray: 1000,
                          strokeDashoffset: 1000,
                          animation: visibleCheckmarks.includes(2)
                            ? "drawLine 1s ease-out 0.6s forwards"
                            : "none",
                        }}
                      />
                    </svg>
                    <span className="text-white/80 text-body">
                      nsfw content filtering
                    </span>
                  </div>
                </div>
              </div>

              {/* Integrations */}
              <div className="bg-white/5 backdrop-blur-sm p-4 sm:p-6 md:p-8 rounded-[20px] sm:rounded-[25px]">
                <h3 className="heading-small text-white mb-4 sm:mb-6">
                  integrations
                </h3>
                <p className="text-body text-white/70 mb-4 sm:mb-6">
                  connect your favorite apps and track habits automatically.
                </p>
                <div className="grid grid-cols-2 gap-3 sm:gap-4">
                  {/* Active integrations */}
                  <div className="flex items-center space-x-2 sm:space-x-3 p-2 sm:p-3 bg-white/10 rounded-xl sm:rounded-2xl border border-white/20 transition-all duration-300 cursor-pointer hover:bg-white/20 hover:border-white/40 hover:transform hover:scale-105 hover:shadow-lg hover:shadow-white/10">
                    <div className="w-6 h-6 sm:w-8 sm:h-8 bg-white/20 rounded-lg flex items-center justify-center transition-all duration-300">
                      <svg
                        className="w-3 h-3 sm:w-5 sm:h-5 text-white transition-all duration-300"
                        fill="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z" />
                      </svg>
                    </div>
                    <span className="text-white/90 text-sm sm:text-base transition-all duration-300">
                      github
                    </span>
                  </div>
                  <div className="flex items-center space-x-2 sm:space-x-3 p-2 sm:p-3 bg-white/10 rounded-xl sm:rounded-2xl border border-white/20 transition-all duration-300 cursor-pointer hover:bg-white/20 hover:border-white/40 hover:transform hover:scale-105 hover:shadow-lg hover:shadow-white/10">
                    <div className="w-6 h-6 sm:w-8 sm:h-8 bg-white/20 rounded-lg flex items-center justify-center transition-all duration-300">
                      <svg
                        className="w-3 h-3 sm:w-5 sm:h-5 text-white transition-all duration-300"
                        fill="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path d="M13.483 0a1.374 1.374 0 0 0-.961.438L7.116 6.226l-3.854 4.126a5.266 5.266 0 0 0-1.209 2.104 5.35 5.35 0 0 0-.125.513 5.527 5.527 0 0 0 .062 2.362 5.83 5.83 0 0 0 .349 1.017 5.938 5.938 0 0 0 1.271 1.818l4.277 4.193.039.038c2.248 2.165 5.852 2.133 8.063-.074l2.396-2.392c.54-.54.54-1.414.003-1.955a1.378 1.378 0 0 0-1.951-.003l-2.396 2.392a3.021 3.021 0 0 1-4.205.038l-.02-.019-4.276-4.193c-.652-.64-.972-1.469-.948-2.263a2.68 2.68 0 0 1 .066-.523 2.545 2.545 0 0 1 .619-1.164L9.13 8.114c1.058-1.134 3.204-1.27 4.43-.278l3.501 2.831c.593.48 1.461.387 1.94-.207a1.384 1.384 0 0 0-.207-1.943l-3.5-2.831c-.8-.647-1.766-1.045-2.774-1.202l2.015-2.158A1.384 1.384 0 0 0 13.483 0zm-2.866 12.815a1.38 1.38 0 0 0-1.38 1.382 1.38 1.38 0 0 0 1.38 1.382H20.79a1.38 1.38 0 0 0 1.38-1.382 1.38 1.38 0 0 0-1.38-1.382z" />
                      </svg>
                    </div>
                    <span className="text-white/90 text-sm sm:text-base transition-all duration-300">
                      leetcode
                    </span>
                  </div>
                  <div className="flex items-center space-x-2 sm:space-x-3 p-2 sm:p-3 bg-white/10 rounded-xl sm:rounded-2xl border border-white/20 transition-all duration-300 cursor-pointer hover:bg-white/20 hover:border-white/40 hover:transform hover:scale-105 hover:shadow-lg hover:shadow-white/10">
                    <div className="w-6 h-6 sm:w-8 sm:h-8 bg-white/20 rounded-lg flex items-center justify-center transition-all duration-300">
                      <svg
                        className="w-3 h-3 sm:w-5 sm:h-5 text-white transition-all duration-300"
                        fill="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path d="M20.84 4.61a5.5 5.5 0 0 0-7.78 0L12 5.67l-1.06-1.06a5.5 5.5 0 0 0-7.78 7.78l1.06 1.06L12 21.23l7.78-7.78 1.06-1.06a5.5 5.5 0 0 0 0-7.78z" />
                      </svg>
                    </div>
                    <span className="text-white/90 text-sm sm:text-base transition-all duration-300">
                      apple health
                    </span>
                  </div>

                  {/* Inactive integrations */}
                  <div className="flex items-center space-x-2 sm:space-x-3 p-2 sm:p-3 bg-white/5 rounded-xl sm:rounded-2xl border border-white/10 opacity-50">
                    <div className="w-6 h-6 sm:w-8 sm:h-8 bg-white/10 rounded-lg flex items-center justify-center">
                      <svg
                        className="w-3 h-3 sm:w-5 sm:h-5 text-white/60"
                        fill="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path d="M12.534 21.77l-1.09-2.81 10.52.54-.451 4.5zM15.06 0L.307 6.969 2.59 17.471H5.6l-.52-7.512.461-.144 1.81 7.656h3.126l-.116-9.15.462-.144 1.582 9.294h3.31l.78-11.053.462-.144.82 11.197h4.376l1.54-15.37Z" />
                      </svg>
                    </div>
                    <span className="text-white/60 text-sm sm:text-base">
                      riot games
                    </span>
                  </div>
                  <div className="flex items-center space-x-2 sm:space-x-3 p-2 sm:p-3 bg-white/5 rounded-xl sm:rounded-2xl border border-white/10 opacity-50">
                    <div className="w-6 h-6 sm:w-8 sm:h-8 bg-white/10 rounded-lg flex items-center justify-center">
                      <span className="text-xs font-semibold text-white/60">
                        ⏱
                      </span>
                    </div>
                    <span className="text-white/60 text-sm sm:text-base">
                      screen time
                    </span>
                  </div>
                  <div className="flex items-center space-x-2 sm:space-x-3 p-2 sm:p-3 bg-white/5 rounded-xl sm:rounded-2xl border border-white/10 opacity-50">
                    <div className="w-6 h-6 sm:w-8 sm:h-8 bg-white/10 rounded-lg flex items-center justify-center">
                      <svg
                        className="w-3 h-3 sm:w-5 sm:h-5 text-white/60"
                        fill="currentColor"
                        viewBox="0 0 24 24"
                      >
                        <path d="M1.5 1.5v21h21v-21h-21zm10.5 18c-3.863 0-7-3.137-7-7s3.137-7 7-7 7 3.137 7 7-3.137 7-7 7zm0-12.5c-3.033 0-5.5 2.467-5.5 5.5s2.467 5.5 5.5 5.5 5.5-2.467 5.5-5.5-2.467-5.5-5.5-5.5zm0 9.5c-2.206 0-4-1.794-4-4s1.794-4 4-4 4 1.794 4 4-1.794 4-4 4z" />
                      </svg>
                    </div>
                    <span className="text-white/60 text-sm sm:text-base">
                      duolingo
                    </span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className="section section-spacing relative z-10">
        <div className="container-minimal">
          <div className="text-center mb-16">
            <h2 className="heading-medium text-white mb-4">how it works</h2>
            <p className="text-body text-white/80 max-w-2xl mx-auto">
              at tally, the honor code doesn't exist — financial and social
              accountability take reign
            </p>
          </div>

          <div className="max-w-6xl mx-auto space-y-12 sm:space-y-16 md:space-y-20">
            {/* Feature 1 */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 sm:gap-12 items-center">
              <div>
                <div className="text-4xl sm:text-5xl md:text-6xl font-normal text-white/20 mb-3 sm:mb-4">
                  01
                </div>
                <h3 className="heading-small text-white mb-3 sm:mb-4">
                  set your accountability price
                </h3>
                <p className="text-body text-white/80 mb-4 sm:mb-6">
                  make it hurt.
                </p>
              </div>
              <div
                className="bg-white/10 backdrop-blur-sm p-2 sm:p-3 md:p-4 h-60 sm:h-72 md:h-80 flex items-center justify-center"
                style={{ borderRadius: "20px" }}
              >
                <img
                  src="/creation.png"
                  alt="Habit creation screen"
                  className="w-full h-full object-contain"
                />
              </div>
            </div>

            {/* Feature 2 */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 sm:gap-12 items-center">
              <div className="order-2 lg:order-1">
                <div
                  className="bg-white/10 backdrop-blur-sm p-2 sm:p-3 md:p-4 h-60 sm:h-72 md:h-80 flex items-center justify-center"
                  style={{ borderRadius: "20px" }}
                >
                  <img
                    src="/photo.png"
                    alt="Photo verification screen"
                    className="w-full h-full object-contain"
                  />
                </div>
              </div>
              <div className="order-1 lg:order-2">
                <div className="text-4xl sm:text-5xl md:text-6xl font-normal text-white/20 mb-3 sm:mb-4">
                  02
                </div>
                <h3 className="heading-small text-white mb-3 sm:mb-4">
                  verify you're not slacking
                </h3>
                <p className="text-body text-white/80 mb-4 sm:mb-6">
                  snap a pic in-app (no you can't submit a pic you took before
                  lol, nice try)
                </p>
              </div>
            </div>

            {/* Feature 3 */}
            <div className="grid grid-cols-1 lg:grid-cols-2 gap-8 sm:gap-12 items-center">
              <div>
                <div className="text-4xl sm:text-5xl md:text-6xl font-normal text-white/20 mb-3 sm:mb-4">
                  03
                </div>
                <h3 className="heading-small text-white mb-3 sm:mb-4">
                  pay, profit, or break even
                </h3>
                <p className="text-body text-white/80 mb-4 sm:mb-6">
                  either pay the price, make a buck or two from your friends, or
                  break even. the choice was and will always be yours.
                </p>
              </div>
              <div
                className="bg-white/5 backdrop-blur-sm p-2 sm:p-3 md:p-4 h-60 sm:h-72 md:h-80 flex items-center justify-center"
                style={{ borderRadius: "20px" }}
              >
                <img
                  src="/feed.png"
                  alt="Community feed screen"
                  className="w-full h-full object-contain"
                />
              </div>
            </div>
          </div>
        </div>
      </section>

      {/* FAQ Section */}
      <section id="faq" className="section section-spacing relative z-10">
        <div className="container-minimal">
          <div className="text-center mb-16">
            <h2 className="heading-medium text-white mb-4">
              frequently asked questions
            </h2>
            <p className="text-body text-white/80 max-w-2xl mx-auto">
              everything you need to know about tally
            </p>
          </div>

          <div className="space-y-6">
            {faqItem(
              "what can i track",
              <div className="space-y-4">
                <div>
                  <h4
                    className="text-base sm:text-lg text-white/90 font-medium mb-2"
                    style={{ fontFamily: "var(--font-eb-garamond), serif" }}
                  >
                    photo verification
                  </h4>
                  <p
                    className="text-sm sm:text-base text-white/75 leading-relaxed"
                    style={{ fontFamily: "var(--font-eb-garamond), serif" }}
                  >
                    gym, alarm, pilates, outdoors, cooking, biking, hiking,
                    anything you can verify with a photo
                  </p>
                </div>
                <div>
                  <h4
                    className="text-base sm:text-lg text-white/90 font-medium mb-2"
                    style={{ fontFamily: "var(--font-eb-garamond), serif" }}
                  >
                    apple health
                  </h4>
                  <p
                    className="text-sm sm:text-base text-white/75 leading-relaxed"
                    style={{ fontFamily: "var(--font-eb-garamond), serif" }}
                  >
                    steps, miles, calories burned, sleeping time, and more
                  </p>
                </div>
                <div>
                  <h4
                    className="text-base sm:text-lg text-white/90 font-medium mb-2"
                    style={{ fontFamily: "var(--font-eb-garamond), serif" }}
                  >
                    integrations
                  </h4>
                  <p
                    className="text-sm sm:text-base text-white/75 leading-relaxed"
                    style={{ fontFamily: "var(--font-eb-garamond), serif" }}
                  >
                    github commits, leetcode problems
                  </p>
                </div>
              </div>,
            )}
            {faqItem(
              "where does money go",
              "recipient-based habits are routed to said recipient.",
            )}
            {faqItem("how are you guys so hot", "idk ask our moms")}
            {faqItem("is this legal", "ya")}
            {faqItem(
              "can i get my money back?",
              "settle that w your recipient!",
            )}
            {faqItem(
              "do you accept crypto?",
              "we accept shame. but for now, just card",
            )}
            {faqItem("is this a cult?", "nah, but we DO have a manifesto")}
          </div>
        </div>
      </section>

      {/* Payment Section */}
      <section id="payment" className="section section-spacing relative z-10">
        <div className="container-minimal text-center">
          <div className="max-w-3xl mx-auto">
            <h2 className="heading-medium text-white mb-6">
              ready to bet on yourself?
            </h2>
            <p className="text-body text-white/80 mb-8">
              join thousands of users who've already started their journey to
              better habits.
              <span className="italic-serif">
                your future self will thank you.
              </span>
            </p>

            <div className="flex items-center justify-center mb-8 sm:mb-12">
              <Link
                href="https://jointally.app.link/"
                className="btn-download text-sm sm:text-base px-6 sm:px-8 py-3 sm:py-4"
              >
                download tally
              </Link>
            </div>

            <div className="text-xs sm:text-small text-white/60 text-center">
              <p>available on the app store</p>
              <p className="mt-1 sm:mt-2">
                privacy-first • no ads • no data selling
              </p>
            </div>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-white/10 py-8 sm:py-12 relative z-10">
        <div className="container-minimal">
          <div className="flex flex-col sm:flex-row items-center justify-between space-y-4 sm:space-y-0">
            <div
              className="text-xl sm:text-2xl font-normal text-white"
              style={{ fontFamily: "var(--font-eb-garamond), serif" }}
            >
              tally.
            </div>
            <div className="flex items-center space-x-4 sm:space-x-6">
              <Link
                href="/privacy"
                className="text-white/60 hover:text-white transition-all duration-300 ease-in-out text-xs sm:text-small hover:transform hover:translateY(-1px)"
              >
                privacy
              </Link>
              <Link
                href="/terms"
                className="text-white/60 hover:text-white transition-all duration-300 ease-in-out text-xs sm:text-small hover:transform hover:translateY(-1px)"
              >
                terms
              </Link>
              <Link
                href="/contact"
                className="text-white/60 hover:text-white transition-all duration-300 ease-in-out text-xs sm:text-small hover:transform hover:translateY(-1px)"
              >
                contact
              </Link>
            </div>
          </div>
          <div className="mt-6 sm:mt-8 text-center text-white/40 text-xs sm:text-small">
            © 2024 tally.{" "}
            <span className="italic-serif">bet on yourself.</span>
          </div>
        </div>
      </footer>
    </div>
  );
}
