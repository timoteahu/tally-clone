import stripe
import os
from dotenv import load_dotenv

# Load environment variables from backend root directory
current_dir = os.path.dirname(os.path.abspath(__file__))
app_dir = os.path.dirname(current_dir)
backend_dir = os.path.dirname(app_dir)
env_path = os.path.join(backend_dir, '.env')
load_dotenv(env_path)

def get_stripe_client():
    """
    Initializes and returns a Stripe client instance.
    
    Returns:
        stripe: A configured Stripe client instance
        
    Raises:
        ValueError: If required environment variables are not set
    """
    stripe_secret_key = os.getenv("STRIPE_SECRET_KEY")
    if not stripe_secret_key:
        raise ValueError(
            "Stripe secret key not found. Please set STRIPE_SECRET_KEY environment variable."
        )
    
    stripe.api_key = stripe_secret_key
    return stripe

def get_stripe_webhook_secret():
    """
    Retrieves the Stripe webhook secret from environment variables.
    
    Returns:
        str: The Stripe webhook secret
        
    Raises:
        ValueError: If the webhook secret is not set
    """
    webhook_secret = os.getenv("STRIPE_WEBHOOK_SECRET")
    if not webhook_secret:
        raise ValueError(
            "Stripe webhook secret not found. Please set STRIPE_WEBHOOK_SECRET environment variable."
        )
    return webhook_secret

# Initialize Stripe client and webhook secret
stripe_client = get_stripe_client()
STRIPE_WEBHOOK_SECRET = get_stripe_webhook_secret()

def create_payment_intent(amount: int, currency: str = "usd", metadata: dict = None, payment_method: str = None, customer_id: str = None, confirm: bool = False):
    """
    Create a Stripe PaymentIntent for a penalty payment
    """
    try:
        payment_intent_params = {
            "amount": amount,
            "currency": currency,
            "metadata": metadata or {},
            "confirm": confirm
        }
        
        if payment_method:
            if not customer_id:
                raise ValueError("customer_id is required when payment_method is provided")
            payment_intent_params["payment_method"] = payment_method
            payment_intent_params["customer"] = customer_id
            payment_intent_params["off_session"] = True
        else:
            payment_intent_params["automatic_payment_methods"] = {"enabled": True}
            
        payment_intent = stripe.PaymentIntent.create(**payment_intent_params)
        return payment_intent
    except stripe.error.StripeError as e:
        raise Exception(f"Stripe error: {str(e)}")

def create_customer(email: str, name: str = None):
    """
    Create a Stripe customer
    """
    try:
        customer = stripe.Customer.create(
            email=email,
            name=name
        )
        return customer
    except stripe.error.StripeError as e:
        raise Exception(f"Stripe error: {str(e)}")

def attach_payment_method(customer_id: str, payment_method_id: str):
    """
    Attach a payment method to a customer
    """
    try:
        payment_method = stripe.PaymentMethod.attach(
            payment_method_id,
            customer=customer_id
        )
        return payment_method
    except stripe.error.StripeError as e:
        raise Exception(f"Stripe error: {str(e)}") 