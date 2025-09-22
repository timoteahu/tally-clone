"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { loadStripe } from "@stripe/stripe-js";
import {
  Elements,
  PaymentElement,
  useStripe,
  useElements,
} from "@stripe/react-stripe-js";
import { API_BASE_URL } from "../../utils/api";

// Initialize Stripe with your publishable key
const stripePromise = loadStripe(
  process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY!,
);

const SetupPaymentForm = () => {
  const stripe = useStripe();
  const elements = useElements();
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const router = useRouter();

  const handleSubmit = async (event: React.FormEvent) => {
    event.preventDefault();

    if (!stripe || !elements) {
      return;
    }

    setLoading(true);
    setError(null);

    try {
      const { setupIntent, error: submitError } = await stripe.confirmSetup({
        elements,
        redirect: "if_required",
        confirmParams: {
          return_url: `${window.location.origin}/setup-payment/thank-you`,
        },
      });

      if (submitError) {
        throw new Error(submitError.message);
      }

      if (setupIntent && setupIntent.status === "succeeded") {
        router.push("/setup-payment/thank-you");
      } else {
        setError("Setup is still in progress. Please wait...");
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "An error occurred");
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-6">
      <div className="bg-white/5 border border-white/10 rounded-lg p-4">
        <PaymentElement
          options={{
            layout: {
              type: "tabs",
              defaultCollapsed: false,
            },
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
            <svg
              className="animate-spin -ml-1 mr-3 h-5 w-5 text-black"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                className="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                strokeWidth="4"
              ></circle>
              <path
                className="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              ></path>
            </svg>
            <span>Processing...</span>
          </>
        ) : (
          "Set Up Payment Method"
        )}
      </button>
    </form>
  );
};

export default function SetupPaymentPage() {
  const [clientSecret, setClientSecret] = useState<string>("");
  const [error, setError] = useState<string>("");
  const [loading, setLoading] = useState(true);
  const router = useRouter();

  useEffect(() => {
    const setupPaymentIntent = async () => {
      const authToken =
        typeof window !== "undefined"
          ? localStorage.getItem("authToken")
          : null;
      if (!authToken) {
        router.push("/auth");
        return;
      }
      try {
        // Call the new setup intent endpoint
        const setupResponse = await fetch(
          `${API_BASE_URL}/payments/create-setup-intent`,
          {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${authToken}`,
            },
          },
        );

        if (!setupResponse.ok) {
          throw new Error("Failed to create setup intent");
        }

        const data = await setupResponse.json();
        setClientSecret(data.clientSecret);
      } catch (err) {
        setError(err instanceof Error ? err.message : "An error occurred");
      } finally {
        setLoading(false);
      }
    };

    setupPaymentIntent();
  }, [router]);

  if (loading) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-[#161C29] from-10% via-[#0B0F16] via-45% to-[#01050B] to-70% flex items-center justify-center">
        <div className="text-center">
          <div className="relative w-16 h-16 mx-auto mb-6">
            <div className="absolute top-0 left-0 w-full h-full border-4 border-white/20 rounded-full animate-pulse"></div>
            <div className="absolute top-0 left-0 w-full h-full border-4 border-white rounded-full animate-spin border-t-transparent"></div>
          </div>
          <p className="text-white/80 text-lg" style={{ fontFamily: 'var(--font-eb-garamond), serif' }}>
            setting up payment...
          </p>
        </div>
      </div>
    );
  }

  if (error) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-[#161C29] from-10% via-[#0B0F16] via-45% to-[#01050B] to-70% flex items-center justify-center">
        <div className="bg-white/5 backdrop-blur-sm border border-white/10 rounded-3xl p-8 max-w-md w-full">
          <div className="w-12 h-12 bg-red-500/20 rounded-full flex items-center justify-center mx-auto mb-4">
            <svg className="w-6 h-6 text-red-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M6 18L18 6M6 6l12 12" />
            </svg>
          </div>
          <h2 className="text-2xl font-normal text-white mb-4 text-center" style={{ fontFamily: 'var(--font-eb-garamond), serif' }}>
            error
          </h2>
          <p className="text-white/80 mb-6 text-center leading-relaxed" style={{ fontFamily: 'var(--font-eb-garamond), serif' }}>
            {error}
          </p>
          <button
            onClick={() => window.location.reload()}
            className="w-full px-6 py-3 border border-white/20 hover:border-white/40 rounded-2xl text-white font-normal transition-all duration-300 hover:bg-white/5"
            style={{ fontFamily: 'var(--font-eb-garamond), serif' }}
          >
            try again
          </button>
        </div>
      </div>
    );
  }

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
          'ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
        spacingUnit: "4px",
        borderRadius: "8px",
      },
    },
  };

  return (
    <div className="min-h-screen bg-black">
      <div className="max-w-4xl mx-auto px-4 py-16">
        <div className="bg-black border border-white/10 rounded-lg p-8">
          <h1 className="text-3xl font-bold text-white mb-8">
            Set Up Payment Method
          </h1>
          <p className="text-white/80 mb-8">
            Add your payment method to get started with Tally. Your card will
            only be charged when you miss a check-in.
          </p>
          <Elements stripe={stripePromise} options={options}>
            <SetupPaymentForm />
          </Elements>
        </div>
      </div>
    </div>
  );
}
