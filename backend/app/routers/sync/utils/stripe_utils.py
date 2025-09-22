import stripe
from utils.memory_optimization import cleanup_memory, disable_print

# Disable verbose printing to reduce response latency
print = disable_print()

async def verify_stripe_connect_status(account_id: str) -> bool:
    """
    Verify that a Stripe Connect account is fully enabled and ready to receive payments.
    Uses the same logic as /payments/connect/account-status endpoint.
    """
    try:
        # Retrieve the account from Stripe
        account = stripe.Account.retrieve(account_id)
        
        # Check if account exists
        if not account or not isinstance(account, stripe.Account):
            print(f"❌ Invalid Stripe account: {account_id}")
            return False
            
        # Use the same verification logic as /payments/connect/account-status
        is_valid = (
            account.details_submitted and
            account.charges_enabled and
            account.payouts_enabled
        )
        
        if not is_valid:
            print(f"⚠️ Stripe account {account_id} not fully enabled:")
            print(f"   • Details submitted: {account.details_submitted}")
            print(f"   • Charges enabled: {account.charges_enabled}")
            print(f"   • Payouts enabled: {account.payouts_enabled}")
            
        return is_valid
        
    except stripe.error.StripeError as e:
        print(f"❌ Stripe error verifying account {account_id}: {str(e)}")
        return False
    except Exception as e:
        print(f"❌ Unexpected error verifying Stripe account {account_id}: {str(e)}")
        return False
    finally:
        cleanup_memory(account if 'account' in locals() else None) 