"""Inference logic module"""
import torch
from torchvision import ops
import json
from typing import List, Dict, Optional
from geco_web.model_manager import get_model_manager
from geco_web.image_processing import (
    process_uploaded_image,
    prepare_image_for_inference,
    convert_bboxes_to_original_coords
)
from geco_web.mask_generator import generate_mask_image


def parse_bboxes(bboxes_json: str) -> List[List[float]]:
    """
    Parse bounding boxes from JSON string
    
    Args:
        bboxes_json: JSON string of bounding boxes
    
    Returns:
        List of bounding boxes [[x1, y1, x2, y2], ...]
    """
    bboxes_list = json.loads(bboxes_json)
    if not bboxes_list:
        raise ValueError("At least one bounding box is required")
    return bboxes_list


def apply_nms(
    outputs: Dict,
    threshold: float,
    device: torch.device,
    idx: int = 0
) -> torch.Tensor:
    """
    Apply Non-Maximum Suppression to model outputs
    
    Args:
        outputs: Model output dictionary
        threshold: Detection threshold
        device: Device to ensure tensors are on
        idx: Batch index
    
    Returns:
        Filtered bounding boxes tensor
    """
    box_v = outputs[idx]['box_v'].to(device)
    pred_boxes = outputs[idx]['pred_boxes'].to(device)
    threshold_value = box_v.max() / threshold
    
    keep = ops.nms(
        pred_boxes[box_v > threshold_value],
        box_v[box_v > threshold_value],
        0.5
    )
    
    filtered_boxes = (pred_boxes[box_v > threshold_value])[keep]
    filtered_boxes = torch.clamp(filtered_boxes, 0, 1)
    
    return filtered_boxes, threshold_value


def run_inference(
    image_bytes: bytes,
    bboxes_json: str,
    output_masks: bool = False,
    threshold: float = 4.0
) -> Dict:
    """
    Run inference on uploaded image with bounding boxes
    
    Args:
        image_bytes: Uploaded image file bytes
        bboxes_json: JSON string of bounding boxes
        output_masks: Whether to return segmentation masks
        threshold: Threshold for filtering detections
    
    Returns:
        Dictionary with inference results
    """
    model_manager = get_model_manager()
    
    # Ensure model is loaded
    if not model_manager.is_loaded():
        try:
            model_manager.load_model()
        except FileNotFoundError as e:
            raise FileNotFoundError(
                f"Model file not found. Please ensure GeCo.pth is available. "
                f"Original error: {e}"
            )
    
    model = model_manager.get_model()
    device = model_manager.get_device()
    
    # Parse bounding boxes
    bboxes_list = parse_bboxes(bboxes_json)
    
    # Process image
    pil_image, image_tensor = process_uploaded_image(image_bytes)
    
    # Convert bboxes to tensor
    bboxes_tensor = torch.tensor(bboxes_list, dtype=torch.float32)
    
    # Prepare for inference
    img, bboxes_resized, scale = prepare_image_for_inference(
        image_tensor, bboxes_tensor, device
    )
    
    # Run inference
    with torch.no_grad():
        outputs, _, _, _, masks = model(img, bboxes_resized)
    
    # Apply NMS
    filtered_boxes, threshold_value = apply_nms(outputs, threshold, device)
    
    # Convert boxes back to original image coordinates
    boxes_list = convert_bboxes_to_original_coords(
        filtered_boxes, scale, img.shape[-1], device
    )
    
    count = len(boxes_list)
    
    # Prepare response
    result = {
        "count": count,
        "boxes": boxes_list,
        "image_width": pil_image.width,
        "image_height": pil_image.height
    }
    
    # Generate mask image if requested
    if output_masks and masks is not None:
        try:
            box_v = outputs[0]['box_v'].to(device)
            mask_base64 = generate_mask_image(
                masks=masks,
                box_v=box_v,
                threshold_value=threshold_value,
                img_shape=img.shape,
                scale=scale,
                original_height=pil_image.height,
                original_width=pil_image.width,
                device=device
            )
            result["mask"] = mask_base64
        except Exception as e:
            print(f"Warning: Could not generate mask: {e}")
    
    return result

