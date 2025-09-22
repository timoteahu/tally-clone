import os
import httpx
from datetime import datetime, timedelta, timezone
from typing import List, Dict, Optional, Tuple
from uuid import UUID
import logging

logger = logging.getLogger(__name__)

class RiotAPIService:
    def __init__(self):
        self.api_key = os.getenv("RIOT_API_KEY")
        if not self.api_key:
            raise ValueError("RIOT_API_KEY environment variable not set")
        
        # Base URLs for different regions
        self.region_urls = {
            "americas": "https://americas.api.riotgames.com",
            "europe": "https://europe.api.riotgames.com", 
            "asia": "https://asia.api.riotgames.com",
            "sea": "https://sea.api.riotgames.com"
        }
        
        # Platform routing values for account lookup
        self.platform_urls = {
            "na1": "https://na1.api.riotgames.com",
            "euw1": "https://euw1.api.riotgames.com",
            "eun1": "https://eun1.api.riotgames.com",
            "kr": "https://kr.api.riotgames.com",
            "jp1": "https://jp1.api.riotgames.com",
            "br1": "https://br1.api.riotgames.com",
            "la1": "https://la1.api.riotgames.com",
            "la2": "https://la2.api.riotgames.com",
            "oc1": "https://oc1.api.riotgames.com",
            "tr1": "https://tr1.api.riotgames.com",
            "ru": "https://ru.api.riotgames.com"
        }
        
        self.headers = {
            "X-Riot-Token": self.api_key
        }
    
    async def get_puuid_by_riot_id(self, riot_id: str, tagline: str, region: str) -> Optional[str]:
        """Get PUUID for a Riot ID and tagline."""
        try:
            url = f"{self.region_urls[region]}/riot/account/v1/accounts/by-riot-id/{riot_id}/{tagline}"
            
            async with httpx.AsyncClient() as client:
                response = await client.get(url, headers=self.headers)
                
                if response.status_code == 200:
                    data = response.json()
                    return data.get("puuid")
                elif response.status_code == 404:
                    logger.warning(f"Riot account not found: {riot_id}#{tagline}")
                    return None
                else:
                    logger.error(f"Error fetching PUUID: {response.status_code} - {response.text}")
                    return None
                    
        except Exception as e:
            logger.error(f"Exception fetching PUUID: {str(e)}")
            return None
    
    async def get_lol_matches_for_date(self, puuid: str, region: str, target_date: datetime) -> List[Dict]:
        """Get all League of Legends matches that started on the target date."""
        matches = []
        
        try:
            # Log the input parameters
            logger.info(f"=== RIOT API DEBUG ===")
            logger.info(f"Getting LoL matches for PUUID: {puuid}")
            logger.info(f"Region: {region}")
            logger.info(f"Target date: {target_date}")
            logger.info(f"Target date timezone: {target_date.tzinfo}")
            
            # If target_date is timezone-aware, use it; otherwise assume UTC
            if target_date.tzinfo is None:
                logger.warning("Target date has no timezone info, assuming UTC")
                target_date = target_date.replace(tzinfo=timezone.utc)
            
            # Set time window for the target date (preserving timezone)
            # Add a buffer to catch matches that might span midnight
            start_of_day = target_date.replace(hour=0, minute=0, second=0, microsecond=0)
            end_of_day = start_of_day + timedelta(days=1)
            
            # IMPORTANT: Riot API seems to use game creation time, not start time
            # Also add a small buffer to catch games that started just before/after midnight
            logger.info(f"Original date range: {start_of_day} to {end_of_day}")
            
            # Expand the window slightly to catch edge cases
            start_of_day = start_of_day - timedelta(hours=1)  # 1 hour before midnight
            end_of_day = end_of_day + timedelta(hours=6)  # 6 hours after midnight (to catch late night games)
            
            logger.info(f"Expanded date range for edge cases: {start_of_day} to {end_of_day}")
            
            # Convert to timestamps (milliseconds) - this will respect the timezone
            start_time = int(start_of_day.timestamp() * 1000)
            end_time = int(end_of_day.timestamp() * 1000)
            
            logger.info(f"Date range: {start_of_day} to {end_of_day}")
            logger.info(f"Timestamp range: {start_time} to {end_time}")
            
            # Ensure we have a valid region key
            if region not in self.region_urls:
                logger.error(f"Invalid region: {region}. Valid regions: {list(self.region_urls.keys())}")
                return matches
            
            # Get match IDs - fetch without date filter due to Riot API issues
            match_ids_url = f"{self.region_urls[region]}/lol/match/v5/matches/by-puuid/{puuid}/ids"
            
            # Fetch last 100 matches without date filter (Riot API date filtering seems broken)
            params = {
                "count": 100  # Max allowed
            }
            
            logger.info(f"Fetching LoL matches from URL: {match_ids_url}")
            logger.info(f"Target date range: {start_of_day} to {end_of_day}")
            logger.info(f"Fetching last 100 matches and filtering locally due to Riot API date parameter issues")
            
            async with httpx.AsyncClient() as client:
                response = await client.get(match_ids_url, headers=self.headers, params=params)
                
                logger.info(f"Riot API response status: {response.status_code}")
                
                # Handle specific error codes
                if response.status_code == 401:
                    logger.error("401 Unauthorized - Invalid API key")
                    return matches
                elif response.status_code == 403:
                    logger.error("403 Forbidden - API key may not have access to this endpoint")
                    return matches
                elif response.status_code == 429:
                    retry_after = response.headers.get('Retry-After', 'Unknown')
                    logger.error(f"429 Rate Limited - Retry after {retry_after} seconds")
                    return matches
                elif response.status_code == 404:
                    logger.error("404 Not Found - PUUID may be invalid")
                    return matches
                elif response.status_code != 200:
                    logger.error(f"Error fetching LoL match IDs: {response.status_code} - {response.text}")
                    return matches
                
                all_match_ids = response.json()
                logger.info(f"Riot API returned {len(all_match_ids)} total match IDs")
                
                # Now we need to filter matches by date locally
                match_ids_in_range = []
                
                # Check each match to see if it falls within our date range
                for match_id in all_match_ids[:20]:  # Check first 20 matches to avoid too many API calls
                    match_url = f"{self.region_urls[region]}/lol/match/v5/matches/{match_id}"
                    match_response = await client.get(match_url, headers=self.headers)
                    
                    if match_response.status_code == 200:
                        match_data = match_response.json()
                        game_creation = match_data.get("info", {}).get("gameCreation", 0) / 1000
                        game_start = match_data.get("info", {}).get("gameStartTimestamp", 0) / 1000
                        
                        # Use game start time if available, otherwise use creation time
                        game_time = game_start if game_start > 0 else game_creation
                        
                        # Check if this match falls within our date range
                        if start_time / 1000 <= game_time <= end_time / 1000:
                            match_ids_in_range.append(match_id)
                            logger.info(f"Match {match_id} is within date range: {datetime.fromtimestamp(game_time, tz=timezone.utc)}")
                        else:
                            logger.debug(f"Match {match_id} is outside date range: {datetime.fromtimestamp(game_time, tz=timezone.utc)}")
                        
                        # If we've gone past our date range, we can stop checking
                        if game_time < start_time / 1000:
                            logger.info("Reached matches before our date range, stopping search")
                            break
                
                logger.info(f"Found {len(match_ids_in_range)} matches within date range out of {len(all_match_ids[:20])} checked")
                
                # Now fetch full details for matches in our date range
                for match_id in match_ids_in_range:
                    match_url = f"{self.region_urls[region]}/lol/match/v5/matches/{match_id}"
                    match_response = await client.get(match_url, headers=self.headers)
                    
                    if match_response.status_code == 200:
                        match_data = match_response.json()
                        matches.append(match_data)
                    else:
                        logger.warning(f"Failed to fetch match {match_id}: {match_response.status_code}")
                
                logger.info(f"Found {len(matches)} LoL matches for {target_date.date()}")
                
        except Exception as e:
            logger.error(f"Exception fetching LoL matches: {str(e)}")
            
        return matches
    
    async def get_valorant_matches_for_date(self, puuid: str, region: str, target_date: datetime) -> List[Dict]:
        """Get all Valorant matches that started on the target date.
        
        NOTE: Valorant API requires a Production API key from Riot.
        Development keys only work for League of Legends.
        """
        matches = []
        
        try:
            # For Valorant, we need to use the platform-specific endpoint
            # Map region to platform
            platform_mapping = {
                "americas": "na",
                "europe": "eu", 
                "asia": "ap",
                "sea": "ap"
            }
            platform = platform_mapping.get(region, "na")
            
            # Get match history
            match_history_url = f"https://{platform}.api.riotgames.com/val/match/v1/matchlists/by-puuid/{puuid}"
            
            async with httpx.AsyncClient() as client:
                response = await client.get(match_history_url, headers=self.headers)
                
                if response.status_code != 200:
                    logger.error(f"Error fetching Valorant match history: {response.status_code} - {response.text}")
                    return matches
                
                match_list = response.json()
                
                # Filter matches by date and fetch details
                start_of_day = target_date.replace(hour=0, minute=0, second=0, microsecond=0)
                end_of_day = start_of_day + timedelta(days=1)
                
                for match_entry in match_list.get("history", []):
                    match_id = match_entry.get("matchId")
                    match_start = match_entry.get("gameStartMillis", 0) / 1000
                    match_datetime = datetime.fromtimestamp(match_start, tz=timezone.utc)
                    
                    # Check if match started on target date
                    if start_of_day <= match_datetime < end_of_day:
                        # Fetch full match details
                        match_url = f"https://{platform}.api.riotgames.com/val/match/v1/matches/{match_id}"
                        match_response = await client.get(match_url, headers=self.headers)
                        
                        if match_response.status_code == 200:
                            match_data = match_response.json()
                            matches.append(match_data)
                        else:
                            logger.warning(f"Failed to fetch Valorant match {match_id}: {match_response.status_code}")
                
                logger.info(f"Found {len(matches)} Valorant matches for {target_date.date()}")
                
        except Exception as e:
            logger.error(f"Exception fetching Valorant matches: {str(e)}")
            
        return matches
    
    def calculate_lol_match_duration(self, match_data: Dict) -> Tuple[datetime, datetime, int]:
        """Calculate League of Legends match duration and times."""
        info = match_data.get("info", {})
        
        # Game start time (milliseconds)
        game_start = info.get("gameCreation", 0) / 1000
        game_duration = info.get("gameDuration", 0)  # In seconds for v5
        
        # Handle different duration formats (sometimes it's already in seconds, sometimes milliseconds)
        if game_duration > 10000:  # Likely milliseconds
            game_duration = game_duration / 1000
            
        start_time = datetime.fromtimestamp(game_start, tz=timezone.utc)
        end_time = start_time + timedelta(seconds=game_duration)
        duration_minutes = int(game_duration / 60)
        
        return start_time, end_time, duration_minutes
    
    def calculate_valorant_match_duration(self, match_data: Dict) -> Tuple[datetime, datetime, int]:
        """Calculate Valorant match duration and times."""
        match_info = match_data.get("matchInfo", {})
        
        # Game start time (milliseconds)
        game_start = match_info.get("gameStartMillis", 0) / 1000
        game_length = match_info.get("gameLengthMillis", 0) / 1000  # Convert to seconds
        
        start_time = datetime.fromtimestamp(game_start, tz=timezone.utc)
        end_time = start_time + timedelta(seconds=game_length)
        duration_minutes = int(game_length / 60)
        
        return start_time, end_time, duration_minutes
    
    def get_lol_queue_type(self, queue_id: int) -> str:
        """Map League of Legends queue ID to readable name."""
        queue_mapping = {
            420: "Ranked Solo/Duo",
            440: "Ranked Flex",
            400: "Normal Draft",
            430: "Normal Blind",
            450: "ARAM",
            700: "Clash",
            830: "Co-op vs AI Intro",
            840: "Co-op vs AI Beginner", 
            850: "Co-op vs AI Intermediate",
            900: "ARURF",
            1020: "One for All",
            1090: "Teamfight Tactics",
            1100: "Ranked TFT",
            1400: "Ultimate Spellbook",
            490: "Normal (Quickplay)"
        }
        return queue_mapping.get(queue_id, f"Queue {queue_id}")
    
    def get_valorant_game_mode(self, match_data: Dict) -> str:
        """Extract Valorant game mode from match data."""
        match_info = match_data.get("matchInfo", {})
        mode = match_info.get("mode", "")
        
        mode_mapping = {
            "Competitive": "Competitive",
            "Unrated": "Unrated", 
            "Spikerush": "Spike Rush",
            "Deathmatch": "Deathmatch",
            "Escalation": "Escalation",
            "Replication": "Replication",
            "Snowball": "Snowball Fight",
            "SwiftPlay": "Swiftplay"
        }
        
        return mode_mapping.get(mode, mode)