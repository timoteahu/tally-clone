"use client";

import { useState } from "react";
import { loadStripe } from "@stripe/stripe-js";
import {
  Elements,
  PaymentElement,
  useStripe,
  useElements,
} from "@stripe/react-stripe-js";

// Initialize Stripe with your publishable key
const stripePromise = loadStripe(
  process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY!,
);

function SetupForm({ clientSecret }: { clientSecret: string }) {
  const stripe = useStripe();
  const elements = useElements();
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [success, setSuccess] = useState(false);

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();
    if (!stripe || !elements) return;
    setLoading(true);
    setError(null);

    const { setupIntent, error: submitError } = await stripe.confirmSetup({
      elements,
      confirmParams: {
        return_url: `${window.location.origin}/payment/success`,
      },
      redirect: "if_required",
    });

    if (submitError) {
      setError(submitError.message ?? "An error occurred");
    } else if (setupIntent && setupIntent.status === "succeeded") {
      setSuccess(true);
    }
    setLoading(false);
  };

  if (success) {
    return (
      <div className="bg-green-500/10 border border-green-500/20 rounded-2xl p-6 text-center">
        <div className="w-12 h-12 bg-green-500/20 rounded-full flex items-center justify-center mx-auto mb-4">
          <svg className="w-6 h-6 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        </div>
        <p className="text-green-400 text-lg" style={{ fontFamily: 'var(--font-eb-garamond), serif' }}>
          payment method saved!
        </p>
      </div>
    );
  }

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <div className="bg-white/5 border border-white/10 rounded-2xl p-6">
        <PaymentElement
          options={{ 
            layout: { type: "tabs", defaultCollapsed: false },
            fields: {
              billingDetails: {
                name: 'auto',
                email: 'auto',
                phone: 'auto',
                address: {
                  country: 'auto',
                  line1: 'auto',
                  line2: 'auto',
                  city: 'auto',
                  state: 'auto',
                  postalCode: 'auto'
                }
              }
            }
          }}
        />
      </div>
      {error && (
        <div className="bg-red-500/10 border border-red-500/20 rounded-2xl p-4">
          <p className="text-red-400 text-sm" style={{ fontFamily: 'var(--font-eb-garamond), serif' }}>{error}</p>
        </div>
      )}
      <button
        type="submit"
        disabled={!stripe || loading}
        className="w-full bg-white text-black py-4 px-6 rounded-2xl font-normal
                 hover:bg-white/90 focus:outline-none focus:ring-2 focus:ring-offset-2 
                 focus:ring-white/20 disabled:opacity-50 disabled:cursor-not-allowed transition-all
                 flex items-center justify-center space-x-3"
        style={{ fontFamily: 'var(--font-eb-garamond), serif' }}
      >
        {loading ? (
          <>
            <div className="animate-spin rounded-full h-5 w-5 border-b-2 border-black"></div>
            <span>saving...</span>
          </>
        ) : (
          <>
            <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={1.5} d="M5 13l4 4L19 7" />
            </svg>
            <span>save payment method</span>
          </>
        )}
      </button>
    </form>
  );
}

export function PaymentForm({ clientSecret }: { clientSecret: string }) {
  const options = {
    clientSecret,
    appearance: {
      theme: "night" as const,
      variables: {
        colorPrimary: "#ffffff",
        colorBackground: "#000000",
        colorText: "#ffffff",
        colorDanger: "#EF4444",
        fontFamily:
          'var(--font-eb-garamond), serif',
        spacingUnit: "4px",
        borderRadius: "12px",
      },
    },
  };

  return (
    <Elements stripe={stripePromise} options={options}>
      <SetupForm clientSecret={clientSecret} />
    </Elements>
  );
}
