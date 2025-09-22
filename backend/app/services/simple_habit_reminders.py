# HABIT REMINDERS FEATURE - COMMENTED OUT UNTIL TWILIO PHONE NUMBER CONFIGURED
# 
# This file contains the simple habit reminder service with hardcoded templates.
# To enable:
# 1. Add TWILIO_PHONE_NUMBER=+1yourphone to .env file
# 2. Uncomment this entire file
# 3. Re-enable calls in penalty_handler.py and scheduler.py
# 4. Re-enable router in main.py

# import os
# import logging
# import random
# from typing import Dict
# from dotenv import load_dotenv
# from supabase import Client
# from twilio.rest import Client as TwilioClient
# from twilio.base.exceptions import TwilioException

# # Load environment variables
# load_dotenv()

# logger = logging.getLogger(__name__)

# class SimpleHabitReminderService:
#     """Simplified habit reminder service with easily customizable hardcoded messages"""
    
#     def __init__(self):
#         self.twilio_client = None
#         self._initialize_twilio()
        
#         # 🎯 CUSTOMIZE YOUR MESSAGES HERE! 🎯
#         # Mix of professional and out-of-pocket templates for variety
#         self.message_templates = {
#             "gym": {
#                 "daily_miss": [
#                     "🏋️‍♂️ Heads‑up! {partner_name} ghosted the gym today. You just scored ${penalty_amount}. Maybe send them a hype text? 💪",
#                     "No reps, no sweats—just debit. {partner_name} skipped their workout, so ${penalty_amount} landed in your court. Cha‑ching!",
#                     "Gym pass declined! 😅 {partner_name} paid ${penalty_amount} to you for missing today's lift. Flex on 'em (kindly).",
#                     "FYI: {partner_name} hit 'snooze' on the gym. You get ${penalty_amount}. Maybe challenge them to leg day tomorrow?",
#                     "🚨 Workout whiff! {partner_name} owes you ${penalty_amount}. Friendly reminder: gains wait for no one.",
#                     "Push‑ups? Nah. Payouts? Yeah. {partner_name} missed the session, so ${penalty_amount} is yours.",
#                     "Gym absentee alert: {partner_name} ghosted leg day harder than their ex 😂 — your balance just leveled‑up ${penalty_amount}.",
#                     "{partner_name} skipped the iron paradise, but your wallet's doing curls with ${penalty_amount}. 💸",
#                     "Legends lift; {partner_name} drifted. Cash in: ${penalty_amount}. Send them a mirror selfie of your grin."
#                 ],
#                 "weekly_miss": [
#                     "📊 Weekly check‑in: {partner_name} skipped {missed_days} gym days. Total sent: ${penalty_amount}. Consider a joint workout plan?",
#                     "{missed_days} empty squat racks later… ${penalty_amount} just hit your balance. Time to roast {partner_name} (politely).",
#                     "Gains report: MIA {missed_days}/7 days. You pocket ${penalty_amount}. Maybe share a workout meme for motivation.",
#                     "Your wallet's lifting heavier than {partner_name}—${penalty_amount} earned from {missed_days} misses this week.",
#                     "Spotter alert: {partner_name} dropped the ball {missed_days} times. You're up ${penalty_amount}.",
#                     "💰 Profit from procrastination: {partner_name} ducked the gym on {missed_days} days. Total payout ${penalty_amount}.",
#                     "{partner_name} racked up {missed_days} no‑shows— that's ${penalty_amount} straight to your protein‑shake fund.",
#                     "Flex report: 0 reps, {missed_days} excuses. Your gain: ${penalty_amount}."
#                 ]
#             },
#             "studying": {
#                 "daily_miss": [
#                     "📚🚫 Books were benched! {partner_name} skipped study time and sent you ${penalty_amount}. Maybe swap them a flashcard?",
#                     "Study sesh? Cancelled. Your balance grew by ${penalty_amount}. Give {partner_name} a pep talk!",
#                     "Knowledge nap detected. {partner_name} paid ${penalty_amount} for today's miss.",
#                     "Heads‑up: {partner_name} chose Netflix > notes. You got ${penalty_amount}.",
#                     "Another page left un‑turned. {partner_name} owes you ${penalty_amount}.",
#                     "No cram, just cash: ${penalty_amount} from {partner_name} for skipping study.",
#                     "{partner_name}'s textbooks are officially paperweights today. Cash prize for you: ${penalty_amount}.",
#                     "Study sesh cancelled like a flop Netflix pilot. Pocket that ${penalty_amount}.",
#                     "Brains on airplane mode—good thing your balance is at 100% (${penalty_amount})."
#                 ],
#                 "weekly_miss": [
#                     "{partner_name} missed studying {missed_days} times. Your coffers +${penalty_amount}. Maybe co‑work next week?",
#                     "Report card 💸: {missed_days} zeros in the planner → ${penalty_amount} for you.",
#                     "{missed_days}/7 study days skipped. You earned ${penalty_amount}.",
#                     "Study slump alert: {partner_name} owed you ${penalty_amount} after {missed_days} misses.",
#                     "Textbooks lonely for {missed_days} days. Wallet not lonely: +${penalty_amount}.",
#                     "Profit from procrastination Part II: {partner_name} ➔ you ${penalty_amount} (missed {missed_days} studies).",
#                     "Report: {missed_days} study flops. You level‑up ${penalty_amount} coins.",
#                     "{partner_name} left knowledge on 'read' {missed_days} times. That's ${penalty_amount} to your coffee fund."
#                 ]
#             },
#             "alarm": {
#                 "daily_miss": [
#                     "⏰ Snooze‑fest! {partner_name} overslept. You just earned ${penalty_amount}. Maybe send a loud gif?",
#                     "{partner_name} slept in; your wallet is up ${penalty_amount}. Early riser superiority confirmed.",
#                     "Morning fail => money hail. {partner_name} paid you ${penalty_amount}.",
#                     "Alarm: 0, {partner_name}: 0, You: +${penalty_amount}.",
#                     "Rise & fine! {partner_name} owes you ${penalty_amount}.",
#                     "Sleepyhead tax collected: ${penalty_amount} from {partner_name}.",
#                     "{partner_name} slept like it's a paid internship—luckily it kinda is… for you. Collect ${penalty_amount}.",
#                     "Snooze button 1, {partner_name} 0, Your wallet +${penalty_amount}.",
#                     "Morning L delivered. Tracking number: ${penalty_amount}."
#                 ],
#                 "weekly_miss": [
#                     "{partner_name} snoozed {missed_days} mornings. Total payout: ${penalty_amount}.",
#                     "Weekly wake count low. Your gain: ${penalty_amount}.",
#                     "Alarm losses {missed_days}× ➔ ${penalty_amount} to you.",
#                     "Snooze summary: {missed_days} misses → ${penalty_amount}.",
#                     "⏰→💸 {partner_name} missed {missed_days} alarms; you bank ${penalty_amount}.",
#                     "Late‑o‑meter: {missed_days}. Compensation: ${penalty_amount}.",
#                     "{partner_name} whiffed the alarm {missed_days} times. Pocket bills: ${penalty_amount}.",
#                     "Sleep stats: {missed_days} wake‑ups MIA. You grabbed ${penalty_amount} while they grabbed Z's."
#                 ]
#             },
#             "cooking": {
#                 "daily_miss": [
#                     "🍕➡️💵 Takeout night! {partner_name} skipped cooking and paid you ${penalty_amount}. Maybe share a recipe?",
#                     "Chef off‑duty. You got ${penalty_amount} from {partner_name}.",
#                     "Home‑meal fail = wallet win. ${penalty_amount} received.",
#                     "{partner_name} ordered in; you cash out ${penalty_amount}.",
#                     "No apron, no problem—for you. ${penalty_amount} credited.",
#                     "Kitchen lights off, funds on. ${penalty_amount} from {partner_name}.",
#                     "Microwave beep > chef's kiss. {partner_name} ordered out; you cash in ${penalty_amount}.",
#                     "Sauce was lost, but money found: +${penalty_amount}.",
#                     "Stove got ghosted; your Venmo got toasted with ${penalty_amount}."
#                 ],
#                 "weekly_miss": [
#                     "{partner_name} dodged the stove {missed_days} times. Your earnings: ${penalty_amount}.",
#                     "Meal prep? More like meal‑skip {missed_days}×. ${penalty_amount} delivered.",
#                     "Weekly chef score: {missed_days} misses ➔ ${penalty_amount}.",
#                     "{partner_name} sent ${penalty_amount} after {missed_days} cookless days.",
#                     "Cook‑out (literally): {missed_days} takeouts = ${penalty_amount} for you.",
#                     "Zero‑cook nights: {missed_days}. Wallet +${penalty_amount}.",
#                     "Kitchen strike: {missed_days} nights off. Your tip‑jar: ${penalty_amount}.",
#                     "Chef's hat? More like chef's nap. {missed_days} misses; you earn ${penalty_amount}."
#                 ]
#             },
#             "yoga": {
#                 "daily_miss": [
#                     "🧘‍♂️ Zen‑skip detected. {partner_name} missed yoga and sent you ${penalty_amount}.",
#                     "Chakras misaligned; wallet aligned. ${penalty_amount} incoming.",
#                     "No namaste today. {partner_name} paid ${penalty_amount}.",
#                     "Mat stayed rolled. You gained ${penalty_amount}.",
#                     "Pose? Nope. Payment ${penalty_amount}.",
#                     "Flexibility loss → financial gain. ${penalty_amount} received.",
#                     "{partner_name} skipped the zen and sent the yen—${penalty_amount} to you.",
#                     "No downward dog, just downward debt: +${penalty_amount}.",
#                     "Pose count: zero. Bank count: +${penalty_amount}."
#                 ],
#                 "weekly_miss": [
#                     "{partner_name} skipped yoga {missed_days} days. You earned ${penalty_amount}.",
#                     "Mind‑body? Maybe next week. Funds: ${penalty_amount}.",
#                     "Zen report: {missed_days} misses ➔ ${penalty_amount} to you.",
#                     "Weekly yoga gap: {missed_days}. Compensation ${penalty_amount}.",
#                     "Less ohm, more $$: ${penalty_amount} for {missed_days} misses.",
#                     "Mat‑free days: {missed_days}. Wallet +${penalty_amount}.",
#                     "{missed_days} mats collecting dust. Your dust‑buster: ${penalty_amount}.",
#                     "Om my god—{missed_days} misses. Your mantra: convert to ${penalty_amount}."
#                 ]
#             },
#             "outdoors": {
#                 "daily_miss": [
#                     "🌞>🏠? Not today. {partner_name} stayed in and paid you ${penalty_amount}.",
#                     "No fresh air, fresh cash: ${penalty_amount} received.",
#                     "Couch potato tax: ${penalty_amount} from {partner_name}.",
#                     "Indoor day logged. You earn ${penalty_amount}.",
#                     "Grass un‑touched. Wallet touched: +${penalty_amount}.",
#                     "Nature ghosted → balance boosted (${penalty_amount}).",
#                     "{partner_name} avoided fresh air like it's DLC. Loot drop: ${penalty_amount}.",
#                     "They chose indoor mode; you unlocked ${penalty_amount}.",
#                     "Couch XP +100, bank XP +${penalty_amount}."
#                 ],
#                 "weekly_miss": [
#                     "{partner_name} skipped the outdoors {missed_days} days. ${penalty_amount} collected.",
#                     "Vitamin D deficiency? Your pocket's healthy: ${penalty_amount}.",
#                     "Nature log: {missed_days} misses ➔ ${penalty_amount}.",
#                     "Outside index low. Funds high: ${penalty_amount}.",
#                     "Screen time 1, green time 0. You +${penalty_amount}.",
#                     "{missed_days} inside days. Wallet gains ${penalty_amount}.",
#                     "Nature nil: {missed_days} misses. Cash yes: ${penalty_amount}.",
#                     "{partner_name}'s sunlight budget reallocated to you: ${penalty_amount}."
#                 ]
#             },
#             # Add custom habit types as needed
#             "custom": {
#                 "daily_miss": [
#                     "{partner_name} skipped {habit_type}. Your reward: ${penalty_amount}.",
#                     "Habit alert: {habit_type} missed. ${penalty_amount} sent over.",
#                     "Custom miss detected. You gained ${penalty_amount}.",
#                     "{partner_name} bailed on {habit_type}. Wallet +${penalty_amount}.",
#                     "No {habit_type} today. Funds ${penalty_amount}.",
#                     "Penalty for missing {habit_type}: ${penalty_amount} to you.",
#                     "{partner_name} bailed on {habit_type}. You collect ${penalty_amount}; they collect disappointment.",
#                     "Habit {habit_type}? More like habit *not*. ${penalty_amount} your way.",
#                     "{partner_name} forgot {habit_type}. Wallet says thanks for the ${penalty_amount} boost."
#                 ],
#                 "weekly_miss": [
#                     "{partner_name} missed {habit_type} {missed_days} times. You earned ${penalty_amount}.",
#                     "{missed_days} skips on {habit_type}. Payout ${penalty_amount}.",
#                     "Custom gap report: {missed_days} misses → ${penalty_amount}.",
#                     "{habit_type} low, funds high: ${penalty_amount}.",
#                     "{partner_name} bailed {missed_days}×; you bank ${penalty_amount}.",
#                     "Weekly miss tally: {missed_days}. Wallet +${penalty_amount}.",
#                     "Custom habit MIA {missed_days} times. Pay‑day: ${penalty_amount}.",
#                     "Less {habit_type}, more bank hype: +${penalty_amount}."
#                 ]
#             }
#         }
    
