import os
import boto3
from typing import Optional
import logging

logger = logging.getLogger(__name__)

# Singleton boto3 clients
_rekognition_client: Optional[boto3.client] = None
_s3_client: Optional[boto3.client] = None

def get_rekognition_client():
    """
    Get or create a singleton AWS Rekognition client.
    This ensures we reuse the same client instance across all requests,
    preventing memory leaks from creating new clients repeatedly.
    """
    global _rekognition_client
    
    if _rekognition_client is None:
        try:
            _rekognition_client = boto3.client(
                'rekognition',
                aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
                aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
                region_name=os.getenv('AWS_REGION', 'us-east-1')
            )
            logger.info("✅ Created singleton Rekognition client")
        except Exception as e:
            logger.error(f"Failed to create Rekognition client: {e}")
            return None
    
    return _rekognition_client

def get_s3_client():
    """
    Get or create a singleton AWS S3 client.
    For future use when S3 operations are needed.
    """
    global _s3_client
    
    if _s3_client is None:
        try:
            _s3_client = boto3.client(
                's3',
                aws_access_key_id=os.getenv('AWS_ACCESS_KEY_ID'),
                aws_secret_access_key=os.getenv('AWS_SECRET_ACCESS_KEY'),
                region_name=os.getenv('AWS_REGION', 'us-east-1')
            )
            logger.info("✅ Created singleton S3 client")
        except Exception as e:
            logger.error(f"Failed to create S3 client: {e}")
            return None
    
    return _s3_client

def reset_aws_clients():
    """
    Reset AWS clients (useful for testing or forced reconnection).
    This should rarely be needed in production.
    """
    global _rekognition_client, _s3_client
    
    if _rekognition_client:
        try:
            # boto3 clients don't have an explicit close method, but we can
            # remove the reference and let garbage collection handle it
            _rekognition_client = None
            logger.info("Reset Rekognition client")
        except Exception as e:
            logger.error(f"Error resetting Rekognition client: {e}")
    
    if _s3_client:
        try:
            _s3_client = None
            logger.info("Reset S3 client")
        except Exception as e:
            logger.error(f"Error resetting S3 client: {e}")