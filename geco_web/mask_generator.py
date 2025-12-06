"""Mask generation utilities"""
import torch
from torchvision import transforms as T
from PIL import Image
import io
import base64
import numpy as np


def generate_mask_image(
    masks: torch.Tensor,
    box_v: torch.Tensor,
    threshold_value: float,
    img_shape: tuple,
    scale: float,
    original_height: int,
    original_width: int,
    device: torch.device
) -> str:
    """
    Generate segmentation mask image and return as base64 string
    
    Args:
        masks: Mask tensor from model output
        box_v: Box visibility scores
        threshold_value: Threshold for filtering
        img_shape: Shape of processed image (batch, channels, height, width)
        scale: Scale factor from resize_and_pad
        original_height: Original image height
        original_width: Original image width
    
    Returns:
        str: Base64 encoded PNG image data URL
    """
    idx = 0
    # Ensure masks and box_v are on the same device
    masks = masks.to(device)
    box_v = box_v.to(device)
    masks_ = masks[idx][(box_v > threshold_value)[0]]
    
    if len(masks_) == 0:
        raise ValueError("No masks to generate")
    
    N_masks = masks_.shape[0]
    indices = torch.randint(
        1, N_masks + 1,
        (1, N_masks),
        device=device
    ).view(-1, 1, 1)
    
    combined_mask = (masks_ * indices).sum(dim=0)
    
    # Resize mask to original image size
    mask_resize = T.Resize(
        (int(img_shape[2] / scale), int(img_shape[3] / scale)),
        interpolation=T.InterpolationMode.NEAREST
    )
    mask_display = mask_resize(combined_mask.cpu().unsqueeze(0))[0]
    mask_display = mask_display[:original_height, :original_width]
    
    # Convert mask to image
    mask_array = mask_display.numpy().astype(np.uint8)
    mask_image = Image.fromarray(mask_array, mode='L')
    
    # Convert to base64
    buffer = io.BytesIO()
    mask_image.save(buffer, format='PNG')
    mask_base64 = base64.b64encode(buffer.getvalue()).decode('utf-8')
    
    return f"data:image/png;base64,{mask_base64}"

