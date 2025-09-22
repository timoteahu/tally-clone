import boto3
import threading
import os
from typing import Optional
import weakref
from utils.memory_optimization import cleanup_memory, disable_print

# Disable verbose printing for performance
print = disable_print()

class AWSClientManager:
    """
    Thread-safe singleton AWS client manager with proper lifecycle management.
    Ensures only ONE instance of each AWS service client exists globally.
    """
    
    _instance = None
    _lock = threading.Lock()
    _clients = {}
    _client_locks = {}
    
    def __new__(cls):
        if cls._instance is None:
            with cls._lock:
                if cls._instance is None:
                    cls._instance = super(AWSClientManager, cls).__new__(cls)
        return cls._instance
    
    def __init__(self):
        # Only initialize once
        if not hasattr(self, '_initialized'):
            self._initialized = True
            print("🔧 AWS Client Manager initialized")
    
    def get_rekognition_client(self) -> Optional[boto3.client]:
        """Get or create the single Rekognition client instance"""
        service_name = 'rekognition'
        
        if service_name not in self._client_locks:
            with self._lock:
                if service_name not in self._client_locks:
                    self._client_locks[service_name] = threading.Lock()
        
        with self._client_locks[service_name]:
            if service_name not in self._clients or self._clients[service_name] is None:
                try:
                    # Create optimized client configuration
                    config = boto3.session.Config(
                        region_name=os.getenv('AWS_REGION', 'us-east-1'),
                        retries={
                            'max_attempts': 2,  # Minimal retries
                            'mode': 'standard'
                        },
                        max_pool_connections=3,  # Limit connection pool
                        read_timeout=30,  # Prevent hanging
                        connect_timeout=10
                    )
                    
                    self._clients[service_name] = boto3.client(
                        service_name,
                        aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
                        aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
                        region_name=os.getenv('AWS_REGION', 'us-east-1'),
                        config=config
                    )
                    print(f"🆕 Created AWS {service_name} client")
                    
                except Exception as e:
                    print(f"❌ Failed to create AWS {service_name} client: {e}")
                    self._clients[service_name] = None
                    return None
        
        return self._clients.get(service_name)
    
    def cleanup_client(self, service_name: str) -> None:
        """Clean up a specific AWS client"""
        if service_name not in self._client_locks:
            return
            
        with self._client_locks[service_name]:
            if service_name in self._clients and self._clients[service_name] is not None:
                try:
                    client = self._clients[service_name]
                    
                    # Close underlying HTTP sessions
                    if hasattr(client, '_client_config'):
                        client._client_config = None
                    if hasattr(client, 'meta') and hasattr(client.meta, 'client'):
                        client.meta.client = None
                    if hasattr(client, '_service_model'):
                        client._service_model = None
                    
                    # Clear from our registry
                    self._clients[service_name] = None
                    
                    # Explicit cleanup
                    cleanup_memory(client)
                    print(f"🧹 Cleaned up AWS {service_name} client")
                    
                except Exception as e:
                    print(f"⚠️ Error cleaning up AWS {service_name} client: {e}")
                    self._clients[service_name] = None
    
    def cleanup_all_clients(self) -> None:
        """Clean up all AWS clients"""
        with self._lock:
            for service_name in list(self._clients.keys()):
                self.cleanup_client(service_name)
            print("🧹 All AWS clients cleaned up")
    
    def get_client_status(self) -> dict:
        """Get status of all managed clients"""
        status = {}
        for service_name, client in self._clients.items():
            status[service_name] = "active" if client is not None else "inactive"
        return status

# Global singleton instance
_aws_manager = AWSClientManager()

def get_aws_rekognition_client() -> Optional[boto3.client]:
    """Get the singleton AWS Rekognition client"""
    return _aws_manager.get_rekognition_client()

def cleanup_aws_clients() -> None:
    """Clean up all AWS clients (useful for testing/shutdown)"""
    _aws_manager.cleanup_all_clients()

def get_aws_client_status() -> dict:
    """Get status of all AWS clients"""
    return _aws_manager.get_client_status()

class AWSResponseCleaner:
    """
    Context manager for automatic AWS response cleanup.
    Use this to ensure AWS responses are properly cleaned up after use.
    """
    
    def __init__(self):
        self._responses = []
    
    def __enter__(self):
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb):
        self.cleanup_all()
    
    def register(self, response: dict):
        """Register an AWS response for cleanup"""
        if response:
            self._responses.append(response)
        return response
    
    def cleanup_response(self, response: dict) -> None:
        """Aggressively clean up a single AWS response"""
        if not response:
            return
            
        try:
            # Clear all nested structures recursively
            self._recursive_clear(response)
            response.clear()
        except Exception as e:
            print(f"Error cleaning AWS response: {e}")
        finally:
            cleanup_memory(response)
    
    def _recursive_clear(self, obj):
        """Recursively clear nested dictionaries and lists"""
        if isinstance(obj, dict):
            for key, value in list(obj.items()):
                if isinstance(value, (dict, list)):
                    self._recursive_clear(value)
                del obj[key]
        elif isinstance(obj, list):
            for item in obj:
                if isinstance(item, (dict, list)):
                    self._recursive_clear(item)
            obj.clear()
    
    def cleanup_all(self) -> None:
        """Clean up all registered responses"""
        for response in self._responses:
            self.cleanup_response(response)
        self._responses.clear()
        cleanup_memory(self._responses)

# Convenience function for one-off response cleanup
def cleanup_aws_response(response: dict) -> None:
    """Clean up a single AWS response immediately"""
    with AWSResponseCleaner() as cleaner:
        cleaner.cleanup_response(response) 