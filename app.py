"""Main FastAPI application"""
from fastapi import FastAPI, File, UploadFile, Form, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse, FileResponse
from fastapi.staticfiles import StaticFiles
from geco_web.model_manager import get_model_manager
from geco_web.inference import run_inference
from geco_web.sample_images import get_sample_images, get_sample_image_path
import traceback

app = FastAPI(title="GeCo Object Counting Demo")

# Mount static files
app.mount("/static", StaticFiles(directory="static"), name="static")


@app.on_event("startup")
async def startup_event():
    """Load model on startup"""
    model_manager = get_model_manager()
    try:
        # Try to load model, but don't fail if it's not available
        model_manager.load_model()
    except FileNotFoundError as e:
        print(f"Warning: Model file not found: {e}")
        print("Model will be loaded on first inference request if available")
    except Exception as e:
        print(f"Warning: Could not load model on startup: {e}")
        print("Model will be loaded on first request")


@app.get("/", response_class=HTMLResponse)
async def read_root():
    """Serve the main HTML page"""
    with open("static/index.html", "r") as f:
        return HTMLResponse(content=f.read())


@app.post("/api/infer")
async def infer(
    image: UploadFile = File(...),
    bboxes: str = Form(...),
    output_masks: bool = Form(False),
    threshold: float = Form(4.0)
):
    """
    Run inference on uploaded image with bounding boxes
    
    Args:
        image: Uploaded image file
        bboxes: JSON string of bounding boxes [[x1, y1, x2, y2], ...]
        output_masks: Whether to return segmentation masks
        threshold: Threshold for filtering detections
    """
    try:
        image_bytes = await image.read()
        result = run_inference(
            image_bytes=image_bytes,
            bboxes_json=bboxes,
            output_masks=output_masks,
            threshold=threshold
        )
        return JSONResponse(content=result)
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    except Exception as e:
        traceback.print_exc()
        raise HTTPException(status_code=500, detail=f"Inference error: {str(e)}")


@app.get("/api/sample-images")
async def list_sample_images():
    """Get list of available sample images"""
    return JSONResponse(content={"images": get_sample_images()})


@app.get("/api/sample-images/{image_name}")
async def get_sample_image(image_name: str):
    """Get a sample image file"""
    try:
        image_path = get_sample_image_path(image_name)
        return FileResponse(
            image_path,
            media_type="image/jpeg",
            filename=image_name
        )
    except FileNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))


@app.get("/api/health")
async def health():
    """Health check endpoint"""
    model_manager = get_model_manager()
    return {
        "status": "ok",
        "model_loaded": model_manager.is_loaded(),
        "device": str(model_manager.get_device()) if model_manager.is_loaded() else None
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
