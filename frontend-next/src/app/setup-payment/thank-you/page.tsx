'use client';
import { useEffect } from 'react';
import { useRouter } from 'next/navigation';

export default function ThankYouPage() {
  const router = useRouter();
  useEffect(() => {
    const timer = setTimeout(() => {
      router.push('/');
    }, 3000);
    return () => clearTimeout(timer);
  }, [router]);

  return (
    <div className="min-h-screen bg-black flex items-center justify-center">
      <div className="bg-black border border-white/10 rounded-lg p-8 max-w-md w-full text-center">
        <h1 className="text-3xl font-bold text-white mb-4">Thank You!</h1>
        <p className="text-white/80 mb-2">Your payment method has been saved.</p>
        <p className="text-white/60">You will be redirected to the home page shortly.</p>
      </div>
    </div>
  );
} 