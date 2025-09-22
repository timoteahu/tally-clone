import requests
from datetime import date
import os
import dotenv
from supabase import create_client, Client

dotenv.load_dotenv()
# --- CONFIGURATION ---
HABIT_ID = "41bc1897-b364-41f8-bb3d-87162e98df4c"
TEST_DATE = "2024-06-10"  # YYYY-MM-DD, must be a Monday or Thursday
SUPABASE_URL = os.getenv("SUPABASE_URL")
SUPABASE_KEY = os.getenv("SUPABASE_KEY")
PENALTY_CHECK_URL = "http://localhost:8000/api/penalties/check"

# --- STEP 1: Delete the habit log for the test date ---
def delete_habit_log():
    print(f"Deleting habit verification for habit {HABIT_ID} on {TEST_DATE}...")
    supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)
    response = supabase.table("habit_verifications").delete().eq("habit_id", HABIT_ID).eq("verified_at", TEST_DATE).execute()
    print("Habit verification deleted (if it existed). Response:", response)

# --- STEP 2: Trigger the penalty check ---
def trigger_penalty_check():
    print("Triggering penalty check via API...")
    resp = requests.post(PENALTY_CHECK_URL)
    print("API response:", resp.status_code, resp.text)

# --- MAIN ---
if __name__ == "__main__":
    delete_habit_log()
    trigger_penalty_check()
    print("\nCheck your Stripe dashboard and penalties/payments tables for results!") 