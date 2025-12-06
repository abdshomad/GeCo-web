"""Image processing utilities"""
import torch
from torchvision import transforms as T
from PIL import Image
import io
from utils.data import resize_and_pad


def process_uploaded_image(image_bytes: bytes) -> tuple:
    """
    Process uploaded image bytes
    
    Returns:
        tuple: (PIL Image, image tensor)
    """
    pil_image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    image_tensor = T.ToTensor()(pil_image)
    return pil_image, image_tensor


def prepare_image_for_inference(
    image_tensor: torch.Tensor,
    bboxes_tensor: torch.Tensor,
    device: torch.device
) -> tuple:
    """
    Prepare image and bounding boxes for model inference
    
    Args:
        image_tensor: Input image tensor
        bboxes_tensor: Bounding boxes tensor
        device: Target device
    
    Returns:
        tuple: (processed_image, processed_bboxes, scale_factor)
    """
    # Resize and pad
    img, bboxes_resized, scale = resize_and_pad(
        image_tensor, bboxes_tensor, full_stretch=False
    )
    
    # Normalize
    normalize = T.Normalize(
        mean=[0.485, 0.456, 0.406],
        std=[0.229, 0.224, 0.225]
    )
    img = normalize(img).unsqueeze(0).to(device)
    bboxes_resized = bboxes_resized.unsqueeze(0).to(device)
    
    return img, bboxes_resized, scale


def convert_bboxes_to_original_coords(
    filtered_boxes: torch.Tensor,
    scale: float,
    img_size: int,
    device: torch.device
) -> list:
    """
    Convert normalized bounding boxes back to original image coordinates
    
    Args:
        filtered_boxes: Normalized bounding boxes [0, 1]
        scale: Scale factor from resize_and_pad
        img_size: Original processed image size
        device: Device of the boxes tensor
    
    Returns:
        list: List of bounding boxes in original coordinates
    """
    # Ensure filtered_boxes is on the correct device
    filtered_boxes = filtered_boxes.to(device)
    scale_tensor = torch.tensor([scale, scale, scale, scale], device=device, dtype=filtered_boxes.dtype)
    # Do computation on device, then move to CPU for conversion to list
    pred_boxes_original = (filtered_boxes / scale_tensor) * img_size
    return pred_boxes_original.cpu().tolist()

