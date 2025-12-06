"""Sample images management module"""
import os
from pathlib import Path
from typing import List, Dict


def get_sample_images() -> List[Dict[str, str]]:
    """
    Get list of sample images from material folder
    
    Returns:
        List of dictionaries with image info (name, path, url)
    """
    material_dir = Path("material")
    if not material_dir.exists():
        return []
    
    sample_images = []
    image_extensions = {'.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'}
    
    for file_path in sorted(material_dir.iterdir()):
        if file_path.is_file() and file_path.suffix.lower() in image_extensions:
            sample_images.append({
                "name": file_path.name,
                "path": str(file_path),
                "url": f"/api/sample-images/{file_path.name}"
            })
    
    return sample_images


def get_sample_image_path(image_name: str) -> str:
    """
    Get full path to a sample image
    
    Args:
        image_name: Name of the image file
    
    Returns:
        Full path to the image file
    
    Raises:
        FileNotFoundError: If image doesn't exist
    """
    image_path = Path("material") / image_name
    
    # Security check: ensure path is within material directory
    try:
        image_path.resolve().relative_to(Path("material").resolve())
    except ValueError:
        raise FileNotFoundError(f"Invalid image path: {image_name}")
    
    if not image_path.exists():
        raise FileNotFoundError(f"Sample image not found: {image_name}")
    
    return str(image_path)