#     def _initialize_twilio(self):
#         """Initialize Twilio client"""
#         try:
#             account_sid = os.getenv("TWILIO_ACCOUNT_SID")
#             auth_token = os.getenv("TWILIO_AUTH_TOKEN")
            
#             if account_sid and auth_token:
#                 self.twilio_client = TwilioClient(account_sid, auth_token)
#                 logger.info("Twilio client initialized successfully")
#             else:
#                 logger.warning("Twilio credentials not found in environment variables")
#         except Exception as e:
#             logger.error(f"Failed to initialize Twilio client: {e}")
    
#     async def send_habit_reminder(
#         self, 
#         habit_id: str, 
#         message_type: str, 
#         supabase_client: Client,
#         missed_days: int = 1
#     ) -> Dict[str, any]:
#         """Send a habit reminder message to the accountability partner"""
#         try:
#             # Get habit details
#             habit_result = supabase_client.table("habits").select("*").eq("id", habit_id).single().execute()
#             if not habit_result.data:
#                 raise Exception(f"Habit {habit_id} not found")
            
#             habit = habit_result.data
            
#             # Check if habit has a recipient (accountability partner)
#             if not habit.get("recipient_id"):
#                 logger.info(f"Habit {habit_id} has no accountability partner - skipping reminder")
#                 return {"status": "skipped", "reason": "no_accountability_partner"}
            
