import gc

def _cleanup_memory(*objects):
    """Explicitly cleanup memory for large objects"""
    for obj in objects:
        if obj is not None:
            del obj
    gc.collect()