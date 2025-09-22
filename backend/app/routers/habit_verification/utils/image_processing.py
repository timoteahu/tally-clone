import io
from PIL import Image, ImageOps
from typing import Tuple
from utils.memory_optimization import cleanup_memory, disable_print

# Disable verbose printing for performance
print = disable_print()

class OptimizedImageProcessor:
    """
    Memory-optimized image processor with automatic cleanup.
    Designed for processing images for AWS Rekognition with minimal memory footprint.
    """
    
    def __init__(self):
        self._temp_objects = []
        
    def __enter__(self):
        return self
        
    def __exit__(self, exc_type, exc_val, exc_tb):
        self._cleanup()
        
    def _cleanup(self):
        """Clean up all temporary objects"""
        for obj in self._temp_objects:
            try:
                if hasattr(obj, 'close'):
                    obj.close()
                elif isinstance(obj, io.BytesIO):
                    obj.seek(0)
                    obj.truncate(0)
                cleanup_memory(obj)
            except Exception:
                pass
        self._temp_objects.clear()
    
    def register(self, obj):
        """Register object for cleanup"""
        if obj is not None:
            self._temp_objects.append(obj)
        return obj
        
    def process_for_rekognition(
        self, 
        image_bytes: bytes, 
        max_size: Tuple[int, int] = (512, 512), 
        quality: int = 75
    ) -> bytes:
        """
        Process image for AWS Rekognition with balanced quality/memory.
        
        Args:
            image_bytes: Original image bytes
            max_size: Maximum dimensions (width, height)
            quality: JPEG quality (1-100)
            
        Returns:
            Processed image bytes optimized for Rekognition
        """
        
        input_buffer = self.register(io.BytesIO(image_bytes))
        
        try:
            with Image.open(input_buffer) as img:
                # Handle EXIF orientation to ensure proper image orientation
                try:
                    img = ImageOps.exif_transpose(img)
                except Exception:
                    # Continue if EXIF processing fails
                    pass
                
                # Convert to RGB if needed (Rekognition requires RGB)
                if img.mode != 'RGB':
                    img = img.convert('RGB')
                
                # Resize if image is larger than max_size
                if img.width > max_size[0] or img.height > max_size[1]:
                    img.thumbnail(max_size, Image.Resampling.LANCZOS)
                
                # Save with optimized settings for Rekognition
                output_buffer = self.register(io.BytesIO())
                img.save(
                    output_buffer, 
                    format="JPEG", 
                    quality=quality, 
                    optimize=True,
                    progressive=True  # Better compression for larger images
                )
                
                return output_buffer.getvalue()
                
        except Exception as e:
            print(f"Error processing image: {e}")
            raise
    
    def get_image_info(self, image_bytes: bytes) -> dict:
        """
        Get basic information about an image without keeping it in memory.
        
        Args:
            image_bytes: Image bytes to analyze
            
        Returns:
            Dict with image information
        """
        input_buffer = self.register(io.BytesIO(image_bytes))
        
        try:
            with Image.open(input_buffer) as img:
                return {
                    "format": img.format,
                    "mode": img.mode,
                    "size": img.size,
                    "width": img.width,
                    "height": img.height,
                    "has_transparency": img.mode in ('RGBA', 'LA') or 'transparency' in img.info
                }
        except Exception as e:
            print(f"Error getting image info: {e}")
            return {"error": str(e)}

def process_single_image_optimized(
    image_bytes: bytes, 
    max_size: Tuple[int, int] = (512, 512),
    quality: int = 75
) -> bytes:
    """
    Standalone function to process a single image with automatic cleanup.
    Use this for one-off image processing.
    
    Args:
        image_bytes: Original image bytes
        max_size: Maximum dimensions (width, height)
        quality: JPEG quality (1-100)
        
    Returns:
        Processed image bytes
    """
    with OptimizedImageProcessor() as processor:
        return processor.process_for_rekognition(image_bytes, max_size, quality)

def validate_image_format(image_bytes: bytes) -> bool:
    """
    Validate if image bytes represent a valid image format.
    
    Args:
        image_bytes: Image bytes to validate
        
    Returns:
        True if valid image, False otherwise
    """
    try:
        with OptimizedImageProcessor() as processor:
            info = processor.get_image_info(image_bytes)
            return "error" not in info and info.get("format") is not None
    except Exception:
        return False

def get_optimized_dimensions(width: int, height: int, max_size: Tuple[int, int]) -> Tuple[int, int]:
    """
    Calculate optimized dimensions for an image while maintaining aspect ratio.
    
    Args:
        width: Original width
        height: Original height
        max_size: Maximum allowed dimensions (width, height)
        
    Returns:
        Optimized dimensions (width, height)
    """
    max_width, max_height = max_size
    
    # If image is already smaller, return original size
    if width <= max_width and height <= max_height:
        return (width, height)
    
    # Calculate aspect ratio
    aspect_ratio = width / height
    
    # Calculate new dimensions based on limiting dimension
    if width > height:
        # Width is the limiting factor
        new_width = max_width
        new_height = int(max_width / aspect_ratio)
    else:
        # Height is the limiting factor
        new_height = max_height
        new_width = int(max_height * aspect_ratio)
    
    return (new_width, new_height) 