#             # Get user and recipient details
#             user_result = supabase_client.table("users").select("*").eq("id", habit["user_id"]).single().execute()
#             recipient_result = supabase_client.table("users").select("*").eq("id", habit["recipient_id"]).single().execute()
            
#             if not user_result.data or not recipient_result.data:
#                 raise Exception("User or recipient not found")
            
#             user = user_result.data
#             recipient = recipient_result.data
            
#             # Get message template
#             template_text = self._get_message_template(habit["habit_type"], message_type)
            
#             # Format the message with actual values
#             formatted_message = self._format_message(
#                 template_text=template_text,
#                 user_name=user["name"],
#                 partner_name=user["name"],  # The person who missed the habit
#                 habit_name=habit["name"],
#                 habit_type=habit["habit_type"],
#                 penalty_amount=float(habit["penalty_amount"]),
#                 missed_days=missed_days
#             )
            
#             #
#             message_status = await self._send_sms(
#                 recipient_phone=recipient["phone_number"],
#                 message_text=formatted_message
#             )
            
#             # Return appropriate response based on message status
#             if message_status["status"] == "sent":
#                 return {
#                     "status": message_status["status"],
#                     "message": formatted_message,
#                     "recipient_phone": recipient["phone_number"],
#                     "template_used": template_text
#                 }
#             else:
#                 return {
#                     "status": "failed",
#                     "error": message_status.get("error", "Unknown error"),
#                     "recipient_phone": recipient["phone_number"]
#                 }
            
