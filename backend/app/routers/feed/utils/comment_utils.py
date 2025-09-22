from typing import List
from models.schemas import Comment
from utils.memory_cleanup import _cleanup_memory

def organize_comments_flattened(comments: List[Comment], db_data_map: dict[str, dict]) -> List[Comment]:
    """
    Organize comments using proper tree structure (no path compression).
    Memory optimized with explicit cleanup.
    """
    if not comments:
        return []
    
    children_by_parent = {}
    top_level_comments = []
    organized_comments = []
    
    try:
        # Build parent-to-children mapping
        for comment in comments:
            db_data = db_data_map.get(str(comment.id), {})
            parent_id = db_data.get('parent_comment_id')
            
            if parent_id is None:
                # This is a top-level comment
                top_level_comments.append(comment)
            else:
                # This is a reply - add to parent's children list
                parent_id_str = str(parent_id)
                if parent_id_str not in children_by_parent:
                    children_by_parent[parent_id_str] = []
                children_by_parent[parent_id_str].append(comment)
        
        # Sort top-level comments chronologically
        top_level_comments.sort(key=lambda x: x.created_at)
        
        # Recursively build the flat list maintaining tree order
        def add_comment_and_children(comment: Comment, depth: int = 0):
            """Add a comment and all its descendants in tree order"""
            organized_comments.append(comment)
            
            # Add direct children, sorted chronologically
            comment_id_str = str(comment.id)
            if comment_id_str in children_by_parent:
                children = children_by_parent[comment_id_str]
                children.sort(key=lambda x: x.created_at)
                
                for child in children:
                    add_comment_and_children(child, depth + 1)
        
        # Build the organized list starting with top-level comments
        for top_comment in top_level_comments:
            add_comment_and_children(top_comment)
        
        # Cleanup intermediate objects
        _cleanup_memory(children_by_parent, top_level_comments)
        
        return organized_comments
        
    except Exception as e:
        print(f"Error organizing comments: {e}")
        # Cleanup on error
        _cleanup_memory(children_by_parent, top_level_comments, organized_comments)
        return comments  # Return original comments if organization fails 