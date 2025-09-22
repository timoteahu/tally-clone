"""
ML Training Data Service

Provides easy access to training data for CoreML model development.
"""

from typing import List, Dict, Any, Optional
from supabase._async.client import AsyncClient
import json
import os
from datetime import datetime, timedelta

class MLTrainingService:
    """Service for managing ML training data"""
    
    def __init__(self, supabase: AsyncClient):
        self.supabase = supabase
    
    async def get_training_data_summary(self) -> Dict[str, Any]:
        """Get summary statistics of available training data"""
        
        # Get counts by habit type and validity
        result = await self.supabase.table("ml_training_data")\
            .select("habit_type, is_valid, COUNT(*)")\
            .execute()
        
        summary = {}
        for row in result.data:
            habit_type = row['habit_type']
            is_valid = row['is_valid']
            count = row['count']
            
            if habit_type not in summary:
                summary[habit_type] = {'valid': 0, 'invalid': 0, 'total': 0}
            
            if is_valid:
                summary[habit_type]['valid'] = count
            else:
                summary[habit_type]['invalid'] = count
            summary[habit_type]['total'] += count
        
        return summary
    
    async def get_training_data(
        self, 
        habit_type: Optional[str] = None,
        min_confidence: float = 0.6,
        exclude_screens: bool = True,
        limit: Optional[int] = None
    ) -> List[Dict[str, Any]]:
        """Get training data filtered by criteria"""
        
        query = self.supabase.table("ml_training_data")\
            .select("*")\
            .gte("confidence", min_confidence)\
            .order("created_at", desc=True)
        
        if habit_type:
            query = query.eq("habit_type", habit_type)
        
        if exclude_screens:
            query = query.eq("is_screen", False)
        
        if limit:
            query = query.limit(limit)
        
        result = await query.execute()
        return result.data
    
    async def export_training_manifest(
        self, 
        output_path: str = "training_manifest.json",
        min_confidence: float = 0.6,
        exclude_screens: bool = True
    ) -> str:
        """Export training data manifest for CoreML training"""
        
        # Get all training data above confidence threshold
        query = self.supabase.table("ml_training_data")\
            .select("*")\
            .gte("confidence", min_confidence)\
            .order("habit_type, is_valid")
        
        if exclude_screens:
            query = query.eq("is_screen", False)
        
        result = await query.execute()
        
        # Organize by habit type and validity
        manifest = {}
        for record in result.data:
            habit_type = record['habit_type']
            is_valid = record['is_valid']
            
            if habit_type not in manifest:
                manifest[habit_type] = {'valid': [], 'invalid': []}
            
            data_point = {
                'id': record['id'],
                'image_path': record['image_path'],
                'confidence': record['confidence'],
                'is_screen': record['is_screen'],
                'created_at': record['created_at']
            }
            
            if is_valid:
                manifest[habit_type]['valid'].append(data_point)
            else:
                manifest[habit_type]['invalid'].append(data_point)
        
        # Add summary statistics
        manifest['_metadata'] = {
            'exported_at': datetime.utcnow().isoformat(),
            'min_confidence': min_confidence,
            'exclude_screens': exclude_screens,
            'total_images': sum(
                len(data['valid']) + len(data['invalid']) 
                for data in manifest.values() 
                if isinstance(data, dict)
            )
        }
        
        # Save manifest
        with open(output_path, 'w') as f:
            json.dump(manifest, f, indent=2)
        
        return output_path
    
    async def download_training_images(
        self,
        manifest_path: str = "training_manifest.json",
        output_dir: str = "training_data"
    ):
        """Download all training images based on manifest"""
        
        with open(manifest_path, 'r') as f:
            manifest = json.load(f)
        
        for habit_type, data in manifest.items():
            if habit_type == '_metadata':
                continue
            
            # Create directories
            os.makedirs(f"{output_dir}/{habit_type}/valid", exist_ok=True)
            os.makedirs(f"{output_dir}/{habit_type}/invalid", exist_ok=True)
            
            # Download valid images
            for item in data['valid']:
                image_path = item['image_path']
                local_path = f"{output_dir}/{habit_type}/valid/{os.path.basename(image_path)}"
                
                try:
                    image_data = await self.supabase.storage.from_("ml-training").download(image_path)
                    with open(local_path, 'wb') as f:
                        f.write(image_data)
                    print(f"Downloaded: {local_path}")
                except Exception as e:
                    print(f"Failed to download {image_path}: {e}")
            
            # Download invalid images
            for item in data['invalid']:
                image_path = item['image_path']
                local_path = f"{output_dir}/{habit_type}/invalid/{os.path.basename(image_path)}"
                
                try:
                    image_data = await self.supabase.storage.from_("ml-training").download(image_path)
                    with open(local_path, 'wb') as f:
                        f.write(image_data)
                    print(f"Downloaded: {local_path}")
                except Exception as e:
                    print(f"Failed to download {image_path}: {e}")
    
    async def cleanup_old_training_data(self, days: int = 90):
        """Remove training data older than specified days"""
        
        cutoff_date = datetime.utcnow() - timedelta(days=days)
        
        # Get old records
        old_records = await self.supabase.table("ml_training_data")\
            .select("id, image_path")\
            .lt("created_at", cutoff_date.isoformat())\
            .execute()
        
        # Delete images from storage
        for record in old_records.data:
            try:
                await self.supabase.storage.from_("ml-training").remove(record['image_path'])
            except Exception as e:
                print(f"Failed to delete image {record['image_path']}: {e}")
        
        # Delete records from database
        await self.supabase.table("ml_training_data")\
            .delete()\
            .lt("created_at", cutoff_date.isoformat())\
            .execute()
        
        return len(old_records.data)