#         except Exception as e:
#             logger.error(f"Failed to send habit reminder for habit {habit_id}: {e}")
#             return {"status": "failed", "error": str(e)}
    
#     def _get_message_template(self, habit_type: str, message_type: str) -> str:
#         """Get random message template for habit type and message type"""
        
#         # Check if we have a specific template for this habit type
#         if habit_type in self.message_templates:
#             templates = self.message_templates[habit_type]
#             if message_type in templates and templates[message_type]:
#                 return random.choice(templates[message_type])
        
#         # Fall back to custom template
#         if message_type in self.message_templates["custom"] and self.message_templates["custom"][message_type]:
#             return random.choice(self.message_templates["custom"][message_type])
        
#         # Ultimate fallback
#         return "{partner_name} missed their {habit_type} habit. Here's your ${penalty_amount}!"
    
#     def _format_message(
#         self,
#         template_text: str,
#         user_name: str,
#         partner_name: str,
#         habit_name: str,
#         habit_type: str,
#         penalty_amount: float,
#         missed_days: int
#     ) -> str:
#         """Format message template with actual values"""
        
#         message = template_text.format(
#             partner_name=partner_name,
#             user_name=user_name,
#             habit_name=habit_name,
#             habit_type=habit_type,
#             penalty_amount=f"{penalty_amount:.2f}",
#             missed_days=missed_days
#         )
        
#         return message
    
#     async def _send_sms(self, recipient_phone: str, message_text: str) -> Dict[str, any]:
#         """Send SMS message via Twilio using the same config as auth verification"""
        
#         if not self.twilio_client:
#             logger.error("Twilio client not initialized")
#             return {"status": "failed", "error": "Twilio client not available"}
        
#         try:
#             # Format phone number (same as auth system)
#             if not recipient_phone.startswith("+"):
#                 recipient_phone = f"+1{recipient_phone.replace('-', '').replace('(', '').replace(')', '').replace(' ', '')}"
            
#             # Try to get Twilio phone number first
#             twilio_phone = os.getenv("TWILIO_PHONE_NUMBER")
            
#             if twilio_phone:
#                 # Standard SMS approach (like your verification would use if it sent custom messages)
#                 message = self.twilio_client.messages.create(
#                     body=message_text,
#                     from_=twilio_phone,
#                     to=recipient_phone
#                 )
#                 logger.info(f"SMS sent successfully to {recipient_phone}, SID: {message.sid}")
#                 return {"status": "sent", "message_sid": message.sid}
#             else:
#                 # Fallback: Use messaging service if you have one configured
#                 messaging_service_sid = os.getenv("TWILIO_MESSAGING_SERVICE_SID")
#                 if messaging_service_sid:
#                     message = self.twilio_client.messages.create(
#                         body=message_text,
#                         messaging_service_sid=messaging_service_sid,
#                         to=recipient_phone
#                     )
#                     logger.info(f"SMS sent via messaging service to {recipient_phone}, SID: {message.sid}")
#                     return {"status": "sent", "message_sid": message.sid}
#                 else:
#                     logger.error("Neither TWILIO_PHONE_NUMBER nor TWILIO_MESSAGING_SERVICE_SID configured")
#                     return {"status": "failed", "error": "No Twilio sending method configured"}
            
#         except TwilioException as e:
#             logger.error(f"Twilio error sending SMS to {recipient_phone}: {e}")
#             return {"status": "failed", "error": str(e)}
#         except Exception as e:
#             logger.error(f"Unexpected error sending SMS to {recipient_phone}: {e}")
#             return {"status": "failed", "error": str(e)}

# # Create global instance for use by other modules
# # simple_habit_reminder_service = SimpleHabitReminderService() 